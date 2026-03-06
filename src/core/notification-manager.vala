/*
 * Copyright (c) 2023-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    public interface NotificationsProvider : Ft.Provider
    {
        public abstract string name { get; }
        public abstract string vendor { get; }
        public abstract string version { get; }
        public abstract bool   has_actions { get; }
    }


    private enum NotificationType
    {
        NULL,
        TIME_BLOCK_ABOUT_TO_END,
        TIME_BLOCK_ENDED,
        TIME_BLOCK_STARTED,
        TIME_BLOCK_RUNNING,
        CONFIRM_ADVANCEMENT
    }


    public interface NotificationBackend : GLib.Object
    {
        public abstract void withdraw_notification (string id);

        public abstract void send_notification (string?           id,
                                                GLib.Notification notification);
    }


    private class DefaultNotificationBackend : GLib.Object, Ft.NotificationBackend
    {
        private GLib.Application? application = null;

        construct
        {
            this.application = GLib.Application.get_default ();
        }

        public void withdraw_notification (string id)
        {
            this.application?.withdraw_notification (id);
        }

        public void send_notification (string?           id,
                                       GLib.Notification notification)
        {
            this.application?.send_notification (id, notification);
        }

        public override void dispose ()
        {
            this.application = null;

            base.dispose ();
        }
    }


    /**
     * `NotificationManager` manages notification popups and the screen overlay.
     */
    [SingleInstance]
    public class NotificationManager : GLib.Object
    {
        /**
         * Notifications may contain remaining time. As we can't update it gracefully the most sensible way is to
         * dismiss the notification when it's getting stale. The timeout is higher to allow urgent notifications be
         * shown. Unfortunately, we may dismiss the notification before it gets acknowledged.
         */
        private const uint WITHDRAW_TIMEOUT_SECONDS = 30;

        private const uint SCREEN_OVERLAY_OPEN_TIMEOUT = 1000;

        private const int64 TIME_BLOCK_ABOUT_TO_END_MIN_DURATION = 10 * Ft.Interval.SECOND;
        private const int64 TIME_BLOCK_ABOUT_TO_END_MAX_DURATION = 15 * Ft.Interval.SECOND;
        private const int64 TIME_BLOCK_ABOUT_TO_END_TOLERANCE = 5 * Ft.Interval.SECOND;

        public Ft.Timer timer {
            get {
                return this._timer;
            }
            construct {
                this._timer = value;

                this.previous_timer_state = this._timer.state.copy ();
                this.timer_state_changed_id = this._timer.state_changed.connect (
                        this.on_timer_state_changed);
            }
        }

        public Ft.SessionManager session_manager {
            get {
                return this._session_manager;
            }
            construct {
                this._session_manager = value;

                this.session_manager_confirm_advancement_id = this._session_manager.confirm_advancement.connect (
                        this.on_session_manager_confirm_advancement);
            }
        }

        public Ft.NotificationBackend backend {
            get {
                return this._backend;
            }
            construct {
                this._backend = value;
            }
        }

        private Ft.Timer?               _timer = null;
        private Ft.SessionManager?      _session_manager = null;
        private Ft.NotificationBackend? _backend = null;
        private GLib.Settings?          settings = null;
        private Ft.IdleMonitor?         idle_monitor = null;
        private Ft.LockScreen?          lock_screen = null;
        private Ft.TimerState           previous_timer_state;
        private ulong                   timer_state_changed_id = 0;
        private ulong                   timer_tick_id = 0;
        private ulong                   settings_changed_id = 0;
        private ulong                   session_manager_confirm_advancement_id = 0;
        private bool                    screen_overlay_active = false;
        private int                     screen_overlay_inhibit_count = 0;
        private uint                    screen_overlay_open_timeout_id = 0U;
        private uint                    withdraw_timeout_id = 0U;
        private uint                    lock_screen_idle_id = 0U;
        private uint                    reopen_screen_overlay_idle_id = 0U;
        private GLib.Notification?      notification = null;
        private Ft.NotificationType     notification_type = NotificationType.NULL;
        private weak Ft.TimeBlock?      notification_time_block = null;
        private bool                    debug = false;

        public NotificationManager ()
        {
            GLib.Object (
                timer: Ft.Timer.get_default (),
                session_manager: Ft.SessionManager.get_default (),
                backend: new Ft.DefaultNotificationBackend ()
            );
        }

        public NotificationManager.with_backend (Ft.NotificationBackend backend)
        {
            GLib.Object (
                timer: Ft.Timer.get_default (),
                session_manager: Ft.SessionManager.get_default (),
                backend: backend
            );
        }

        construct
        {
            this.settings = Ft.get_settings ();
            this.idle_monitor = new Ft.IdleMonitor ();
            this.lock_screen = new Ft.LockScreen ();
            this.debug = true;  // Ft.is_test ();

            this.settings_changed_id = this.settings.changed.connect (this.on_settings_changed);

            this.schedule_announcements ();
            this.update (true);

            if (this.notification == null) {
                this._backend.withdraw_notification ("timer");
            }
        }

        private string format_remaining_time (Ft.TimeBlock time_block)
        {
            var timestamp = this._timer.get_last_tick_time ();
            var seconds = Ft.Timestamp.to_seconds (time_block.calculate_remaining (timestamp));
            var seconds_uint = (uint) Ft.round_seconds (seconds);

            // translators: time remaining eg. "3 minutes 50 seconds remaining"
            return _("%s remaining").printf (Ft.format_time (seconds_uint));
        }

        /**
         * Check basic conditions if the screen overlay is possible for the current timer state.
         */
        private bool can_open_screen_overlay_later ()
        {
            if (!this._timer.is_running ()) {
                return false;
            }

            var current_time_block = this._session_manager.current_time_block;
            if (current_time_block == null || !current_time_block.state.is_break ()) {
                return false;
            }

            if (!this.settings.get_boolean ("screen-overlay")) {
                return false;
            }

            return true;
        }

        /**
         * Return whether screen overlay can be opened right now.
         */
        private bool can_open_screen_overlay ()
        {
            if (this.screen_overlay_inhibit_count > 0) {
                return false;
            }

            if (!this.can_open_screen_overlay_later ()) {
                return false;
            }

            // Don't interrupt the current announcement.
            if (this.notification_type == Ft.NotificationType.TIME_BLOCK_ABOUT_TO_END &&
                this.notification_time_block != null &&
                this.notification_time_block.state.is_break ())
            {
                return false;
            }

            // TODO: check if we're not interrupting a drag-and-drop or a videocall

            return true;
        }

        private void on_lock_screen_idle ()
        {
            if (!this.screen_overlay_active) {
                return;
            }

            this.lock_screen.activate ();
        }

        private void on_reopen_screen_overlay_idle ()
        {
            if (this.screen_overlay_active) {
                GLib.debug ("Screen overlay has already opened.");
                return;
            }

            if (!this.can_open_screen_overlay ()) {
                GLib.debug ("Screen overlay not allowed.");
                return;
            }

            // Don't reopen if close to announcement notification.
            var timestamp = this._timer.get_current_time ();
            var about_to_end_threshold = this.get_about_to_end_duration () + TIME_BLOCK_ABOUT_TO_END_TOLERANCE;

            if (this._timer.calculate_remaining (timestamp) <= about_to_end_threshold) {
                return;
            }

            // Request the overlay
            this.emit_request_screen_overlay_open ();
        }

        private bool add_lock_screen_idle_watch ()
        {
            var lock_delay = Ft.Timestamp.from_milliseconds_uint (
                    this.settings.get_uint ("screen-overlay-lock-delay") * 1000);

            if (this.lock_screen_idle_id == 0 && lock_delay > 0 && this.idle_monitor.enabled) {
                this.lock_screen_idle_id = this.idle_monitor.add_idle_watch (lock_delay,
                                                                             this.on_lock_screen_idle,
                                                                             GLib.get_monotonic_time ());
                return this.lock_screen_idle_id != 0;
            }

            return false;
        }

        private bool remove_lock_screen_idle_watch ()
        {
            if (this.lock_screen_idle_id != 0) {
                this.idle_monitor.remove_watch (this.lock_screen_idle_id);
                this.lock_screen_idle_id = 0;
                return true;
            }

            return false;
        }

        private bool add_reopen_screen_overlay_idle_watch ()
        {
            if (this.reopen_screen_overlay_idle_id != 0) {
                return false;
            }

            if (!this.idle_monitor.enabled ||
                !this.can_open_screen_overlay_later ())
            {
                return false;
            }

            var reopen_delay = Ft.Timestamp.from_milliseconds_uint (
                    this.settings.get_uint ("screen-overlay-reopen-delay") * 1000U);

            this.reopen_screen_overlay_idle_id = this.idle_monitor.add_idle_watch (
                    reopen_delay,
                    this.on_reopen_screen_overlay_idle,
                    GLib.get_monotonic_time ());

            return true;
        }

        private bool remove_reopen_screen_overlay_idle_watch ()
        {
            if (this.reopen_screen_overlay_idle_id == 0) {
                return false;  // already removed
            }

            this.idle_monitor.remove_watch (this.reopen_screen_overlay_idle_id);
            this.reopen_screen_overlay_idle_id = 0;

            return true;
        }

        private void reset_reopen_screen_overlay_idle_watch ()
        {
            this.remove_reopen_screen_overlay_idle_watch ();
            this.add_reopen_screen_overlay_idle_watch ();
        }

        private void remove_withdraw_timeout ()
        {
            if (this.withdraw_timeout_id != 0U) {
                GLib.Source.remove (this.withdraw_timeout_id);
                this.withdraw_timeout_id = 0U;
            }
        }

        private void withdraw_notifications ()
        {
            this.remove_withdraw_timeout ();

            if (this.notification == null) {
                return;
            }

            this._backend.withdraw_notification ("timer");

            this.notification = null;
            this.notification_type = Ft.NotificationType.NULL;
            this.notification_time_block = null;
        }

        private void schedule_withdraw_notifications ()
        {
            this.remove_withdraw_timeout ();

            // TODO: ensure user is active / acknowledged notification

            this.withdraw_timeout_id = GLib.Timeout.add_seconds (
                WITHDRAW_TIMEOUT_SECONDS,
                () => {
                    this.withdraw_timeout_id = 0U;
                    this.withdraw_notifications ();

                    return GLib.Source.REMOVE;
                }
            );
            GLib.Source.set_name_by_id (this.withdraw_timeout_id,
                                        "Ft.NotificationManager.schedule_withdraw_notifications");
        }

        private GLib.Notification create_notification (string title,
                                                       string body,
                                                       bool   activate_screen_overlay = false)
        {
            var notification = new GLib.Notification (title);
            notification.set_priority (GLib.NotificationPriority.HIGH);

            if (activate_screen_overlay) {
                notification.set_default_action ("app.screen-overlay");
            }
            else {
                notification.set_default_action_and_target_value ("app.window",
                                                                  new GLib.Variant.string ("timer"));
            }

            if (body != "") {
                notification.set_body (body);
            }

            // try {
            //     notification.set_icon (GLib.Icon.new_for_string (Config.PACKAGE_NAME));
            // }
            // catch (GLib.Error error) {
            //     GLib.warning (error.message);
            // }

            return notification;
        }

        /**
         * Show notification informing that the time-block has started.
         */
        private void notify_time_block_started (Ft.TimeBlock time_block)
        {
            var title = "";
            var body = this.format_remaining_time (time_block);

            switch (time_block.state)
            {
                case Ft.State.POMODORO:
                    title = _("Pomodoro");
                    break;

                case Ft.State.BREAK:
                    title = _("Take a break");
                    break;

                case Ft.State.SHORT_BREAK:
                    title = _("Take a short break");
                    break;

                case Ft.State.LONG_BREAK:
                    title = _("Take a long break");
                    break;

                default:
                    assert_not_reached ();
            }

            this.notification = this.create_notification (
                    title,
                    body,
                    time_block.state.is_break ());
            this.notification_type = Ft.NotificationType.TIME_BLOCK_STARTED;
            this.notification_time_block = time_block;

            if (this.debug) {
                this.notification.set_data<string> ("hash", @"$(time_block.state.to_string()):time-block-started");
            }

            this._backend.send_notification ("timer", this.notification);

            this.schedule_withdraw_notifications ();
        }

        /**
         * Show notification with current state and remaining time.
         */
        private void notify_time_block_running (Ft.TimeBlock time_block)
        {
            var title = time_block.state.get_label ();
            var body = this.format_remaining_time (time_block);

            this.notification = this.create_notification (
                    title,
                    body,
                    time_block.state.is_break ());
            this.notification_type = Ft.NotificationType.TIME_BLOCK_RUNNING;
            this.notification_time_block = time_block;

            if (this.debug) {
                var timestamp = this._timer.get_last_tick_time ();
                this.notification.set_data<string> (
                        "hash",
                        @"$(time_block.state.to_string()):time-block-running:$(timestamp)");
            }

            this._backend.send_notification ("timer", this.notification);

            this.schedule_withdraw_notifications ();
        }

        /**
         * Show notification informing that the time-block has ended.
         */
        private void notify_time_block_about_to_end (Ft.TimeBlock time_block)
        {
            var title = "";
            var body = "";
            var action_label = "";

            switch (time_block.state)
            {
                case Ft.State.POMODORO:
                    title = _("Pomodoro is about to end");
                    action_label = _("Take a Break");
                    break;

                case Ft.State.BREAK:
                case Ft.State.SHORT_BREAK:
                case Ft.State.LONG_BREAK:
                    title = _("Break is about to end");
                    action_label = _("Start Pomodoro");
                    break;

                default:
                    assert_not_reached ();
            }

            var notification = this.create_notification (title, body, false);
            notification.set_priority (GLib.NotificationPriority.URGENT);
            notification.add_button_with_target_value (_("+1 minute"), "app.extend", 60);
            notification.add_button (action_label, "app.advance");

            this.notification = notification;
            this.notification_type = Ft.NotificationType.TIME_BLOCK_ABOUT_TO_END;
            this.notification_time_block = time_block;

            if (this.debug) {
                var timestamp = this._timer.get_last_tick_time ();
                this.notification.set_data<string> ("hash", @"$(time_block.state.to_string()):time-block-about-to-end:$(timestamp)");
            }

            this._backend.send_notification ("timer", this.notification);

            this.remove_withdraw_timeout ();
        }

        /**
         * Show notification informing that the time-block has ended.
         *
         * It's only shown when waiting for activity.
         */
        private void notify_time_block_ended (Ft.TimeBlock previous_time_block)
        {
            var title = "";
            var body = _("Get ready…");

            switch (previous_time_block.state)
            {
                case Ft.State.POMODORO:
                    title = _("Pomodoro is over!");
                    break;

                case Ft.State.BREAK:
                case Ft.State.SHORT_BREAK:
                case Ft.State.LONG_BREAK:
                    title = _("Break is over!");
                    break;

                default:
                    assert_not_reached ();
            }

            this.notification = this.create_notification (title, body, false);
            this.notification_type = Ft.NotificationType.TIME_BLOCK_ENDED;
            this.notification_time_block = previous_time_block;

            if (this.debug) {
                this.notification.set_data<string> (
                        "hash", @"$(previous_time_block.state.to_string()):time-block-ended");
            }

            this._backend.send_notification ("timer", this.notification);

            this.remove_withdraw_timeout ();
        }

        /**
         * Show notification with emphasis on confirming advancement to the next time-block.
         */
        private void notify_confirm_advancement (Ft.TimeBlock current_time_block,
                                                 Ft.TimeBlock next_time_block)
        {
            var title = "";
            var body = "";
            var action_label = "";

            switch (current_time_block.state)
            {
                case Ft.State.POMODORO:
                    title = _("Pomodoro is over!");
                    break;

                case Ft.State.BREAK:
                case Ft.State.SHORT_BREAK:
                case Ft.State.LONG_BREAK:
                    title = _("Break is over!");
                    break;

                default:
                    assert_not_reached ();
            }

            switch (next_time_block.state)
            {
                case Ft.State.POMODORO:
                    body = _("Confirm the start of a Pomodoro…");
                    action_label = _("Start Pomodoro");
                    break;

                case Ft.State.BREAK:
                    body = _("Confirm the start of a break…");
                    action_label = _("Take a Break");
                    break;

                case Ft.State.SHORT_BREAK:
                    body = _("Confirm the start of a short break…");
                    action_label = _("Take a Break");
                    break;

                case Ft.State.LONG_BREAK:
                    body = _("Confirm the start of a long break…");
                    action_label = _("Take a Break");
                    break;

                default:
                    assert_not_reached ();
            }

            var notification = this.create_notification (title, body, false);
            notification.set_priority (GLib.NotificationPriority.URGENT);

            if (next_time_block.state.is_break ()) {
                notification.add_button_with_target_value (_("Skip Break"),
                                                           "app.advance-to-state",
                                                           new GLib.Variant.string ("pomodoro"));
            }

            notification.add_button (action_label, "app.advance");

            this.notification = notification;
            this.notification_type = Ft.NotificationType.CONFIRM_ADVANCEMENT;
            this.notification_time_block = current_time_block;

            if (this.debug) {
                this.notification.set_data<string> (
                        "hash", @"$(current_time_block.state.to_string()):confirm-advancement");
            }

            this._backend.send_notification ("timer", this.notification);

            this.remove_withdraw_timeout ();
        }

        private int64 get_about_to_end_duration ()
        {
            if (!this.settings.get_boolean ("announce-about-to-end")) {
                return 0;
            }

            // if (this.capability_manager.is_enabled ("indicator")) {
            //     return TIME_BLOCK_ABOUT_TO_END_MIN_DURATION;
            // }

            // var notifications_capability = this.capability_manager.lookup ("notifications");
            //
            // if (notifications_capability != null &&
            //     notifications_capability.is_enabled () &&
            //     notifications_capability.has_detail ("actions"))
            // {
            //     return TIME_BLOCK_ABOUT_TO_END_MIN_DURATION;
            // }

            return TIME_BLOCK_ABOUT_TO_END_MAX_DURATION;
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            var current_time_block = current_state.user_data as Ft.TimeBlock;
            var previous_time_block = previous_state.user_data as Ft.TimeBlock;
            var timestamp = this._timer.get_current_time ();

            this.previous_timer_state = previous_state.copy ();

            if (!this.can_open_screen_overlay_later ())
            {
                this.emit_request_screen_overlay_close (true);
                this.remove_reopen_screen_overlay_idle_watch ();
            }

            if (current_state.is_paused () ||
                current_time_block == null)
            {
                this.withdraw_notifications ();
            }
            else if (current_state.is_finished ())
            {
                // Either SessionManager will advance to the next time-block or
                // `confirm_advancement` signal will be emitted. So, nothing to do here.
            }
            else if (!current_state.is_started ())
            {
                if (previous_time_block != null) {
                    this.notify_time_block_ended (previous_time_block);
                }
            }
            else if (current_state.is_running ())
            {
                var remaining = this._timer.calculate_remaining (timestamp);
                var about_to_end_duration =
                        this.get_about_to_end_duration () + TIME_BLOCK_ABOUT_TO_END_TOLERANCE;
                var is_rewinding =
                        current_state.user_data == previous_state.user_data &&
                        current_state.paused_time == previous_state.paused_time &&
                        current_state.offset != previous_state.offset;

                if (current_time_block.state.is_break ())
                {
                    if (remaining >= about_to_end_duration &&
                        !is_rewinding &&
                        this.can_open_screen_overlay ())
                    {
                        this.emit_request_screen_overlay_open ();
                        return;
                    }
                }

                this.add_reopen_screen_overlay_idle_watch ();

                if (current_state.started_time == timestamp) {
                    this.notify_time_block_started (current_time_block);
                }
                else if (remaining < about_to_end_duration) {
                    this.notify_time_block_about_to_end (current_time_block);
                }
                else {
                    this.notify_time_block_running (current_time_block);
                }
            }
            else {
                assert_not_reached ();
            }
        }

        private void on_timer_tick (int64 timestamp)
        {
            if (this.screen_overlay_active) {
                return;
            }

            if (this.notification_type == Ft.NotificationType.TIME_BLOCK_ABOUT_TO_END ||
                this.notification_type == Ft.NotificationType.TIME_BLOCK_ENDED ||
                this.notification_type == Ft.NotificationType.CONFIRM_ADVANCEMENT)
            {
                return;
            }

            var remaining = this._timer.calculate_remaining (timestamp);

            if (remaining <= this.get_about_to_end_duration () &&
                remaining >= TIME_BLOCK_ABOUT_TO_END_TOLERANCE)
            {
                this.notify_time_block_about_to_end (this.session_manager.current_time_block);
            }
        }

        private void on_session_manager_confirm_advancement (Ft.TimeBlock current_time_block,
                                                             Ft.TimeBlock next_time_block)
        {
            this.emit_request_screen_overlay_close ();

            this.notify_confirm_advancement (current_time_block, next_time_block);
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "announce-about-to-end":
                    this.schedule_announcements ();
                    break;

                case "screen-overlay":
                case "screen-overlay-reopen-delay":
                    if (this.reopen_screen_overlay_idle_id != 0) {
                        this.reset_reopen_screen_overlay_idle_watch ();
                    }

                    break;
            }
        }

        private void update (bool allow_screen_overlay)
        {
            if (this.session_manager.current_session == null) {
                this.withdraw_notifications ();
                return;
            }

            if (allow_screen_overlay) {
                this.on_timer_state_changed (this._timer.state, this.previous_timer_state);
            }
            else {
                this.screen_overlay_inhibit_count++;
                this.on_timer_state_changed (this._timer.state, this.previous_timer_state);
                this.screen_overlay_inhibit_count--;
            }
        }

        private void schedule_announcements ()
        {
            if (this.settings.get_boolean ("announce-about-to-end"))
            {
                if (this.timer_tick_id == 0) {
                    this.timer_tick_id = this._timer.tick.connect (this.on_timer_tick);
                }
            }
            else {
                if (this.timer_tick_id != 0) {
                    this._timer.disconnect (this.timer_tick_id);
                    this.timer_tick_id = 0;
                }
            }
        }

        private void emit_request_screen_overlay_open ()
        {
            if (this.screen_overlay_active ||
                this.screen_overlay_open_timeout_id != 0U)
            {
                return;
            }

            this.screen_overlay_open_timeout_id = GLib.Timeout.add (
                SCREEN_OVERLAY_OPEN_TIMEOUT,
                () => {
                    // Open notification as a fallback
                    this.screen_overlay_open_timeout_id = 0;

                    this.remove_lock_screen_idle_watch ();
                    this.update (false);

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.screen_overlay_open_timeout_id,
                                        "Ft.NotificationManager.emit_request_screen_overlay_open");

            this.request_screen_overlay_open ();
        }

        private void emit_request_screen_overlay_close (bool force_close = false)
        {
            if (!force_close &&
                !this.screen_overlay_active &&
                this.screen_overlay_open_timeout_id == 0U)
            {
                return;
            }

            if (this.screen_overlay_open_timeout_id != 0U) {
                GLib.Source.remove (this.screen_overlay_open_timeout_id);
                this.screen_overlay_open_timeout_id = 0U;
            }

            if (this.screen_overlay_active) {
                this.request_screen_overlay_close ();
            }

            if (force_close && this.screen_overlay_active) {
                this.screen_overlay_closed ();
            }
        }

        /**
         * Notify manager that screen overlay has opened.
         */
        [HasEmitter]
        public void screen_overlay_opened ()
        {
            if (this.screen_overlay_open_timeout_id != 0U) {
                GLib.Source.remove (this.screen_overlay_open_timeout_id);
                this.screen_overlay_open_timeout_id = 0U;
            }

            this.screen_overlay_active = true;

            this.remove_reopen_screen_overlay_idle_watch ();
            this.add_lock_screen_idle_watch ();

            this.withdraw_notifications ();
        }

        /**
         * Notify manager that screen overlay has closed.
         */
        [HasEmitter]
        public void screen_overlay_closed ()
        {
            this.screen_overlay_active = false;

            this.remove_lock_screen_idle_watch ();
            this.update (false);
        }

        public signal void request_screen_overlay_open ();

        public signal void request_screen_overlay_close ();

        public void destroy ()
        {
            this.withdraw_notifications ();

            if (this.screen_overlay_open_timeout_id != 0U) {
                GLib.Source.remove (this.screen_overlay_open_timeout_id);
                this.screen_overlay_open_timeout_id = 0U;
            }
        }

        public override void dispose ()
        {
            this.destroy ();

            if (this.screen_overlay_active) {
                this.request_screen_overlay_close ();
            }

            if (this.timer_tick_id != 0) {
                this._timer.disconnect (this.timer_tick_id);
                this.timer_tick_id = 0;
            }

            if (this.timer_state_changed_id != 0) {
                this._timer.disconnect (this.timer_state_changed_id);
                this.timer_state_changed_id = 0;
            }

            if (this.session_manager_confirm_advancement_id != 0) {
                this._session_manager.disconnect (this.session_manager_confirm_advancement_id);
                this.session_manager_confirm_advancement_id = 0;
            }

            if (this.settings_changed_id != 0) {
                this.settings.disconnect (this.settings_changed_id);
                this.settings_changed_id = 0;
            }

            this.remove_reopen_screen_overlay_idle_watch ();
            this.remove_lock_screen_idle_watch ();

            this._timer = null;
            this._session_manager = null;
            this._backend = null;
            this.settings = null;
            this.notification = null;
            this.notification_time_block = null;
            this.idle_monitor = null;
            this.lock_screen = null;

            base.dispose ();
        }
    }
}
