/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Mpris
{
    public class ApplicationExtension : Ft.ApplicationExtension
    {
        private GLib.Settings?                              settings = null;
        private Ft.Timer?                                   timer = null;
        private Ft.SessionManager?                          session_manager = null;
        private GLib.Cancellable?                           cancellable = null;
        private GLib.DBusConnection?                        connection = null;
        private uint                                        name_owner_changed_id = 0;
        private GLib.HashTable<string, Mpris.PlayerWrapper> players = null;
        private Ft.State                                    effective_state = Ft.State.STOPPED;
        private Ft.SoundManager?                            sound_manager = null;
        private bool                                        background_sound_inhibited = false;

        construct
        {
            this.players = new GLib.HashTable<string, Mpris.PlayerWrapper> (GLib.str_hash,
                                                                            GLib.str_equal);
            this.cancellable = new GLib.Cancellable ();

            this.timer = Ft.Timer.get_default ();
            this.session_manager = Ft.SessionManager.get_default ();

            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.mpris");
            this.settings.changed.connect (this.on_settings_changed);

            var application = Ft.Application.get_default ();
            application.shutdown.connect (() => this.disable ());

            if (application.ready) {
                this.init ();
            }
            else {
                application.notify["ready"].connect (() => this.init ());
            }
        }

        private void init (int timeout = -1)
        {
            var current_time_block = timer.user_data as Ft.TimeBlock;
            this.effective_state = current_time_block != null && this.timer.is_started ()
                    ? current_time_block.state
                    : Ft.State.STOPPED;

            try {
                this.connection = GLib.Bus.get_sync (BusType.SESSION);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while obtaining D-Bus connection: %s", error.message);
                return;
            }

            this.name_owner_changed_id = dbus_subscribe_name_owner_changed (
                    this.connection,
                    this.on_name_owner_changed);

            foreach (var dbus_name in list_dbus_names (this.connection, timeout))
            {
                if (dbus_name.has_prefix (DBUS_NAME_PREFIX)) {
                    this.add_player (dbus_name);
                }
            }

            this.sound_manager = new Ft.SoundManager ();

            this.update_background_sound_inhibitor ();

            if (this.settings.get_boolean ("control-media-playback")) {
                this.enable ();
            }
        }

        private inline void foreach_player (GLib.Func<unowned Mpris.PlayerWrapper> func)
        {
            this.players.@foreach (
                (bus_name, player) => {
                    func (player);
                });
        }

        private void update_background_sound_inhibitor ()
        {
            if (this.sound_manager == null) {
                return;
            }

            var inhibit_background_sound = this.settings.get_boolean ("inhibit-background-sound");
            var playing_count = 0U;

            this.foreach_player (
                (player) => {
                    if (player.status == Mpris.PlaybackStatus.PLAYING) {
                        playing_count++;
                    }
                });

            if (playing_count > 0 &&
                inhibit_background_sound &&
                !this.background_sound_inhibited)
            {
                this.background_sound_inhibited = true;
                this.sound_manager.inhibit_background_sound ();
            }
            else if (this.background_sound_inhibited && (
                     playing_count == 0 || !inhibit_background_sound))
            {
                this.background_sound_inhibited = false;
                this.sound_manager.uninhibit_background_sound ();
            }
        }

        private void enable ()
        {
            this.timer.state_changed.connect (this.on_timer_state_changed);
        }

        private void disable ()
        {
            this.timer.state_changed.disconnect (this.on_timer_state_changed);

            this.foreach_player (
                (player) => {
                    player.auto_paused = false;
                });
        }

        private void add_player (string dbus_name)
        {
            if (this.players.contains (dbus_name)) {
                return;
            }

            var player = new Mpris.PlayerWrapper (dbus_name, this.cancellable);
            player.status_changed.connect (this.on_player_status_changed);

            this.players.insert (dbus_name, player);

            this.update_background_sound_inhibitor ();
        }

        private void remove_player (string dbus_name)
        {
            var player = this.players.lookup (dbus_name);
            if (player == null) {
                return;
            }

            player.status_changed.disconnect (this.on_player_status_changed);

            this.players.remove (dbus_name);

            this.update_background_sound_inhibitor ();
        }

        /**
         * Do not auto-resume playback if there's other media playing.
         *
         * TODO: detect videocall
         */
        private bool can_resume_playback ()
        {
            var can_resume = true;

            this.foreach_player (
                (player) => {
                    if (player.status == Mpris.PlaybackStatus.PLAYING && !player.is_pausing ()) {
                        can_resume = false;
                    }
                });

            return can_resume;
        }

        private void pause_playback (Ft.State assigned_state)
        {
            this.foreach_player (
                (player) => {
                    if (player.status != Mpris.PlaybackStatus.PLAYING ||
                        player.associated_state != assigned_state)
                    {
                        return;
                    }

                    player.pause.begin (
                        (obj, res) => {
                            if (player.pause.end (res)) {
                                player.auto_paused = true;
                            }
                        });
                });
        }

        private void resume_playback (Ft.State assigned_state)
        {
            var can_resume = this.can_resume_playback ();
            var resuming = false;

            this.foreach_player (
                (player) => {
                    if (!player.auto_paused ||
                        player.associated_state != assigned_state)
                    {
                        return;
                    }

                    if (can_resume)
                    {
                        player.resume.begin (
                            (obj, res) => {
                                if (player.resume.end (res)) {
                                    player.auto_paused = false;
                                }
                            });
                        resuming = true;
                    }
                    else {
                        player.auto_paused = false;
                    }
                });

            // Anticipate that the player state will soon change to PLAYING.
            // It's a workaround for buggy fade-in/out animation.
            if (resuming && !this.background_sound_inhibited) {
                this.background_sound_inhibited = true;
                this.sound_manager.inhibit_background_sound ();
            }
        }

        private void on_name_owner_changed (GLib.DBusConnection connection,
                                            string              dbus_name,
                                            string              old_owner,
                                            string              new_owner)
        {
            if (!dbus_name.has_prefix (DBUS_NAME_PREFIX)) {
                return;
            }

            if (old_owner != "") {
                this.remove_player (dbus_name);
            }

            if (new_owner != "") {
                this.add_player (dbus_name);
            }
        }

        private void on_player_status_changed (Mpris.PlayerWrapper  player,
                                               Mpris.PlaybackStatus status,
                                               Mpris.PlaybackStatus previous_status)
        {
            var current_time_block = this.timer.user_data as Ft.TimeBlock;
            var is_waiting_for_activity = current_time_block != null && !this.timer.is_started ();

            this.update_background_sound_inhibitor ();

            if (status == Mpris.PlaybackStatus.PLAYING &&
                is_waiting_for_activity &&
                player.auto_paused &&
                player.associated_state == Ft.State.POMODORO)
            {
                // Treat resuming playback as an activity that resumes the timer,
                // even on lock-screen.
                var timer_action_group = new Ft.TimerActionGroup ();
                timer_action_group.activate_action ("start", null);
            }
            else if (status == Mpris.PlaybackStatus.PLAYING ||
                     previous_status == Mpris.PlaybackStatus.UNKNOWN)
            {
                // When we're about to start Pomodoro, assume the PLAYING state is attributed to
                // the Pomodoro, even if advancement hasn't been confirmed yet.
                var effective_state = is_waiting_for_activity && status == Mpris.PlaybackStatus.PLAYING
                        ? current_time_block.state
                        : this.effective_state;

                player.associated_state = effective_state;
                player.auto_paused = false;
            }
            else if (previous_status == Mpris.PlaybackStatus.PLAYING &&
                     current_time_block != null &&
                     this.session_manager.lockscreen_active)
            {
                // Mark manually pausing playback on the lock-screen with `auto-paused`,
                // to auto resume playback later.
                player.auto_paused = true;
            }
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            var current_time_block = current_state.user_data as Ft.TimeBlock;
            var previous_time_block = previous_state.user_data as Ft.TimeBlock;

            var effective_state = current_time_block != null
                    ? current_time_block.state
                    : Ft.State.STOPPED;
            var is_paused = current_state.is_paused ();
            var previous_effective_state = this.effective_state;
            var previous_is_paused = previous_state.is_paused ();

            if (effective_state != Ft.State.STOPPED &&
                !current_state.is_started () && previous_time_block != null)
            {
                effective_state = previous_time_block.state;
            }

            if (effective_state.is_break ()) {
                effective_state = Ft.State.BREAK;
            }

            this.effective_state = effective_state;

            if (effective_state == Ft.State.STOPPED &&
                previous_effective_state != Ft.State.POMODORO)
            {
                return;
            }

            if (previous_effective_state == Ft.State.STOPPED)
            {
                this.foreach_player (
                    (player) => {
                        player.auto_paused = false;

                        if (player.status == Mpris.PlaybackStatus.PLAYING) {
                            player.associated_state = effective_state;
                        }
                    });
            }

            if (effective_state != previous_effective_state)
            {
                this.pause_playback (previous_effective_state);

                if (effective_state == Ft.State.POMODORO &&
                    previous_effective_state == Ft.State.BREAK &&
                    !is_paused)
                {
                    this.resume_playback (effective_state);
                }
            }
            else if (is_paused != previous_is_paused)
            {
                if (is_paused) {
                    this.pause_playback (effective_state);
                }
                else {
                    this.resume_playback (effective_state);
                }
            }
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "control-media-playback":
                    if (settings.get_boolean (key)) {
                        this.enable ();
                    }
                    else {
                        this.disable ();
                    }

                    break;

                case "inhibit-background-sound":
                    this.update_background_sound_inhibitor ();
                    break;

                default:
                    break;
            }
        }

        public override void dispose ()
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            if (this.name_owner_changed_id != 0 && this.connection != null) {
                this.connection.signal_unsubscribe (this.name_owner_changed_id);
                this.name_owner_changed_id = 0;
            }

            if (this.settings != null) {
                this.settings.changed.disconnect (this.on_settings_changed);
                this.settings = null;
            }

            if (this.timer != null) {
                this.timer.state_changed.disconnect (this.on_timer_state_changed);
                this.timer = null;
            }

            if (this.background_sound_inhibited) {
                this.background_sound_inhibited = false;
                this.sound_manager.uninhibit_background_sound ();
            }

            this.connection = null;
            this.players = null;
            this.sound_manager = null;
            this.session_manager = null;

            base.dispose ();
        }
    }
}
