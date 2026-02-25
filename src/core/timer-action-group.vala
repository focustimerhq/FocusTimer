/*
 * Copyright (c) 2016-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    public class TimerActionGroup : GLib.SimpleActionGroup
    {
        public Ft.Timer timer { get; construct; }

        public TimerActionGroup ()
        {
            GLib.Object (
                timer: Ft.Timer.get_default ()
            );
        }

        public TimerActionGroup.with_timer (Ft.Timer timer)
        {
            GLib.Object (
                timer: timer
            );
        }

        construct
        {
            var start_action = new GLib.SimpleAction ("start", null);
            start_action.activate.connect (this.activate_start);
            this.add_action (start_action);

            var reset_action = new GLib.SimpleAction ("reset", null);
            reset_action.activate.connect (this.activate_reset);
            this.add_action (reset_action);

            var pause_action = new GLib.SimpleAction ("pause", null);
            pause_action.activate.connect (this.activate_pause);
            this.add_action (pause_action);

            var resume_action = new GLib.SimpleAction ("resume", null);
            resume_action.activate.connect (this.activate_resume);
            this.add_action (resume_action);

            var rewind_action = new GLib.SimpleAction ("rewind", null);
            rewind_action.activate.connect (this.activate_rewind);
            this.add_action (rewind_action);

            var rewind_by_action = new GLib.SimpleAction ("rewind-by", GLib.VariantType.INT32);
            rewind_by_action.activate.connect (this.activate_rewind);
            this.add_action (rewind_by_action);

            var toggle_action = new GLib.SimpleAction ("toggle", null);  // alias for start-stop
            toggle_action.activate.connect (this.activate_start_stop);
            this.add_action (toggle_action);

            var start_stop_action = new GLib.SimpleAction ("start-stop", null);
            start_stop_action.activate.connect (this.activate_start_stop);
            this.add_action (start_stop_action);

            var start_pause_resume_action = new GLib.SimpleAction ("start-pause-resume", null);
            start_pause_resume_action.activate.connect (this.activate_start_pause_resume);
            this.add_action (start_pause_resume_action);

            var shorten_action = new GLib.SimpleAction ("shorten", null);
            shorten_action.activate.connect (this.activate_shorten);
            this.add_action (shorten_action);

            var extend_action = new GLib.SimpleAction ("extend", null);
            extend_action.activate.connect (this.activate_extend);
            this.add_action (extend_action);

            var extend_by_action = new GLib.SimpleAction ("extend-by", GLib.VariantType.INT32);
            extend_by_action.activate.connect (this.activate_extend);
            this.add_action (extend_by_action);
        }

        private void activate_start (GLib.SimpleAction action,
                                     GLib.Variant?     parameter)
        {
            Ft.Context.set_event_source ("timer.start");
            this.timer.start ();
        }

        private void activate_reset (GLib.SimpleAction action,
                                     GLib.Variant?     parameter)
        {
            Ft.Context.set_event_source ("timer.reset");
            this.timer.reset ();
        }

        private void activate_pause (GLib.SimpleAction action,
                                     GLib.Variant?     parameter)
        {
            Ft.Context.set_event_source ("timer.pause");
            this.timer.pause ();
        }

        private void activate_resume (GLib.SimpleAction action,
                                      GLib.Variant?     parameter)
        {
            Ft.Context.set_event_source ("timer.resume");
            this.timer.resume ();
        }

        private void activate_rewind (GLib.SimpleAction action,
                                      GLib.Variant?     parameter)
        {
            var interval = parameter != null
                    ? parameter.get_int32 () * Ft.Interval.SECOND
                    : Ft.Interval.MINUTE;

            Ft.Context.set_event_source ("timer.rewind");
            this.timer.rewind (interval);
        }

        private void activate_start_stop (GLib.SimpleAction action,
                                          GLib.Variant?     parameter)
        {
            if (!this.timer.is_started ()) {
                Ft.Context.set_event_source ("timer.start");
                this.timer.start ();
            }
            else {
                Ft.Context.set_event_source ("timer.reset");
                this.timer.reset ();
            }
        }

        private void activate_start_pause_resume (GLib.SimpleAction action,
                                                  GLib.Variant?     parameter)
        {
            if (!this.timer.is_started ()) {
                Ft.Context.set_event_source ("timer.start");
                this.timer.start ();
            }
            else if (this.timer.is_paused ()) {
                Ft.Context.set_event_source ("timer.resume");
                this.timer.resume ();
            }
            else {
                Ft.Context.set_event_source ("timer.pause");
                this.timer.pause ();
            }
        }

        private void activate_shorten (GLib.SimpleAction action,
                                       GLib.Variant?     parameter)
        {
            var interval = parameter != null
                    ? parameter.get_int32 () * Ft.Interval.SECOND
                    : Ft.Interval.MINUTE;

            this.timer.extend (-interval);
        }

        private void activate_extend (GLib.SimpleAction action,
                                      GLib.Variant?     parameter)
        {
            var interval = parameter != null
                    ? parameter.get_int32 () * Ft.Interval.SECOND
                    : Ft.Interval.MINUTE;

            this.timer.extend (interval);
        }
    }
}
