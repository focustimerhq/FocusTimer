/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    [SingleInstance]
    public class SoundManager : GLib.Object
    {
        private const int64 SHORT_FADE_DURATION = 300 * Ft.Interval.MILLISECOND;
        private const int64 LONG_FADE_DURATION  = Ft.Interval.SECOND;

        // Silence at the end of Pomodoro serves as a cue that it's about to end
        private const int64 ABOUT_TO_END_TIME = 10 * Ft.Interval.SECOND;

        [CCode (notify = false)]
        public bool muted {
            get {
                return this._muted;
            }
            set {
                if (this._muted == value) {
                    return;
                }

                this._muted = value;
                this.update_background_sound (false);
                this.notify_property ("muted");
            }
        }

        private bool                _muted = false;
        private Ft.AlertSound?      pomodoro_finished_sound = null;
        private Ft.AlertSound?      break_finished_sound = null;
        private Ft.BackgroundSound? background_sound = null;
        private uint                background_sound_inhibit_count = 0;
        private GLib.Settings?      settings = null;
        private Ft.Timer?           timer = null;
        private ulong               timer_state_changed_id = 0;
        private uint                fade_out_timeout_id = 0;

        construct
        {
            this.timer = Ft.Timer.get_default ();
            this.timer_state_changed_id = this.timer.state_changed.connect_after (this.on_timer_state_changed);

            this.pomodoro_finished_sound = new Ft.AlertSound ("pomodoro-finished");
            this.break_finished_sound = new Ft.AlertSound ("break-finished");
            this.background_sound = new Ft.BackgroundSound ();
            this.background_sound.loop = true;
            this.background_sound.fade_out (0);

            this.settings = Ft.get_settings ();
            this.settings.bind ("pomodoro-finished-sound",
                                this.pomodoro_finished_sound,
                                "uri",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("pomodoro-finished-sound-volume",
                                this.pomodoro_finished_sound,
                                "volume",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("break-finished-sound",
                                this.break_finished_sound,
                                "uri",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("break-finished-sound-volume",
                                this.break_finished_sound,
                                "volume",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("background-sound",
                                this.background_sound,
                                "uri",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("background-sound-volume",
                                this.background_sound,
                                "volume",
                                GLib.SettingsBindFlags.DEFAULT);

            this.update_background_sound ();
        }

        private void schedule_fade_out (int64 timeout)
                                        requires (this.fade_out_timeout_id == 0)
        {
            this.fade_out_timeout_id = GLib.Timeout.add (Ft.Timestamp.to_milliseconds_uint (timeout),
                                                         this.on_fade_out_timeout);
            GLib.Source.set_name_by_id (this.fade_out_timeout_id, "Ft.SoundManager.on_fade_out_timeout");
        }

        private void unschedule_fade_out ()
        {
            if (this.fade_out_timeout_id != 0) {
                GLib.Source.remove (this.fade_out_timeout_id);
                this.fade_out_timeout_id = 0;
            }
        }

        private void update_background_sound (bool animate = true)
        {
            this.unschedule_fade_out ();

            if (this._muted) {
                this.background_sound.fade_out (0);
                return;
            }

            if (this.background_sound_inhibit_count != 0) {
                this.background_sound.fade_out (LONG_FADE_DURATION);
                return;
            }

            if (!this.background_sound.can_play ()) {
                return;
            }

            var current_time_block = this.timer.user_data as Ft.TimeBlock;
            var current_state = current_time_block != null
                    ? current_time_block.state
                    : Ft.State.STOPPED;

            if (current_state == Ft.State.POMODORO && this.timer.is_running ())
            {
                var remaining = this.timer.calculate_remaining ();
                var fade_duration = animate ? LONG_FADE_DURATION : 0;

                if (remaining > ABOUT_TO_END_TIME) {
                    this.background_sound.fade_in (fade_duration);
                    this.schedule_fade_out (remaining - ABOUT_TO_END_TIME);
                }
                else {
                    if (animate) {
                        fade_duration = int64.max (remaining - Ft.Interval.SECOND,
                                                   SHORT_FADE_DURATION);
                    }

                    this.background_sound.fade_out (fade_duration);
                }
            }
            else {
                this.background_sound.fade_out (animate ? SHORT_FADE_DURATION : 0);
            }
        }

        public void inhibit_background_sound ()
        {
            this.background_sound_inhibit_count++;

            if (this.background_sound_inhibit_count == 1) {
                this.update_background_sound ();
            }
        }

        public void uninhibit_background_sound ()
        {
            this.background_sound_inhibit_count--;

            if (this.background_sound_inhibit_count == 0) {
                this.update_background_sound ();
            }
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            if (current_state.is_finished () &&
                !previous_state.is_finished () &&
                previous_state.user_data != null)
            {
                var current_time_block = current_state.user_data as Ft.TimeBlock;

                if (current_time_block.state == Ft.State.POMODORO) {
                    this.pomodoro_finished_sound.play ();
                }
                else if (current_time_block.state.is_break ()) {
                    this.break_finished_sound.play ();
                }
            }

            this.update_background_sound ();
        }

        private bool on_fade_out_timeout ()
                                          requires (this.timer.is_running ())
        {
            var current_time = this.timer.get_current_time (GLib.MainContext.current_source ().get_time ());
            var remaining = this.timer.calculate_remaining (current_time);
            var fade_out_duration = int64.max (remaining - Ft.Interval.SECOND, SHORT_FADE_DURATION);

            this.fade_out_timeout_id = 0;
            this.background_sound.fade_out (fade_out_duration);

            return GLib.Source.REMOVE;
        }

        public override void dispose ()
        {
            this.unschedule_fade_out ();

            if (this.timer_state_changed_id != 0) {
                this.timer.disconnect (this.timer_state_changed_id);
                this.timer_state_changed_id = 0;
            }

            if (this.pomodoro_finished_sound != null) {
                this.pomodoro_finished_sound.stop ();
                this.pomodoro_finished_sound = null;
            }

            if (this.break_finished_sound != null) {
                this.break_finished_sound.stop ();
                this.break_finished_sound = null;
            }

            if (this.background_sound != null) {
                this.background_sound.stop ();
                this.background_sound = null;
            }

            this.timer = null;
            this.settings = null;

            base.dispose ();
        }
    }
}
