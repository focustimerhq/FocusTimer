/*
 * Copyright (c) 2023-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/overlays/screen-overlay.ui")]
    public class ScreenOverlay : Ft.Lightbox
    {
        /* Time between user input events before watching for dismiss gesture.
         * Value is a little higher than:
         *   - slow typing speed of 23 words per minute which translates
         *     to 523 miliseconds between key presses
         *   - moderate typing speed of 35 words per minute, 343 miliseconds.
         */
        private const uint IDLE_TIME_TO_ACKNOWLEDGE = 700;
        private const double MOTION_VELOCITY_TO_DISMISS = 3.0;

        [CCode (notify = false)]
        public bool enable_dismiss_gesture {
            get {
                return this._enable_dismiss_gesture;
            }
            set {
                if (this._enable_dismiss_gesture == value) {
                    return;
                }

                this._enable_dismiss_gesture = value;
                this.notify_property ("enable-dismiss-gesture");

                if (!this.get_mapped ()) {
                    return;
                }

                this.prepare_dismiss_gesture ();
                this.reset_acknowledge_timeout ();
            }
        }

        public bool acknowledged { get; private set; default = false; }

        [GtkChild]
        private unowned Gtk.Button lock_screen_button;

        private bool                _enable_dismiss_gesture = true;
        private Ft.LockScreen?      lock_screen = null;
        private GLib.Settings?      settings = null;
        private uint                acknowledge_timeout_id = 0;
        private uint                dismiss_idle_id = 0;
        private double              last_motion_x = 0.0;
        private double              last_motion_y = 0.0;
        private uint32              last_motion_time = 0;
        private bool                have_last_motion = false;

        construct
        {
            this.lock_screen = new Ft.LockScreen ();
            this.lock_screen.bind_property ("enabled",
                                            this.lock_screen_button,
                                            "visible",
                                            GLib.BindingFlags.SYNC_CREATE);

            this.settings = Ft.get_settings ();
            this.settings.bind ("dismiss-gesture",
                                this,
                                "enable-dismiss-gesture",
                                GLib.SettingsBindFlags.DEFAULT);
        }

        private bool check_gesture_allowed (Gtk.EventController? controller)
        {
            if (!this.enable_dismiss_gesture || controller == null) {
                return false;
            }

            return controller.get_current_event_device () != null;
        }

        private void remove_acknowledge_timeout ()
        {
            if (this.acknowledge_timeout_id != 0) {
                GLib.Source.remove (this.acknowledge_timeout_id);
                this.acknowledge_timeout_id = 0;
            }
        }

        private void remove_dismiss_idle ()
        {
            if (this.dismiss_idle_id != 0) {
                GLib.Source.remove (this.dismiss_idle_id);
                this.dismiss_idle_id = 0;
            }
        }

        private void queue_dismiss ()
        {
            if (this.dismiss_idle_id != 0 || !this.get_mapped ()) {
                return;
            }

            this.remove_acknowledge_timeout ();

            this.dismiss_idle_id = GLib.Idle.add (() => {
                this.dismiss_idle_id = 0;
                this.close ();

                return GLib.Source.REMOVE;
            });
            GLib.Source.set_name_by_id (this.dismiss_idle_id,
                                        "Ft.ScreenOverlay.dismiss");
        }

        private void reset_acknowledge_timeout ()
        {
            this.remove_acknowledge_timeout ();

            if (!this.enable_dismiss_gesture || this.acknowledged || !this.get_mapped ()) {
                return;
            }

            this.acknowledge_timeout_id = GLib.Timeout.add (
                IDLE_TIME_TO_ACKNOWLEDGE,
                () => {
                    this.acknowledge_timeout_id = 0;
                    this.acknowledge ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.acknowledge_timeout_id,
                                        "Ft.ScreenOverlay.acknowledge");
        }

        private void reset_motion ()
        {
            this.have_last_motion = false;
            this.last_motion_time = 0;
        }

        private void note_motion (double x,
                                  double y,
                                  uint32 time)
        {
            this.last_motion_x = x;
            this.last_motion_y = y;
            this.last_motion_time = time;
            this.have_last_motion = true;
        }

        private void prepare_dismiss_gesture ()
        {
            this.reset_motion ();
            this.acknowledged = false;
            this.remove_css_class ("acknowledged");
        }

        private void acknowledge ()
        {
            if (this.acknowledged || !this.enable_dismiss_gesture) {
                return;
            }

            this.remove_acknowledge_timeout ();
            // Velocity is measured from the first motion after acknowledgement,
            // so the idle gap itself cannot dismiss the overlay.
            this.reset_motion ();
            this.acknowledged = true;
            this.add_css_class ("acknowledged");
        }

        [GtkCallback]
        private bool on_gesture_key_pressed (Gtk.EventControllerKey controller,
                                             uint                   keyval,
                                             uint                   keycode,
                                             Gdk.ModifierType       state)
        {
            if (!this.check_gesture_allowed (controller)) {
                return false;
            }

            if (this.acknowledged) {
                this.queue_dismiss ();
            }
            else {
                this.reset_acknowledge_timeout ();
            }

            // Keep propagating so Ft.Lightbox can still handle Escape.
            return false;
        }

        [GtkCallback]
        private void on_gesture_pressed (Gtk.GestureClick gesture,
                                         int              n_press,
                                         double           x,
                                         double           y)
        {
            if (!this.check_gesture_allowed (gesture)) {
                return;
            }

            if (this.acknowledged) {
                this.queue_dismiss ();
            }
            else {
                this.reset_acknowledge_timeout ();
            }
        }

        [GtkCallback]
        private void on_gesture_motion (Gtk.EventControllerMotion controller,
                                        double                    x,
                                        double                    y)
        {
            if (!this.check_gesture_allowed (controller)) {
                return;
            }

            var time = controller.get_current_event_time ();

            if (!this.acknowledged) {
                this.note_motion (x, y, time);
                this.reset_acknowledge_timeout ();
                return;
            }

            var dismiss = false;

            if (this.have_last_motion)
            {
                var dt = (double) (time - this.last_motion_time);

                if (dt > 0.0) {
                    var dx = x - this.last_motion_x;
                    var dy = y - this.last_motion_y;
                    var velocity_squared = (dx * dx + dy * dy) / (dt * dt);
                    var threshold = MOTION_VELOCITY_TO_DISMISS * MOTION_VELOCITY_TO_DISMISS;

                    dismiss = velocity_squared > threshold;
                }
            }

            this.note_motion (x, y, time);

            if (dismiss) {
                this.queue_dismiss ();
            }
        }

        [GtkCallback]
        private bool on_gesture_scroll (Gtk.EventControllerScroll controller,
                                        double                    dx,
                                        double                    dy)
        {
            if (!this.check_gesture_allowed (controller)) {
                return false;
            }

            if (dx == 0.0 && dy == 0.0) {
                return false;
            }

            if (!this.acknowledged) {
                this.reset_acknowledge_timeout ();
                return false;
            }

            var scroll_event = controller.get_current_event () as Gdk.ScrollEvent;

            if (scroll_event != null &&
                scroll_event.get_unit () == Gdk.ScrollUnit.SURFACE)
            {
                this.queue_dismiss ();
            }

            return false;
        }

        [GtkCallback]
        private void on_lock_screen_button_clicked (Gtk.Button button)
        {
            this.lock_screen.activate ();
        }

        [GtkCallback]
        private void on_close_button_clicked (Gtk.Button button)
        {
            this.close ();
        }

        public override void map ()
        {
            this.prepare_dismiss_gesture ();

            base.map ();

            this.reset_acknowledge_timeout ();
        }

        public override void unmap ()
        {
            this.remove_acknowledge_timeout ();
            this.remove_dismiss_idle ();

            base.unmap ();
        }

        public override void dispose ()
        {
            this.remove_acknowledge_timeout ();
            this.remove_dismiss_idle ();

            this.lock_screen = null;
            this.settings = null;

            base.dispose ();
        }
    }
}
