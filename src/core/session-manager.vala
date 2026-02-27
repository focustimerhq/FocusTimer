/*
 * Copyright (c) 2021-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    private enum AdvancementMode
    {
        CONTINUOUS,
        CONFIRM,
        WAIT_FOR_ACTIVITY
    }


    /**
     * `SessionManager` sets up the timer, advances time-blocks and sessions.
     */
    public class SessionManager : GLib.Object
    {
        /**
         * Idle time after which session should no longer be continued, and new session should be created.
         */
        public const int64 SESSION_EXPIRY_TIMEOUT = Ft.Interval.HOUR;

        /**
         * Time limit when waiting for activity or confirmation.
         */
        private const int64 OVERDUE_TIMEOUT = Ft.Interval.HOUR;

        private static Ft.SessionManager? instance = null;

        public Ft.Timer timer {
            get {
                return this._timer;
            }
            construct {
                this._timer = value;
                this._timer.reset ();

                this.timer_resolve_state_id = this._timer.resolve_state.connect (this.on_timer_resolve_state);
                this.timer_state_changed_id = this._timer.state_changed.connect (this.on_timer_state_changed);
                this.timer_finished_id = this._timer.finished.connect (this.on_timer_finished);
                this.timer_suspending_id = this._timer.suspended.connect (this.on_timer_suspending);
                this.timer_suspended_id = this._timer.suspended.connect (this.on_timer_suspended);
            }
        }

        [CCode (notify = false)]
        public Ft.Scheduler scheduler {
            get {
                return this._scheduler;
            }
            set {
                if (this._scheduler == value) {
                    return;
                }

                if (this._scheduler != null) {
                    this._scheduler.notify["session-template"].disconnect (
                            this.on_scheduler_notify_session_template);
                }

                this._scheduler = value;

                if (this._scheduler != null) {
                    this._scheduler.notify["session-template"].connect (
                            this.on_scheduler_notify_session_template);
                }

                this.reschedule ();
                this.update_has_uniform_breaks ();

                this.notify_property ("scheduler");
            }
        }

        /**
         * A current session.
         *
         * Setter replaces current session with another one without adjusting either of them.
         * To correct the timing use `advance_*` methods. After selecting session manually, the current time-block
         * is null and the timer is stopped.
         */
        [CCode (notify = false)]
        public unowned Ft.Session current_session {
            get {
                return this._current_session;
            }
            set {
                this.set_current_time_block_full (value, null);
            }
        }

        /**
         * Current time-block.
         *
         * Only `SessionManager` is aware which time-block is current. Current time-block is reflected in `Timer.state`,
         * but it's not 1:1 equivalent. Time-block has clearly defined gaps, while timer only keeps track of offset.
         *
         * `null` means that current time-block has not yet started and that timer is stopped.
         *
         * Setter replaces current time-block with another one without adjusting either of them.
         * To correct the timing use `advance_*` methods. Setter is meant only for unit testing.
         * Time-block must be assigned to a session beforehand. Setting a time-block with a different session will
         * also switch to a new session. All blocks within new session preceding given `time-block` will be removed.
         */
        [CCode (notify = false)]
        public unowned Ft.TimeBlock current_time_block {
            get {
                return this._current_time_block;
            }
            set {
                var session = value != null ? value.session : this._current_session;

                this.set_current_time_block_full (session, value);
            }
        }

        /**
         * Convenience property to track current state.
         */
        [CCode (notify = false)]
        public Ft.State current_state {
            get {
                return this._current_state;
            }
            set {
                this.advance_to_state (value);
            }
        }

        public unowned Ft.Gap current_gap {
            get {
                return this._current_gap;
            }
        }

        /**
         * Convenience property to track whether there are several cycles per session.
         *
         * It equivalent to whether a session has short breaks.
         */
        [CCode (notify = false)]
        public bool has_uniform_breaks {
            get {
                return this._has_uniform_breaks;
            }
        }

        private Ft.Timer                _timer;
        private Ft.Scheduler            _scheduler;
        private Ft.Session?             _current_session = null;
        private Ft.TimeBlock?           _current_time_block = null;
        private Ft.Gap?                 _current_gap = null;
        private Ft.State                _current_state = Ft.State.STOPPED;
        private bool                    _has_uniform_breaks = false;
        private Ft.Session?             next_session = null;
        private Ft.TimeBlock?           next_time_block = null;
        private Ft.IdleMonitor?         idle_monitor = null;
        private Ft.TimeZoneMonitor?     timezone_monitor = null;
        private Ft.TimezoneHistory?     timezone_history = null;
        private Ft.ScreenSaver?         screensaver = null;
        private Ft.LockScreen?          lockscreen = null;
        private bool                    auto_paused = false;
        private bool                    current_time_block_entered = false;
        private ulong                   current_time_block_changed_id = 0;
        private bool                    current_session_entered = false;
        private bool                    current_session_changed_frozen = false;
        private ulong                   current_session_notify_expiry_time_id = 0;
        private Ft.Session?             previous_session = null;
        private Ft.TimeBlock?           previous_time_block = null;
        private GLib.Settings?          settings = null;
        private int                     resolving_timer_state = 0;
        private ulong                   timer_resolve_state_id = 0;
        private ulong                   timer_state_changed_id = 0;
        private ulong                   timer_finished_id = 0;
        private ulong                   timer_suspending_id = 0;
        private ulong                   timer_suspended_id = 0;
        private uint                    expiry_timeout_id = 0;
        private uint                    reschedule_idle_id = 0;
        private uint                    active_watch_id = 0;
        private uint                    session_changed_idle_id = 0;

        public SessionManager ()
        {
            GLib.Object (
                timer: Ft.Timer.get_default ()
            );
        }

        public SessionManager.with_timer (Ft.Timer timer)
        {
            GLib.Object (
                timer: timer
            );
        }

        construct
        {
            this.settings = Ft.get_settings ();
            this.scheduler = new Ft.SimpleScheduler ();
            this.timezone_monitor = new Ft.TimeZoneMonitor ();
            this.timezone_history = new Ft.TimezoneHistory ();

            this.settings.changed.connect (this.on_settings_changed);
            this.timezone_monitor.changed.connect (this.on_timezone_changed);

            this.update_session_template ();
        }

        /**
         * Sets a default `SessionManager`.
         *
         * The old default manager is unreffed and the new manager referenced.
         *
         * A value of null for this will cause the current default manager to be released and a new default manager
         * to be created on demand.
         */
        public static void set_default (Ft.SessionManager? session_manager)
        {
            Ft.SessionManager.instance = session_manager;
        }

        /**
         * Return a default manager.
         *
         * A new default manager will be created on demand.
         */
        public static unowned Ft.SessionManager get_default ()
        {
            if (Ft.SessionManager.instance == null) {
                Ft.SessionManager.set_default (new Ft.SessionManager ());
            }

            return Ft.SessionManager.instance;
        }

        private int64 get_current_time ()
        {
            return this.resolving_timer_state > 0
                ? this._timer.get_last_state_changed_time ()
                : this._timer.get_current_time ();
        }

        private Ft.Session initialize_next_session (int64 timestamp)
        {
            var next_session = new Ft.Session ();

            this.reschedule_full (next_session, null, false, timestamp);

            return next_session;
        }

        private Ft.TimeBlock? initialize_next_time_block (int64 timestamp)
        {
            Ft.TimeBlock? next_time_block = null;
            Ft.Session? next_session = null;

            if (this._current_time_block != null &&
                this._current_time_block.state == Ft.State.LONG_BREAK &&
                !this._scheduler.is_time_block_completed (this._current_time_block, timestamp))
            {
                // Continue current session.
                // We don't have next time-block yet. It needs to be added by scheduler.
                next_time_block = null;
                next_session = this._current_session;
            }
            else {
                // Try getting a scheduled block.
                next_time_block = this.get_next_time_block ();
                next_session = next_time_block != null ? next_time_block.session : null;
            }

            // Discard session if it has expired.
            if (next_session != null &&
                next_session.is_expired (timestamp))
            {
                next_session = null;
            }

            // Reschedule - update time-blocks according to given `timestamp`.
            if (next_session != null)
            {
                next_session.freeze_changed ();

                // Update break type. It's not done by scheduler,
                // because we want to start a desired break at will.
                if (next_time_block != null && next_time_block.state.is_break ())
                {
                    var next_state = Ft.State.BREAK;

                    if (!this._has_uniform_breaks) {
                        next_state = this.is_long_break_needed (timestamp)
                                ? Ft.State.LONG_BREAK
                                : Ft.State.SHORT_BREAK;
                    }

                    next_time_block.set_state_internal (next_state);
                    next_time_block.duration =
                            this.scheduler.session_template.get_duration (next_state);
                }

                this.reschedule_full (next_session,
                                      next_time_block,
                                      next_time_block != null,
                                      timestamp);

                next_session.thaw_changed ();

                if (next_time_block == null) {
                    next_time_block = next_session == this._current_session
                            ? next_session.get_next_time_block (this._current_time_block)
                            : next_session.get_first_time_block ();
                }
            }

            if (next_session == null || next_time_block == null) {
                next_session = this.initialize_next_session (timestamp);
                next_time_block = next_session.get_first_time_block ();
            }

            assert (next_time_block != null);
            assert (next_time_block.session == next_session);

            // Store `this.next_session` only to increase session ref count
            this.next_session = next_session;
            this.next_time_block = next_time_block;

            return next_time_block;
        }

        /**
         * Builds a `TimerState` according to current time-block.
         */
        private void initialize_timer_state (ref Ft.TimerState state,
                                             int64             timestamp)
        {
            var current_time_block = this._current_time_block;
            var current_gap = this._current_gap;

            if (current_time_block == null) {
                state = Ft.TimerState ();
                return;
            }

            var paused_time = current_gap != null &&
                              Ft.Timestamp.is_undefined (current_gap.end_time)
                    ? current_gap.start_time
                    : Ft.Timestamp.UNDEFINED;
            if (Ft.Timestamp.is_defined (paused_time)) {
                timestamp = paused_time;
            }

            timestamp = timestamp.clamp (current_time_block.start_time,
                                         current_time_block.end_time);

            // Adjust timer state according to the current-time-block.
            if (!this.is_waiting_for_activity ())
            {
                assert (Ft.Timestamp.is_defined (current_time_block.start_time));

                var elapsed = current_time_block.calculate_elapsed (timestamp);

                state.offset        = timestamp - current_time_block.start_time - elapsed;
                state.duration      = current_time_block.duration - state.offset;
                state.started_time  = current_time_block.start_time;
                state.paused_time   = paused_time;
                state.finished_time = Ft.Timestamp.UNDEFINED;

                if (timestamp >= current_time_block.end_time &&
                    Ft.Timestamp.is_undefined (paused_time))
                {
                    state.finished_time = current_time_block.end_time;
                }
            }
            else {
                assert (current_gap == null);

                state.offset        = 0;
                state.duration      = current_time_block.duration;
                state.started_time  = Ft.Timestamp.UNDEFINED;
                state.paused_time   = Ft.Timestamp.UNDEFINED;
                state.finished_time = Ft.Timestamp.UNDEFINED;
            }

            state.user_data = current_time_block;
        }

        private void update_session_template ()
        {
            this._scheduler.session_template = Ft.SessionTemplate.with_defaults ();
        }

        private void update_timer_state (int64 timestamp)
        {
            if (this.resolving_timer_state != 0) {
                return;
            }

            if (this._current_time_block != null)
            {
                var state = Ft.TimerState ();
                this.initialize_timer_state (ref state, timestamp);

                this._timer.set_state_full (state, timestamp);
            }
            else {
                this._timer.reset (0, null, timestamp);
            }
        }

        private void update_has_uniform_breaks ()
        {
            var has_uniform_breaks = this._scheduler.session_template.has_uniform_breaks ();

            if (has_uniform_breaks != this._has_uniform_breaks)
            {
                this._has_uniform_breaks = has_uniform_breaks;

                this.notify_property ("has-uniform-breaks");
            }

            if (this._current_time_block != null &&
                this._current_time_block.state == Ft.State.BREAK &&
                !has_uniform_breaks)
            {
                this._current_time_block.set_state_internal (Ft.State.SHORT_BREAK);
            }

            if (this._current_time_block != null &&
                this._current_time_block.state == Ft.State.SHORT_BREAK &&
                has_uniform_breaks)
            {
                this._current_time_block.set_state_internal (Ft.State.BREAK);
            }
        }

        private unowned Ft.TimeBlock schedule_pomodoro (int64 timestamp)
                                                        requires (this._current_session != null)
        {

            Ft.SchedulerContext context;
            unowned Ft.TimeBlock? next_time_block = null;
            unowned var link = this._current_session.time_blocks.first ();

            // Pick first scheduled pomodoro
            while (link != null)
            {
                if (link.data.get_status () == Ft.TimeBlockStatus.SCHEDULED &&
                    link.data.state == Ft.State.POMODORO)
                {
                    next_time_block = link.data;
                    break;
                }

                link = link.next;
            }

            // Ensure a pomodoro is scheduled
            if (next_time_block == null)
            {
                this._scheduler.build_scheduler_context (this._current_session,
                                                         true,
                                                         timestamp,
                                                         out context,
                                                         out link);
                context.timestamp = timestamp;
                context.state = Ft.State.STOPPED;

                var resolved_time_block = this._scheduler.resolve_time_block (context);

                if (link != null) {
                    this._current_session.insert_before (resolved_time_block, link.data);
                }
                else {
                    this._current_session.append (resolved_time_block);
                }

                next_time_block = resolved_time_block;
            }
            else {
                this._scheduler.reschedule_time_block (next_time_block, timestamp);
            }

            return next_time_block;
        }

        /**
         * Reschedule session having a pre-selected upcoming time-block.
         */
        private void reschedule_full (Ft.Session?   session,
                                      Ft.TimeBlock? next_time_block,
                                      bool          next_time_block_set,
                                      int64         timestamp)
                                      requires (next_time_block_set || next_time_block == null)
        {
            if (session == null || session.is_completed () || this._scheduler == null) {
                return;
            }

            if (next_time_block_set &&
                next_time_block != null &&
                next_time_block.get_status () != Ft.TimeBlockStatus.SCHEDULED)
            {
                next_time_block_set = false;
                next_time_block = null;
            }

            if (Ft.Timestamp.is_undefined (timestamp)) {
                timestamp = this.get_current_time ();
            }

            session.freeze_changed ();

            if (next_time_block_set &&
                next_time_block == null &&
                session == this._current_session)
            {
                // Anticipate a pomodoro after stopping the timer
                var scheduled_time_block = this.get_next_time_block ();

                if (scheduled_time_block == null ||
                    scheduled_time_block.state != Ft.State.POMODORO)
                {
                    next_time_block = this.schedule_pomodoro (timestamp);
                }
            }

            var rescheduled = this._scheduler.reschedule_session (session,
                                                                  next_time_block,
                                                                  next_time_block_set,
                                                                  timestamp);
            if (session == this._current_session && rescheduled) {
                this.emit_session_rescheduled (timestamp);
            }

            session.thaw_changed ();
        }

        /**
         * Try reschedule current session.
         */
        private void reschedule ()
        {
            if (this.reschedule_idle_id != 0) {
                GLib.Source.remove (this.reschedule_idle_id);
                this.reschedule_idle_id = 0;
            }

            if (this._current_session == null) {
                return;
            }

            var timestamp = this._current_time_block != null
                    ? this._current_time_block.end_time
                    : this.get_current_time ();

            this.reschedule_full (this._current_session, null, false, timestamp);
        }

        /**
         * Try reschedule current session, if it was queued.
         */
        private void reschedule_if_queued ()
        {
            if (this.reschedule_idle_id != 0) {
                this.reschedule ();
            }
        }

        private void queue_reschedule ()
        {
            if (this._current_session == null) {
                return;
            }

            if (this.reschedule_idle_id != 0) {
                return;
            }

            this.reschedule_idle_id = GLib.Idle.add (
                () => {
                    this.reschedule_idle_id = 0;
                    this.reschedule ();

                    return GLib.Source.REMOVE;
                },
                GLib.Priority.HIGH_IDLE
            );
            GLib.Source.set_name_by_id (this.reschedule_idle_id,
                                        "Ft.SessionManager.reschedule");
        }

        /**
         * Set current time-block.
         *
         * It may ignore given session if it's completed.
         */
        private void set_current_time_block_full (Ft.Session?   session,
                                                  Ft.TimeBlock? time_block,
                                                  int64         timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (session == this._current_session && time_block == this._current_time_block) {
                // XXX: Handle `gap`?
                return;
            }

            Ft.ensure_timestamp (ref timestamp);

            if (session != null && session.is_expired (timestamp)) {
                GLib.debug ("set_current_time_block_full: setting an expired session");
            }

            var previous_session    = this._current_session;
            var previous_time_block = this._current_time_block;
            var previous_gap        = this._current_gap;
            var previous_state      = this._current_state;
            var state               = time_block != null ? time_block.state : Ft.State.STOPPED;
            var gap                 = time_block?.get_last_gap ();

            if (gap != null && Ft.Timestamp.is_defined (gap.end_time)) {
                gap = null;
            }

            this.freeze_current_session_changed ();

            // Leave previous time-block.
            if (previous_time_block != null)
            {
                // Prevent `TimeBlock.changed` signal from triggering rescheduling.
                if (this.current_time_block_changed_id != 0) {
                    GLib.SignalHandler.block (previous_time_block, this.current_time_block_changed_id);
                }

                if (previous_gap != null) {
                    this.mark_gap_end (previous_gap, timestamp);
                }

                if (previous_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS) {
                    this.mark_time_block_end (previous_time_block, timestamp);
                }

                if (this.current_time_block_entered) {
                    this.leave_time_block (previous_time_block);
                }

                if (this._current_time_block != previous_time_block || this._current_session != previous_session) {
                    GLib.debug ("The time-block was changed during `leave-time-block` emission.");
                    return;
                }
            }

            if (session != null && session.is_completed ()) {
                session = null;
            }

            // Leave previous session.
            if (previous_session != null && session != previous_session)
            {
                this.mark_session_end (previous_session, timestamp);

                if (this.current_session_entered) {
                    this.leave_session (previous_session);
                }

                if (this._current_time_block != previous_time_block || this._current_session != previous_session) {
                    GLib.debug ("The time-block was changed during `leave-session` emission.");
                    return;
                }
            }

            // Reschedule.
            if (session != null)
            {
                if (session == this.next_session &&
                    time_block == this.next_time_block &&
                    time_block != null &&
                    time_block.start_time == timestamp)
                {
                    // Already scheduled using `initialize_next_time_block`
                }
                else {
                    this.reschedule_full (session, time_block, true, timestamp);
                }
            }

            // Enter session.
            if (session != previous_session)
            {
                this.previous_session    = previous_session;
                this.previous_time_block = previous_time_block;
                this._current_session    = session;
                this._current_time_block = null;
                this._current_gap        = null;

                this.notify_property ("current-session");

                if (session != null) {
                    this.enter_session (session);
                }

                if (this._current_session != session) {
                    GLib.debug ("The session was changed during `enter-session` emission.");
                    return;
                }

                if (this._current_time_block != null) {
                    GLib.debug ("The time-block was changed during `enter-session` emission.");
                    return;
                }
            }

            // Enter time-block. It will start or stop the timer depending whether time-block is null.
            if (time_block != previous_time_block)
            {
                this.previous_time_block = previous_time_block;
                this._current_time_block = time_block;
                this._current_gap        = gap;
                this._current_state      = state;

                this.notify_property ("current-time-block");

                if (state != previous_state) {
                    this.notify_property ("current-state");
                }

                if (time_block != null) {
                    this.enter_time_block (time_block);
                }

                if (this._current_time_block != time_block) {
                    GLib.debug ("The time-block was changed during `enter-time-block` emission.");
                    return;
                }

                this.update_timer_state (timestamp);
            }

            this.reschedule_if_queued ();

            this.advanced (session, time_block,
                           previous_session, previous_time_block);

            if (this._current_time_block != null) {
                this.enable_idle_monitor ();
            }
            else {
                this.disable_idle_monitor ();
            }

            this.thaw_current_session_changed ();
        }

        public unowned Ft.TimeBlock? get_next_time_block ()
        {
            Ft.TimeBlock? next_time_block = null;

            if (this._current_session != null && this._current_time_block == null)
            {
                if (this.previous_time_block != null &&
                    this.previous_time_block.session == this._current_session)
                {
                    next_time_block = this._current_session.get_next_time_block (this.previous_time_block);
                }
                else {
                    next_time_block = this._current_session.get_first_time_block ();
                }
            }
            else if (this._current_session != null)
            {
                next_time_block = this._current_session.get_next_time_block (this._current_time_block);
            }

            // Jump to the first scheduled time-block. Used for restoring.
            while (next_time_block != null &&
                   next_time_block.get_status () != Ft.TimeBlockStatus.SCHEDULED)
            {
                next_time_block = this._current_session.get_next_time_block (next_time_block);
            }

            return next_time_block != null ? next_time_block : this.next_time_block;
        }

        /**
         * Return cycle associated with current_time_block.
         */
        public unowned Ft.Cycle? get_current_cycle ()
        {
            var current_time_block = this._current_time_block != null
                    ? this._current_time_block
                    : this.previous_time_block;

            if (current_time_block == null || this._current_session == null) {
                return null;
            }

            var cycles = this._current_session.get_cycles ();  // XXX: makes list copy
            unowned GLib.List<unowned Ft.Cycle> link = cycles.first ();

            while (link != null)
            {
                if (link.data.contains (current_time_block)) {
                    return link.data;
                }

                link = link.next;
            }

            return null;
        }

        private Ft.AdvancementMode resolve_advancement_mode (Ft.State next_state,
                                                             int64          timestamp)
                                                             requires (this.idle_monitor != null)
        {
            // Pick appropriate advancement mode according to current state.
            var current_state = this._current_time_block != null
                      ? this._current_time_block.state
                      : Ft.State.STOPPED;
            var advancement_mode = Ft.AdvancementMode.CONTINUOUS;

            if (current_state == Ft.State.POMODORO) {
                advancement_mode = this.settings.get_boolean ("confirm-starting-break")
                        ? Ft.AdvancementMode.CONFIRM
                        : Ft.AdvancementMode.CONTINUOUS;
            }
            else if (current_state.is_break ()) {
                advancement_mode = this.settings.get_boolean ("confirm-starting-pomodoro")
                        ? Ft.AdvancementMode.CONFIRM
                        : Ft.AdvancementMode.WAIT_FOR_ACTIVITY;
            }

            switch (advancement_mode)
            {
                case Ft.AdvancementMode.WAIT_FOR_ACTIVITY:
                    // If `IdleMonitor` is not available, use manual confirmation.
                    if (!this.idle_monitor.enabled) {
                        advancement_mode = Ft.AdvancementMode.CONFIRM;
                    }
                    break;

                default:
                    break;
            }

            return advancement_mode;
        }

        /**
         * Push the removal of extra time-blocks onto SQLite queue.
         */
        private void delete_time_blocks (Gom.Repository    repository,
                                         int64             session_id,
                                         GLib.Array<int64> time_block_ids_to_keep)
                                         requires (session_id != 0)
        {
            var adapter = repository.adapter;
            assert (adapter != null);

            var session_id_value = GLib.Value (typeof (int64));
            session_id_value.set_int64 (session_id);

            Gom.Filter[] filters = {
                new Gom.Filter.eq (typeof (Ft.TimeBlockEntry),
                                   "session-id",
                                   session_id_value),
            };

            for (var index = 0; index < time_block_ids_to_keep.length; index++)
            {
                var time_block_id = time_block_ids_to_keep.index (index);
                var time_block_id_value = GLib.Value (typeof (int64));
                time_block_id_value.set_int64 (time_block_id);

                filters += new Gom.Filter.neq (typeof (Ft.TimeBlockEntry),
                                               "id",
                                               time_block_id_value);
            }

            var filter = new Gom.Filter.and_full (filters);
            var command_builder = (Gom.CommandBuilder) GLib.Object.@new (
                    typeof (Gom.CommandBuilder),
                    resource_type: typeof (Ft.TimeBlockEntry),
                    adapter: adapter,
                    filter: filter);
            var command = command_builder.build_delete ();

            command.@ref ();

            adapter.queue_write (
                () => {
                    try {
                        command.execute (null);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while deleting time-blocks: %s", error.message);
                    }

                    command.@unref ();
                });
        }

        private void delete_gaps (Gom.Repository    repository,
                                  int64             time_block_id,
                                  GLib.Array<int64> gap_ids_to_keep)
                                  requires (time_block_id != 0)
        {
            var adapter = repository.adapter;
            assert (adapter != null);

            var time_block_id_value = GLib.Value (typeof (int64));
            time_block_id_value.set_int64 (time_block_id);

            Gom.Filter[] filters = {
                new Gom.Filter.eq (typeof (Ft.GapEntry),
                                   "time-block-id",
                                   time_block_id_value),
            };

            for (var index = 0; index < gap_ids_to_keep.length; index++)
            {
                var gap_id = gap_ids_to_keep.index (index);
                var gap_id_value = GLib.Value (typeof (int64));
                gap_id_value.set_int64 (gap_id);

                filters += new Gom.Filter.neq (typeof (Ft.GapEntry),
                                               "id",
                                               gap_id_value);
            }

            var filter = new Gom.Filter.and_full (filters);
            var command_builder = (Gom.CommandBuilder) GLib.Object.@new (
                    typeof (Gom.CommandBuilder),
                    resource_type: typeof (Ft.GapEntry),
                    adapter: adapter,
                    filter: filter);
            var command = command_builder.build_delete ();

            command.@ref ();

            adapter.queue_write (
                () => {
                    try {
                        command.execute (null);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while deleting gaps: %s", error.message);
                    }

                    command.@unref ();
                });
        }

        /**
         * Delete a session entry by ID, working around a floating reference bug in Gom.
         *
         * Gom's `GomResource.delete_async()` has a bug where it creates a filter with a floating
         * reference and unrefs it without sinking, causing a critical warning. This method
         * implements the delete operation directly to avoid that issue.
         *
         * XXX: fix it upstream
         */
        private void delete_session (Gom.Repository repository,
                                     int64          session_id)
                                     requires (session_id != 0)
        {
            var adapter = repository.adapter;
            assert (adapter != null);

            var id_value = GLib.Value (typeof (int64));
            id_value.set_int64 (session_id);

            var filter = new Gom.Filter.eq (typeof (Ft.SessionEntry),
                                            "id",
                                            id_value);

            var command_builder = (Gom.CommandBuilder) GLib.Object.@new (
                    typeof (Gom.CommandBuilder),
                    resource_type: typeof (Ft.SessionEntry),
                    adapter: adapter,
                    filter: filter);
            var command = command_builder.build_delete ();

            command.@ref ();

            adapter.queue_write (
                () => {
                    try {
                        command.execute (null);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while deleting session entry: %s", error.message);
                    }

                    command.@unref ();
                });
        }

        private async void save_session (Gom.Repository   repository,
                                         Ft.Session session)
                                         throws GLib.Error
        {
            if (!session.should_create_entry ())
            {
                if (session.entry != null && session.entry.id != 0)
                {
                    var session_entry = session.entry;
                    session.unset_entry ();

                    // yield session_entry.delete_async ();  // XXX: should be async
                    this.delete_session (repository, session_entry.id);
                }

                return;
            }

            // Collect session data.
            var session_entry_needs_update = session.should_update_entry ();
            var session_entry = session.create_or_update_entry ();
            var keep_time_block_ids = new GLib.Array<int64> ();
            var keep_gap_ids = new GLib.HashTable<int64?, GLib.Array>.full (
                    GLib.direct_hash,
                    GLib.direct_equal,
                    null,
                    (arr) => {
                        ((GLib.Array) arr).data = null;
                    });
            var time_block_mapping = new GLib.HashTable
                    <unowned Ft.TimeBlock, unowned Ft.TimeBlockEntry>
                    (GLib.direct_hash, GLib.direct_equal);
            var gap_mapping = new GLib.HashTable
                    <unowned Ft.Gap, unowned Ft.GapEntry>
                    (GLib.direct_hash, GLib.direct_equal);

            // Ensure expiry time is defined.
            if (Ft.Timestamp.is_undefined (session_entry.expiry_time)) {
                session_entry.expiry_time = this.get_current_time () + SESSION_EXPIRY_TIMEOUT;
                session_entry_needs_update = true;
            }

            session.@foreach (
                (time_block) => {
                    if (!time_block.should_create_entry ()) {
                        return;
                    }

                    var time_block_entry = time_block.entry;

                    if (time_block_entry != null && time_block_entry.id != 0) {
                        keep_time_block_ids.append_val (time_block_entry.id);
                    }

                    if (time_block.should_update_entry ())
                    {
                        var gap_ids = new GLib.Array<int64> ();

                        time_block_entry = time_block.create_or_update_entry ();
                        time_block_mapping.insert (time_block, time_block_entry);
                        time_block.foreach_gap (
                            (gap) => {
                                if (!gap.should_create_entry ()) {
                                    return;
                                }

                                var gap_entry = gap.entry;

                                if (gap_entry != null && time_block_entry.id != 0) {
                                    gap_ids.append_val (gap_entry.id);
                                }

                                if (gap.should_update_entry ()) {
                                    gap_entry = gap.create_or_update_entry ();
                                    gap_mapping.insert (gap, gap_entry);
                                }
                            });

                        if (time_block_entry.id != 0) {
                            keep_gap_ids.insert (time_block_entry.id, gap_ids);
                        }
                    }
                });

            // Commit updates.
            try {
                if (session_entry_needs_update) {
                    yield session_entry.save_async ();
                }

                var time_block_entries = (Gom.ResourceGroup) GLib.Object.@new (
                        typeof (Gom.ResourceGroup),
                        repository: repository,
                        resource_type: typeof (Ft.TimeBlockEntry),
                        is_writable: true);
                time_block_mapping.@foreach (
                    (time_block, time_block_entry) => {
                        assert (time_block_entry.session_id != 0);

                        // HACK: Gom is eager to erase is-from-table flag,
                        //       which leads entries to being inserted again, not updated.
                        time_block_entry.set_data<bool> ("is-from-table", time_block_entry.id != 0);

                        time_block_entries.append (time_block_entry);
                    });

                this.delete_time_blocks (repository,
                                         session_entry.id,
                                         keep_time_block_ids);
                time_block_entries.write_sync ();
                // yield time_block_entries.write_async ();  // XXX: should use async

                time_block_mapping.@foreach (
                    (time_block, time_block_entry) => {
                        // HACK: Tell Gom that entries are from db
                        time_block_entry.set_data<bool> ("is-from-table", true);

                        this.time_block_saved (time_block, time_block_entry);
                    });

                var gap_entries = (Gom.ResourceGroup) GLib.Object.@new (
                        typeof (Gom.ResourceGroup),
                        repository: repository,
                        resource_type: typeof (Ft.TimeBlockEntry),
                        is_writable: true);
                gap_mapping.@foreach (
                    (gap, gap_entry) => {
                        assert (gap_entry.time_block_id != 0);
                        gap_entries.append (gap_entry);
                    });

                keep_gap_ids.@foreach (
                    (time_block_id, gap_ids_to_keep) => {
                        this.delete_gaps (repository,
                                          time_block_id,
                                          gap_ids_to_keep);
                    });
                gap_entries.write_sync ();
                // yield gap_entries.write_async ();  // XXX: should use async

                gap_mapping.@foreach (
                    (gap, gap_entry) => {
                        // HACK: Tell Gom that entries are from db
                        gap_entry.set_data<bool> ("is-from-table", true);

                        this.gap_saved (gap, gap_entry);
                    });
            }
            catch (GLib.Error error) {
                throw error;
            }

            // TODO: check if instances are disposed properly
        }

        /**
         * Save session state to database.
         */
        public async bool save ()
        {
            var repository = Ft.Database.get_repository ();
            assert (repository != null);

            var remaining_sessions = 0;
            var success = true;

            if (this.previous_session != null)
            {
                remaining_sessions++;

                this.save_session.begin (
                    repository,
                    this.previous_session,
                    (obj, res) => {
                        try {
                            this.save_session.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while saving previous session: %s", error.message);
                            success = false;
                        }

                        remaining_sessions--;

                        if (remaining_sessions == 0) {
                            this.save.callback ();
                        }
                    });
            }

            if (this._current_session != null)
            {
                remaining_sessions++;

                this.save_session.begin (
                    repository,
                    this._current_session,
                    (obj, res) => {
                        try {
                            this.save_session.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while saving current session: %s", error.message);
                            success = false;
                        }

                        remaining_sessions--;

                        if (remaining_sessions == 0) {
                            this.save.callback ();
                        }
                    });
            }

            if (remaining_sessions > 0) {
                yield;
            }

            return success;
        }

        private async Ft.Session? restore_session (Gom.Repository        repository,
                                                   Ft.SessionEntry session_entry)
                                                   throws GLib.Error
        {
            // Load time blocks for this session
            var session_id_value = GLib.Value (typeof (int64));
            session_id_value.set_int64 (session_entry.id);
            var time_block_filter = new Gom.Filter.eq (
                    typeof (Ft.TimeBlockEntry),
                    "session-id",
                    session_id_value);

            var time_block_sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
            time_block_sorting.add (
                    typeof (Ft.TimeBlockEntry),
                    "start-time",
                    Gom.SortingMode.ASCENDING);

            var time_block_results = yield repository.find_sorted_async (
                    typeof (Ft.TimeBlockEntry),
                    time_block_filter,
                    time_block_sorting);

            if (time_block_results.count == 0) {
                return null;
            }

            yield time_block_results.fetch_async (0, time_block_results.count);

            // Reconstruct the session
            var session = new Ft.Session ();
            session.expiry_time = session_entry.expiry_time;
            session.entry = session_entry;

            // Build mapping from time_block_entry.id to time_block
            var time_blocks_by_id = new GLib.HashTable<int64?, Ft.TimeBlock> (
                    GLib.int64_hash, GLib.int64_equal);
            Gom.Filter[] gap_filters = {};

            for (var i = 0; i < time_block_results.count; i++)
            {
                var time_block_entry = (Ft.TimeBlockEntry) time_block_results.get_index (i);

                var time_block = new Ft.TimeBlock (Ft.State.from_string (time_block_entry.state));
                time_block.set_time_range (time_block_entry.start_time, time_block_entry.end_time);
                time_block.set_status (Ft.TimeBlockStatus.from_string (time_block_entry.status));
                time_block.set_intended_duration (time_block_entry.intended_duration);
                time_block.entry = time_block_entry;

                time_blocks_by_id.insert (time_block_entry.id, time_block);

                // Build filter for this time block's gaps
                var time_block_id_value = GLib.Value (typeof (int64));
                time_block_id_value.set_int64 (time_block_entry.id);
                gap_filters += new Gom.Filter.eq (typeof (Ft.GapEntry),
                                                  "time-block-id",
                                                  time_block_id_value);

                session.append (time_block);
            }

            // Load all gaps for this session
            if (gap_filters.length > 0)
            {
                var gap_filter = gap_filters.length == 1
                        ? gap_filters[0]
                        : new Gom.Filter.or_full (gap_filters);
                var gap_sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
                gap_sorting.add (typeof (Ft.GapEntry),
                                 "start-time",
                                 Gom.SortingMode.ASCENDING);

                var gap_results = yield repository.find_sorted_async (typeof (Ft.GapEntry),
                                                                      gap_filter,
                                                                      gap_sorting);
                yield gap_results.fetch_async (0, gap_results.count);

                // Distribute gaps to their respective time blocks
                for (var j = 0; j < gap_results.count; j++)
                {
                    var gap_entry = (Ft.GapEntry) gap_results.get_index (j);
                    var time_block = time_blocks_by_id.lookup (gap_entry.time_block_id);

                    var gap = new Ft.Gap (Ft.GapFlags.from_string (gap_entry.flags));
                    gap.set_time_range (gap_entry.start_time, gap_entry.end_time);
                    gap.entry = gap_entry;

                    time_block.add_gap (gap);
                }
            }

            session.@foreach ((time_block) => time_block.normalize_gaps ());

            this._scheduler.ensure_session_meta (session);

            return session;
        }

        /**
         * Restore session from database.
         */
        public async bool restore (int64 timestamp)
        {
            Ft.SessionEntry? session_entry = null;
            Ft.Session?      restored_session = null;
            Ft.TimeBlock?    restored_time_block = null;
            Ft.Gap?          restored_gap = null;

            Ft.ensure_timestamp (ref timestamp);

            var repository = Ft.Database.get_repository ();
            var success    = true;

            assert (repository != null);

            // XXX: We're trying to write a timezone entry at first opportunity after the
            //      database is ready. Not the best place to do that.
            this.mark_timezone (this.timezone_monitor.timezone, timestamp);

            // Query the most recent session
            var end_time_value = GLib.Value (typeof (int64));
            end_time_value.set_int64 (timestamp - SESSION_EXPIRY_TIMEOUT);
            var session_filter = new Gom.Filter.gte (
                    typeof (Ft.SessionEntry),
                    "end-time",
                    end_time_value);

            var session_sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
            session_sorting.add (
                    typeof (Ft.SessionEntry),
                    "start-time",
                    Gom.SortingMode.DESCENDING);

            try {
                var session_results = yield repository.find_sorted_async (
                        typeof (Ft.SessionEntry),
                        session_filter,
                        session_sorting);

                if (session_results.count > 0) {
                    yield session_results.fetch_async (0, 1);

                    session_entry = (Ft.SessionEntry) session_results.get_index (0);
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Unable to fetch last session: %s", error.message);
                success = false;
            }

            if (session_entry != null)
            {
                try {
                    restored_session = yield this.restore_session (repository, session_entry);
                }
                catch (GLib.Error error) {
                    GLib.warning ("Unable to restore session #%s: %s",
                                  session_entry.id.to_string (), error.message);
                    success = false;
                }
            }

            if (restored_session != null)
            {
                restored_session.@foreach (
                    (time_block) => {
                        if (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS) {
                            restored_time_block = time_block;
                        }
                    });
                restored_time_block?.foreach_gap (
                    (gap) => {
                        if (Ft.Timestamp.is_undefined (gap.end_time)) {
                            restored_gap = gap;
                        }
                    });

                if (restored_time_block != null &&
                    restored_time_block.end_time > timestamp &&
                    restored_gap == null)
                {
                    GLib.warning ("Restoring a time-block that hasn't been paused. Rewinding to last known position...");

                    restored_gap = restored_time_block.get_last_gap ();

                    if (restored_gap != null) {
                        restored_gap.end_time = Ft.Timestamp.UNDEFINED;
                    }
                    else {
                        restored_time_block.set_status (Ft.TimeBlockStatus.SCHEDULED);
                        restored_time_block = null;
                    }
                }

                if (!restored_session.is_completed () &&
                    !restored_session.is_expired (timestamp))
                {
                    this.set_current_time_block_full (restored_session,
                                                      restored_time_block,
                                                      timestamp);
                }

                if (this._timer.is_finished () &&
                    this._timer.user_data == restored_time_block)
                {
                    this.confirm_advancement (this._current_time_block,
                                              this.initialize_next_time_block (timestamp));
                }
            }

            return success;
        }

        /**
         * Extend current time-block, as if it was started from scratch.
         */
        private void extend_current_time_block (bool  resume,
                                                int64 timestamp)
                                                requires (this._current_time_block != null)
                                                requires (this._current_time_block == this._timer.user_data)
        {
            var duration = this._timer.calculate_elapsed (timestamp) +
                           this._current_time_block.get_intended_duration ();
            // TODO: use scheduler to determine `duration`

            if (this._timer.is_finished ()) {
                duration += timestamp - this._timer.state.finished_time;
            }

            if (resume && this._timer.is_paused ())
            {
                var new_state = this._timer.state.copy ();
                new_state.duration = duration;
                new_state.offset += timestamp - new_state.paused_time;
                new_state.paused_time = Ft.Timestamp.UNDEFINED;

                this._timer.set_state_full (new_state, timestamp);
            }
            else {
                this._timer.set_duration_full (duration, timestamp);
            }
        }

        private void swap_current_state (Ft.State new_state,
                                         int64    timestamp)
                                         requires (this._current_time_block != null)
                                         requires (this._current_state.is_break ())
        {
            var time_block = this._current_time_block;
            time_block.freeze_changed ();
            time_block.set_state_internal (new_state);
            time_block.set_intended_duration (
                    this._scheduler.session_template.get_duration (time_block.state));
            time_block.set_completion_time (
                    this._scheduler.calculate_time_block_completion_time (time_block));

            this.extend_current_time_block (true, timestamp);
            time_block.thaw_changed ();
        }

        private void mark_gap_end (Ft.Gap gap,
                                   int64  timestamp)
                                   requires (timestamp >= gap.start_time)
        {
            gap.end_time = timestamp;

            // Invalidate interruption when stopping the timer
            // TODO: also invalidate interruption on session expiry
            if (gap.has_flag (Ft.GapFlags.INTERRUPTION) &&
                Ft.Context.get_event_source () == "timer.reset")
            {
                gap.unset_flag (Ft.GapFlags.INTERRUPTION);
            }
        }

        /**
         * Adjust time-blocks `end-time` and its status.
         */
        private void mark_time_block_end (Ft.TimeBlock time_block,
                                          int64        timestamp)
                                          requires (time_block.get_status () != Ft.TimeBlockStatus.SCHEDULED)
                                          requires (timestamp >= time_block.start_time)
        {
            time_block.freeze_changed ();

            if (this._timer.is_finished () && this._timer.user_data == time_block)
            {
                // Count overdue time when confirming advancement
                time_block.end_time = int64.min (
                        this._timer.state.finished_time + OVERDUE_TIMEOUT,
                        timestamp);
            }
            else {
                time_block.end_time = timestamp;
            }

            time_block.foreach_gap (
                (gap) => {
                    gap.end_time = Ft.Timestamp.is_undefined (gap.end_time)
                            ? time_block.end_time
                            : int64.min (gap.end_time, timestamp);
                });
            time_block.set_status (
                    this._scheduler.is_time_block_completed (time_block, time_block.end_time)
                    ? Ft.TimeBlockStatus.COMPLETED
                    : Ft.TimeBlockStatus.UNCOMPLETED);

            this.update_time_block_meta (time_block);

            time_block.thaw_changed ();
        }

        /**
         * Discard time-blocks that were not marked as ended.
         * Ensure there is no in-progress time block.
         */
        private void mark_session_end (Ft.Session session,
                                       int64      timestamp)
        {
            session.freeze_changed ();
            session.remove_scheduled ();

            var last_time_block = session.get_last_time_block ();

            if (last_time_block != null) {
                // Time-block should be marked as ended earlier, and leave-time-block should be already emitted.
                assert (last_time_block.get_status () != Ft.TimeBlockStatus.IN_PROGRESS);
            }

            session.expiry_time = timestamp;

            session.thaw_changed ();
        }

        private void mark_timezone (GLib.TimeZone timezone,
                                    int64         timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            this.timezone_history.insert (timestamp, timezone);
        }

        private bool is_long_break_needed (int64 timestamp)
        {
            Ft.SchedulerContext context;

            if (this._current_session == null) {
                return false;
            }

            this._scheduler.build_scheduler_context (this._current_session,
                                                     true,
                                                     timestamp,
                                                     out context,
                                                     null);

            return context.needs_long_break;
        }

        private bool is_current_session_completed (int64 timestamp)
        {
            if (this._current_session == null) {
                return false;
            }

            if (this._current_time_block == null) {
                return this._current_session.is_completed ();
            }

            if (this._current_session.is_completed ()) {
                return true;
            }

            if (this._current_time_block != null && (
                this._current_time_block.state == LONG_BREAK ||
                this._current_time_block.state == BREAK))
            {
                return this._scheduler.is_time_block_completed (this._current_time_block,
                                                                timestamp);
            }

            return false;
        }

        private inline bool is_waiting_for_activity ()
        {
            return this.active_watch_id != 0;
        }

        /**
         * Start given time-block.
         *
         * It ends previous time-block and switches to a new one, even if it's of same state.
         * There are many similarities with `set_current_time_block()`, except for handling
         * timer stop (passing `null` time-block). `advance_to_time_block` ensures we advance to
         * another session instead of `null`.
         *
         * When we advance to a break - its type may be change during rescheduling.
         */
        private void advance_to_time_block (Ft.TimeBlock? time_block,
                                            int64         timestamp = Ft.Timestamp.UNDEFINED)
        {
            assert (time_block == null ||
                    time_block.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            Ft.ensure_timestamp (ref timestamp);

            var session = time_block != null ? time_block.session : this._current_session;

            if (time_block != null && session != null && session.is_expired (timestamp)) {
                GLib.warning ("Advancing to a time-block of expired session.");
            }

            if (time_block == null && (
                this._current_session == null ||
                this.is_current_session_completed (timestamp)))
            {
                session = this.initialize_next_session (timestamp);

            }

            this.set_current_time_block_full (session, time_block, timestamp);
        }

        /**
         * Switch to a given state.
         *
         * Unlike `advance_to_time_block()`, it tries to extend current time-block and can handle Ft.State.BREAK.
         * This is the preferred method of advancing the timer states as it tries to avoid emitting enter- leave-
         * signals unnecessarily. Switching between break types will cause creation a of a new time-block.
         *
         * This method allows you to force a short or long break.
         */
        public void advance_to_state (Ft.State state,
                                      int64    timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            if (state == Ft.State.STOPPED) {
                this.advance_to_time_block (null, timestamp);
                return;
            }

            // Determine the type of break if Ft.State.BREAK is given.
            // It's not efficient, as we build scheduler context again later.
            if (state == Ft.State.BREAK && !this._has_uniform_breaks) {
                state = this.is_long_break_needed (timestamp)
                        ? Ft.State.LONG_BREAK
                        : Ft.State.SHORT_BREAK;
            }

            // Extend current time-block if possible.
            if (this._current_time_block != null &&
                this._current_time_block.state == state)
            {
                this.extend_current_time_block (true, timestamp);
                return;
            }

            // Swap break state.
            if (this._current_time_block != null &&
                this._current_time_block.state.is_break () &&
                state.is_break ())
            {
                this.swap_current_state (state, timestamp);
                return;
            }

            this.freeze_current_session_changed ();

            // Preserve current session if it hasn't been completed.
            var next_time_block = this.get_next_time_block ();
            var next_session = next_time_block != null ? next_time_block.session : null;

            if (next_session == null &&
                this._current_session != null &&
                !this._current_session.is_completed ())
            {
                next_session = this._current_session;
                next_time_block = null;
            }

            // Check whether session has expired and select upcoming time-block.
            if (next_session == null || next_session.is_expired (timestamp)) {
                next_session = this.initialize_next_session (timestamp);
                next_time_block = next_session.get_first_time_block ();
            }

            // Create a time-block for given state.
            if (next_time_block != null && next_time_block.state != state) {
                var time_block = new Ft.TimeBlock.with_start_time (timestamp, state);
                next_session.insert_before (time_block, next_time_block);
                next_time_block = time_block;
            }
            else if (next_time_block == null) {
                var time_block = new Ft.TimeBlock.with_start_time (timestamp, state);
                next_session.append (time_block);
                next_time_block = time_block;
            }

            this.advance_to_time_block (next_time_block, timestamp);
            this.thaw_current_session_changed ();
        }

        /**
         * Jump to next scheduled time-block.
         */
        public void advance (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            this.freeze_current_session_changed ();

            var next_time_block = this.initialize_next_time_block (timestamp);

            this.advance_to_time_block (next_time_block, timestamp);
            this.thaw_current_session_changed ();
        }

        /**
         * Update session `expiry-time`.
         *
         * The given timeout is relative to last action in the session.
         */
        private void bump_expiry_time (int64 timeout)
        {
            if (this.expiry_timeout_id != 0)
            {
                GLib.Source.remove (this.expiry_timeout_id);
                this.expiry_timeout_id = 0;
            }

            if (this._current_session != null && !this._current_session.is_scheduled ())
            {
                var expiry_time = this._timer.is_running ()
                        ? Ft.Timestamp.UNDEFINED
                        : this._timer.get_last_state_changed_time () + timeout;

                GLib.SignalHandler.block (
                        this._current_session,
                        this.current_session_notify_expiry_time_id);

                this._current_session.expiry_time = expiry_time;

                GLib.SignalHandler.unblock (
                        this._current_session,
                        this.current_session_notify_expiry_time_id);

                // Call notify signal handler even if there is no change.
                this.on_current_session_notify_expiry_time ();
            }
        }

        private void expire_current_session (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this._current_session == null || this._current_session.is_scheduled ()) {
                return;
            }

            Ft.ensure_timestamp (ref timestamp);

            var current_session = this._current_session;

            this.session_expired (this._current_session, timestamp);

            if (this._current_session == current_session) {
                this.reset (timestamp);
            }
            else {
                GLib.debug ("The session was changed during `session-expired` emission.");
            }
        }

        private void freeze_current_session_changed ()
        {
            if (this._current_session != null && !this.current_session_changed_frozen)
            {
                this.current_session_changed_frozen = true;
                this._current_session.freeze_changed ();

                this.session_changed_idle_id = GLib.Idle.add (
                    () => {
                        GLib.debug ("Calling `thaw_current_session_changed` late...");

                        this.session_changed_idle_id = 0U;
                        this.thaw_current_session_changed ();

                        return GLib.Source.REMOVE;
                    });
                GLib.Source.set_name_by_id (this.session_changed_idle_id,
                                            "Ft.SessionManager.thaw_current_session_changed");
            }
        }

        private void thaw_current_session_changed ()
        {
            if (this.session_changed_idle_id != 0U) {
                GLib.Source.remove (this.session_changed_idle_id);
                this.session_changed_idle_id = 0U;
            }

            if (this.current_session_changed_frozen) {
                assert (this._current_session != null);

                this.current_session_changed_frozen = false;
                this._current_session.thaw_changed ();
            }
        }

        private void emit_session_rescheduled (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this._current_session == null) {
                return;
            }

            if (Ft.Timestamp.is_undefined (timestamp)) {
                timestamp = this.get_current_time ();
            }

            this.session_rescheduled (this._current_session, timestamp);
        }

        private bool should_auto_pause ()
        {
            if (this._current_time_block == null ||
                this._current_time_block.state != Ft.State.POMODORO ||
                !this._timer.is_running () && !this.auto_paused)
            {
                return false;
            }

            if (this.lockscreen != null && this.lockscreen.enabled && this.lockscreen.active) {
                return true;
            }

            if (this.screensaver != null && this.screensaver.enabled && this.screensaver.active) {
                return true;
            }

            return false;
        }

        private bool should_auto_resume ()
        {
            if (!this.auto_paused) {
                return false;
            }

            if (this.lockscreen != null && this.lockscreen.enabled && this.lockscreen.active) {
                return false;
            }

            if (this.screensaver != null && this.screensaver.enabled && this.screensaver.active) {
                return false;
            }

            return true;
        }

        private bool should_auto_advance ()
        {
            if (!this._timer.is_finished () ||
                this._current_time_block == null ||
                this._current_time_block.state != Ft.State.POMODORO ||
                this.next_time_block == null ||
                !this.next_time_block.state.is_break ())
            {
                return false;
            }

            if (this.lockscreen != null && this.lockscreen.enabled && this.lockscreen.active) {
                return true;
            }

            if (this.screensaver != null && this.screensaver.enabled && this.screensaver.active) {
                return true;
            }

            return false;
        }

        private void pause ()
        {
            if (!this.auto_paused)
            {
                this.auto_paused = true;

                Ft.Context.set_event_source ("session-manager.auto-pause");
                this._timer.pause ();
            }
        }

        private void resume ()
        {
            if (this.auto_paused)
            {
                this.auto_paused = false;

                Ft.Context.set_event_source ("session-manager.auto-resume");
                this._timer.resume ();
            }
        }

        private void enable_auto_pause ()
        {
            if (this.lockscreen == null) {
                this.lockscreen = new Ft.LockScreen ();
                this.lockscreen.notify["active"].connect (this.on_lockscreen_notify_active);
            }

            if (this.screensaver == null) {
                this.screensaver = new Ft.ScreenSaver ();
                this.screensaver.notify["active"].connect (this.on_screensaver_notify_active);
            }

            if (this.should_auto_pause ()) {
                this.pause ();
            }
        }

        private void disable_auto_pause ()
        {
            if (this.lockscreen != null) {
                this.lockscreen.notify["active"].disconnect (this.on_lockscreen_notify_active);
                this.lockscreen = null;
            }

            if (this.screensaver != null) {
                this.screensaver.notify["active"].disconnect (this.on_screensaver_notify_active);
                this.screensaver = null;
            }

            this.resume ();
        }

        private void update_auto_pause ()
        {
            if (this._current_time_block != null && this.settings.get_boolean ("pause-on-lockscreen")) {
                this.enable_auto_pause ();
            }
            else {
                this.disable_auto_pause ();
            }
        }

        private void update_time_block_meta (Ft.TimeBlock time_block)
        {
            var completion_time = this._scheduler.calculate_time_block_completion_time (current_time_block);
            current_time_block.set_completion_time (completion_time);

            var weight = this._scheduler.calculate_time_block_weight (current_time_block);
            current_time_block.set_weight (weight);
        }

        /**
         * Update time-block according to changes in timer state.
         */
        private void update_current_time_block (Ft.TimerState current_state,
                                                Ft.TimerState previous_state,
                                                int64         timestamp)
                                                requires (current_state.user_data == this._current_time_block)
                                                requires (this._current_time_block != null)
                                                requires (Ft.Timestamp.is_defined (timestamp))
        {
            var previous_time_block = this.previous_time_block;
            var current_time_block = this._current_time_block;

            this.freeze_current_session_changed ();

            // Handle waiting for an activity.
            if (current_state.user_data == previous_state.user_data &&
                current_state.is_started () &&
                !previous_state.is_started ())
            {
                var overdue = current_state.started_time - previous_time_block.end_time;

                if (previous_time_block != null && overdue < OVERDUE_TIMEOUT) {
                    this.mark_time_block_end (previous_time_block, timestamp);
                }

                current_time_block.move_to (current_state.started_time);
            }

            // Handle duration change.
            current_time_block.end_time = current_state.is_started ()
                    ? current_state.started_time + current_state.offset + current_state.duration
                    : current_time_block.start_time + current_state.offset + current_state.duration;

            if (current_state.user_data == previous_state.user_data &&
                current_state.paused_time == previous_state.paused_time &&
                current_state.offset != previous_state.offset)
            {
                // Handle rewind.
                var interval = current_state.offset - previous_state.offset;

                var gap_flags = current_time_block.state == Ft.State.POMODORO
                        ? Ft.GapFlags.INTERRUPTION
                        : Ft.GapFlags.DEFAULT;
                var gap = new Ft.Gap (gap_flags);
                gap.end_time = this._current_gap != null ? this._current_gap.start_time : timestamp;
                gap.start_time = int64.max (
                        Ft.Timestamp.subtract_interval (gap.end_time, interval),
                        current_time_block.start_time);

                current_time_block.add_gap (gap);
                current_time_block.normalize_gaps ();
            }
            else if (current_state.is_paused ())
            {
                // Mark pause start.
                if (this._current_gap == null)
                {
                    var event_source = Ft.Context.get_event_source ();
                    var gap_flags = current_time_block.state == Ft.State.POMODORO && (
                                    event_source == "timer.pause" ||
                                    event_source == "session-manager.auto-pause")
                            ? Ft.GapFlags.INTERRUPTION
                            : Ft.GapFlags.DEFAULT;
                    this._current_gap = new Ft.Gap.with_start_time (current_state.paused_time,
                                                                          gap_flags);
                    this._current_time_block.add_gap (this._current_gap);
                }
                else {
                    if (this._current_gap.start_time != current_state.paused_time) {
                        GLib.warning ("`Gap.start_time` does not match `TimerState.paused_time`.");
                    }
                }
            }
            else {
                // Mark pause end.
                if (this._current_gap != null)
                {
                    this.mark_gap_end (this._current_gap, timestamp);
                    this._current_gap = null;
                }
            }

            this.update_time_block_meta (current_time_block);
        }

        /**
         * Update resolving timer state according to current session.
         *
         * Start a session or reschedule existing in order to construct a final timer state.
         */
        private void resolve_timer_state (ref Ft.TimerState state,
                                          int64             timestamp)
                                          ensures (state.user_data == this._current_time_block)
                                          ensures (this.current_time_block_entered == (this._current_time_block != null))
        {
            // Timer is paused or has finished. Nothing to resolve.
            // Advancing to a next time-block is handled after emitting `Timer.state_changed`.
            if (state.is_finished () || state.is_paused ()) {
                return;
            }

            // Waiting for activity.
            // `SessionManager` already set up everything in place. Update the timer state.
            if (!state.is_started () && state.user_data == this._current_time_block && this.active_watch_id != 0) {
                return;
            }

            // Stopping (resetting) the timer.
            // Adjust state as if the timer has already stopped. Handling will be continued in `Timer.state_changed`.
            if (!state.is_started () && state.user_data == null)
            {
                if (this._current_time_block != null) {
                    this.advance_to_time_block (null, timestamp);
                    this.initialize_timer_state (ref state, timestamp);
                }
                return;
            }

            // Timer is started by a session manager.
            if (state.user_data == this._current_time_block && this._current_time_block != null) {
                return;
            }

            // Start the timer with a new session.
            if (this._current_session != null && this._current_session.is_expired (timestamp))
            {
                this.advance (state.started_time);
                this.initialize_timer_state (ref state, timestamp);
                return;
            }

            // Starting the timer.
            if (this._current_time_block == null)
            {
                this.advance_to_state (Ft.State.POMODORO, state.started_time);
                this.initialize_timer_state (ref state, timestamp);
                return;
            }
        }

        private void on_timer_resolve_state (ref Ft.TimerState state,
                                             int64             timestamp)
                                             requires (state.user_data == null ||
                                                       state.user_data == this._current_time_block)
        {
            this.resolving_timer_state++;

            this.resolve_timer_state (ref state, timestamp);

            if (this._current_time_block != null) {
                this.update_current_time_block (state, this._timer.state, timestamp);
            }

            this.resolving_timer_state--;
        }

        /**
         * React to timer state changes.
         */
        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            // Remove activity watch upon first change.
            if (this.active_watch_id != 0 && (current_state.is_started () || current_state.user_data == null)) {
                this.idle_monitor.remove_watch (this.active_watch_id);
                this.active_watch_id = 0;
            }

            // HACK: Use `resolving_timer_state` to preserve original timestamp
            //       in `on_current_session_notify_expiry_time()`.
            this.resolving_timer_state++;
            this.bump_expiry_time (SESSION_EXPIRY_TIMEOUT);
            this.update_auto_pause ();
            this.reschedule_if_queued ();
            this.thaw_current_session_changed ();
            this.resolving_timer_state--;
        }

        private void on_timer_finished (Ft.TimerState state)
        {
            this.freeze_current_session_changed ();
            this.enable_idle_monitor ();

            var timestamp        = state.finished_time;
            var next_time_block  = this.initialize_next_time_block (timestamp);
            var advancement_mode = this.resolve_advancement_mode (next_time_block.state, timestamp);

            switch (advancement_mode)
            {
                case Ft.AdvancementMode.CONTINUOUS:
                    if (this.active_watch_id != 0) {
                        this.idle_monitor.remove_watch (this.active_watch_id);
                        this.active_watch_id = 0;
                    }

                    this.advance_to_time_block (next_time_block, timestamp);
                    break;

                case Ft.AdvancementMode.WAIT_FOR_ACTIVITY:
                    // Jump to a next time-block and start the timer after detecting user activity.
                    // It has only one use case: after a break, when we're certain we want to start pomodoro next.
                    // `active_watch_id != 0` will indicate that we're waiting for activity.
                    if (this.active_watch_id == 0) {
                        this.active_watch_id = this.idle_monitor.add_active_watch (this.on_became_active);
                    }

                    this.advance_to_time_block (next_time_block, timestamp);
                    break;

                case Ft.AdvancementMode.CONFIRM:
                    // Keep the current time-block and let the timer indicate it has finished
                    // until user confirms the advancement. Use it if you're uncertain whether the current state
                    // should be extended.
                    if (this.active_watch_id != 0) {
                        this.idle_monitor.remove_watch (this.active_watch_id);
                        this.active_watch_id = 0;
                    }

                    this.confirm_advancement (this._current_time_block, next_time_block);
                    break;

                default:
                    assert_not_reached ();
            }
        }

        private void on_timer_suspending (int64 start_time)
        {
            if (this._current_time_block != null)
            {
                this.pause ();

                // Splitting a gap into smaller chunks would complicate tracking the number of
                // interruptions, so flag ongoing gap as "sleep".
                var gap_flags = Ft.GapFlags.SLEEP;

                if (this._current_time_block.state == Ft.State.POMODORO &&
                    this._timer.is_running ())
                {
                    gap_flags |= Ft.GapFlags.INTERRUPTION;
                }

                if (this._current_gap == null)
                {
                    this._current_gap = new Ft.Gap.with_start_time (start_time, gap_flags);
                    this._current_time_block.add_gap (this._current_gap);
                }
                else {
                    this._current_gap.set_flag (gap_flags);
                }
            }

            if (this._current_session != null)
            {
                GLib.SignalHandler.block (this._current_session, this.current_session_notify_expiry_time_id);
                this._current_session.expiry_time = start_time + SESSION_EXPIRY_TIMEOUT;
                GLib.SignalHandler.unblock (this._current_session, this.current_session_notify_expiry_time_id);
            }

            if (this.expiry_timeout_id != 0)
            {
                GLib.Source.remove (this.expiry_timeout_id);
                this.expiry_timeout_id = 0;
            }
        }

        private void on_timer_suspended (int64 start_time,
                                         int64 end_time)
        {
            if (this._current_session == null) {
                return;
            }

            if (this._current_session.is_expired (end_time)) {
                this.expire_current_session (end_time);
            }
            else {
                this.bump_expiry_time (SESSION_EXPIRY_TIMEOUT);
            }

            if (this._current_gap != null &&
                this._current_gap.start_time == start_time &&
                this._current_gap.has_flag (Ft.GapFlags.SLEEP) &&
                !this.auto_paused)
            {
                this.mark_gap_end (this._current_gap, end_time);
                this._current_gap = null;
            }
        }

        private void on_current_time_block_changed (Ft.TimeBlock time_block)
        {
            if (this.resolving_timer_state == 0) {
                this.reschedule ();
            }
            else {
                this.queue_reschedule ();
            }

            if (this._current_state != time_block.state) {
                this._current_state = time_block.state;
                this.notify_property ("current-state");
            }
        }

        private void on_scheduler_notify_session_template ()
        {
            this.update_has_uniform_breaks ();
            this.queue_reschedule ();
        }

        private void handle_became_active ()
        {
            if (this._timer.user_data == null || this._timer.is_started ()) {
                return;
            }

            if ((this.screensaver != null && this.screensaver.active) ||
                (this.lockscreen != null && this.lockscreen.active))
            {
                return;
            }

            this._timer.start ();
        }

        private void on_lockscreen_notify_active (GLib.Object    object,
                                                  GLib.ParamSpec pspec)
        {
            if (this.should_auto_pause ()) {
                this.pause ();
            }
            else if (this.should_auto_resume ()) {
                this.resume ();
            }
            else if (this.should_auto_advance ()) {
                this.advance ();
            }

            if (!this.lockscreen.active) {
                this.handle_became_active ();
            }
        }

        private void on_screensaver_notify_active (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            if (this.should_auto_pause ()) {
                this.pause ();
            }
            else if (this.should_auto_resume ()) {
                this.resume ();
            }
            else if (this.should_auto_advance ()) {
                this.advance ();
            }

            if (!this.screensaver.active) {
                this.handle_became_active ();
            }
        }

        private void on_became_active ()
        {
            this.active_watch_id = 0;

            this.handle_became_active ();
        }

        private void on_timezone_changed ()
        {
            this.mark_timezone (this.timezone_monitor.timezone);
        }

        /**
         * A wrapper for `Timeout.add_seconds`.
         *
         * We don't want expiry callback to increment the `SessionManager` reference counter,
         * hence the static method and the use of pointer.
         */
        private static uint setup_expiry_timeout (uint  seconds,
                                                  void* session_manager_ptr)
        {
            weak Ft.SessionManager session_manager = (Ft.SessionManager) session_manager_ptr;

            var timeout_id = GLib.Timeout.add_seconds (
                seconds,
                () => {
                    session_manager.expiry_timeout_id = 0;
                    session_manager.expire_current_session (session_manager.current_session.expiry_time);

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (timeout_id,
                                        "Ft.SessionManager.expire_current_session");

            return timeout_id;
        }

        private void on_current_session_notify_expiry_time ()
        {
            var current_time = this.get_current_time ();

            if (this.expiry_timeout_id != 0) {
                GLib.Source.remove (this.expiry_timeout_id);
                this.expiry_timeout_id = 0;
            }

            if (this._current_session.expiry_time > current_time)
            {
                var timeout_seconds = Ft.Timestamp.to_seconds_uint (
                    Ft.Timestamp.round_seconds (this._current_session.expiry_time - current_time));

                this.expiry_timeout_id = Ft.SessionManager.setup_expiry_timeout (timeout_seconds, this);
            }
        }

        private void on_settings_changed (string key)
        {
            switch (key)
            {
                case "pomodoro-duration":
                case "short-break-duration":
                case "long-break-duration":
                case "cycles":
                    this.update_session_template ();
                    break;

                case "pause-on-lockscreen":
                    this.update_auto_pause ();
                    break;

                case "pomodoro-advancement-mode":
                case "break-advancement-mode":
                    break;
            }
        }

        private void enable_idle_monitor ()
        {
            if (this.idle_monitor == null) {
                this.idle_monitor = new Ft.IdleMonitor ();
            }
        }

        private void disable_idle_monitor ()
        {
            if (this.active_watch_id != 0) {
                this.idle_monitor.remove_watch (this.active_watch_id);
                this.active_watch_id = 0;
            }

            this.idle_monitor = null;
        }

        /**
         * Initialize session if there is no current session or if it expired.
         */
        public void ensure_session (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            if (this._current_session == null || this._current_session.is_expired (timestamp))
            {
                var next_session = this.initialize_next_session (timestamp);

                this.set_current_time_block_full (next_session, null, timestamp);
            }
        }

        public bool can_reset ()
        {
            var current_session = this._current_session;
            var is_waiting_for_activity =
                    !this._timer.is_started () && this._timer.user_data != null;

            return current_session != null
                    ? !current_session.is_scheduled () && !is_waiting_for_activity
                    : false;
        }

        /**
         * Start a new session. The `timestamp` marks the end time of ongoing session.
         */
        public void reset (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            var now = Ft.Timestamp.from_now ();

            if (Ft.Timestamp.is_undefined (timestamp)) {
                timestamp = now;
            }

            if (this._current_session != null && !this._current_session.is_scheduled ())
            {
                var next_session = this.initialize_next_session (now);

                this.set_current_time_block_full (next_session, null, timestamp);
            }
        }

        /**
         * Check and expire session if needed. Used in tests.
         */
        public void check_current_session_expired ()
        {
            var timestamp = Ft.Timestamp.from_now ();

            if (this._current_session != null && this._current_session.is_expired (timestamp)) {
                this.expire_current_session (timestamp);
            }
        }

        /**
         * Session is entered as soon as current-session property is set.
         */
        [Signal (run = "first")]
        public signal void enter_session (Ft.Session session)
        {
            assert (session == this._current_session);

            this.current_session_entered = true;
            this.current_session_notify_expiry_time_id = this._current_session.notify["expiry-time"].connect (
                    this.on_current_session_notify_expiry_time);

            this.update_has_uniform_breaks ();
            this.emit_session_rescheduled ();
        }

        [Signal (run = "first")]
        public signal void leave_session (Ft.Session session)
        {
            assert (session == this._current_session);

            this.thaw_current_session_changed ();

            session.disconnect (this.current_session_notify_expiry_time_id);

            this.current_session_entered = false;
            this.current_session_notify_expiry_time_id = 0;
        }

        /**
         * Time block is entered as soon as current-time-block property is set.
         * You should check timer whether time block has really started.
         */
        [Signal (run = "first")]
        public signal void enter_time_block (Ft.TimeBlock time_block)
        {
            assert (time_block == this._current_time_block);
            assert (time_block.get_status () == Ft.TimeBlockStatus.SCHEDULED ||
                    time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);

            if (this.current_time_block_changed_id != 0) {
                GLib.warning ("`TimeBlock.changed` signal handler has not been disconnected properly");
            }

            this.current_time_block_entered = true;
            this.current_time_block_changed_id = time_block.changed.connect (this.on_current_time_block_changed);
            this.next_session = null;
            this.next_time_block = null;

            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
        }

        [Signal (run = "first")]
        public signal void leave_time_block (Ft.TimeBlock time_block)
        {
            assert (time_block == this._current_time_block);
            assert (time_block.get_status () == Ft.TimeBlockStatus.COMPLETED ||
                    time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            this.current_time_block_entered = false;

            if (this.current_time_block_changed_id != 0) {
                time_block.disconnect (this.current_time_block_changed_id);
                this.current_time_block_changed_id = 0;
            }
        }

        public signal void session_rescheduled (Ft.Session session,
                                                int64      timestamp)
        {
            if (this.current_session_changed_frozen && Ft.is_test ()) {
                GLib.debug ("Rescheduled session while setting current-time-block");
            }
        }

        public signal void session_expired (Ft.Session session,
                                            int64      timestamp)
        {
            GLib.debug ("Session expired");
        }

        /**
         * Outward signal that we need a confirmation before advancing to a next time-block.
         * Until then the timer will indicate that it has finished, the session-manager will keep current time-block
         * intact. You should use skip action or `.advance()` to jump to the next time-block.
         */
        public signal void confirm_advancement (Ft.TimeBlock current_time_block,
                                                Ft.TimeBlock next_time_block);

        /**
         * A convenience signal to handle transition between time-blocks.
         *
         * It's emitted after entering the current_time_block.
         */
        public signal void advanced (Ft.Session?   current_session,
                                     Ft.TimeBlock? current_time_block,
                                     Ft.Session?   previous_session,
                                     Ft.TimeBlock? previous_time_block);

        public signal void time_block_saved (Ft.TimeBlock      time_block,
                                             Ft.TimeBlockEntry time_block_entry);

        public signal void gap_saved (Ft.Gap      gap,
                                      Ft.GapEntry gap_entry);

        public override void dispose ()
        {
            if (this._timer != null)
            {
                if (this.timer_resolve_state_id != 0) {
                    this._timer.disconnect (this.timer_resolve_state_id);
                    this.timer_resolve_state_id = 0;
                }

                if (this.timer_state_changed_id != 0) {
                    this._timer.disconnect (this.timer_state_changed_id);
                    this.timer_state_changed_id = 0;
                }

                if (this.timer_finished_id != 0) {
                    this._timer.disconnect (this.timer_finished_id);
                    this.timer_finished_id = 0;
                }

                if (this.timer_suspending_id != 0) {
                    this._timer.disconnect (this.timer_suspending_id);
                    this.timer_suspending_id = 0;
                }

                if (this.timer_suspended_id != 0) {
                    this._timer.disconnect (this.timer_suspended_id);
                    this.timer_suspended_id = 0;
                }
            }

            if (this._scheduler != null) {
                this._scheduler.notify["session-template"].disconnect (
                        this.on_scheduler_notify_session_template);
            }

            if (this.settings != null) {
                this.settings.changed.disconnect (this.on_settings_changed);
            }

            if (this.reschedule_idle_id != 0) {
                GLib.Source.remove (this.reschedule_idle_id);
                this.reschedule_idle_id = 0;
            }

            if (this.session_changed_idle_id != 0) {
                GLib.Source.remove (this.session_changed_idle_id);
                this.session_changed_idle_id = 0;
            }

            if (this.expiry_timeout_id != 0) {
                GLib.Source.remove (this.expiry_timeout_id);
                this.expiry_timeout_id = 0;
            }

            this.disable_auto_pause ();
            this.disable_idle_monitor ();

            this._current_gap = null;
            this._current_time_block = null;
            this._current_session = null;
            this._timer = null;
            this._scheduler = null;
            this.next_time_block = null;
            this.next_session = null;
            this.idle_monitor = null;
            this.timezone_monitor = null;
            this.timezone_history = null;
            this.lockscreen = null;
            this.screensaver = null;
            this.settings = null;

            base.dispose ();
        }
    }
}
