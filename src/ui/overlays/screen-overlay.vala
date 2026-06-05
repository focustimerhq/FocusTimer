/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/overlays/screen-overlay.ui")]
    public class ScreenOverlay : Ft.Lightbox
    {
        private const uint CHALLENGE_DURATION = 60U;
        private const uint IDLE_RESET_SECONDS = 3U;

        [GtkChild]
        private unowned Gtk.Button lock_screen_button;
        [GtkChild]
        private unowned Gtk.Stack stack;
        [GtkChild]
        private unowned Gtk.Label challenge_key_label;
        [GtkChild]
        private unowned Gtk.Label challenge_time_label;

        private Ft.LockScreen?          lock_screen;
        private Gtk.EventControllerKey? challenge_key_controller = null;
        private bool                    challenge_active = false;
        private uint                    challenge_remaining = 0;
        private uint                    challenge_idle = 0;
        private uint                    challenge_keyval = 0;
        private uint                    challenge_source_id = 0;

        construct
        {
            this.lock_screen = new Ft.LockScreen ();

            this.lock_screen.bind_property ("enabled",
                                            this.lock_screen_button,
                                            "visible",
                                            GLib.BindingFlags.SYNC_CREATE);

            this.challenge_key_controller = new Gtk.EventControllerKey ();
            this.challenge_key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            this.challenge_key_controller.key_pressed.connect (this.on_challenge_key_pressed);
            ((Gtk.Widget) this).add_controller (this.challenge_key_controller);
        }

        protected override bool handle_escape ()
        {
            this.request_dismiss ();
            return true;
        }

        [GtkCallback]
        private void on_lock_screen_button_clicked (Gtk.Button button)
        {
            this.lock_screen.activate ();
        }

        [GtkCallback]
        private void on_close_button_clicked (Gtk.Button button)
        {
            this.request_dismiss ();
        }

        private void request_dismiss ()
        {
            if (this.challenge_active) {
                return;
            }

            if (!Ft.get_settings ().get_boolean ("screen-overlay-dismiss-challenge")) {
                this.close ();
                return;
            }

            this.start_challenge ();
        }

        private void start_challenge ()
        {
            this.challenge_active = true;
            this.challenge_remaining = CHALLENGE_DURATION;
            this.challenge_idle = 0;

            this.show_contents = true;
            this.stack.visible_child_name = "challenge";

            this.pick_challenge_key ();
            this.update_challenge_labels ();

            this.challenge_source_id = GLib.Timeout.add_seconds (1, this.on_challenge_tick);
            GLib.Source.set_name_by_id (this.challenge_source_id, "Ft.ScreenOverlay.challenge");
        }

        private void finish_challenge ()
        {
            this.stop_challenge ();
            this.close ();
        }

        private void stop_challenge ()
        {
            this.challenge_active = false;

            if (this.challenge_source_id != 0) {
                GLib.Source.remove (this.challenge_source_id);
                this.challenge_source_id = 0;
            }
        }

        private bool on_challenge_tick ()
        {
            this.challenge_idle++;

            if (this.challenge_idle >= IDLE_RESET_SECONDS) {
                this.challenge_remaining = CHALLENGE_DURATION;
                this.update_challenge_labels ();
                return GLib.Source.CONTINUE;
            }

            this.challenge_remaining--;

            if (this.challenge_remaining == 0) {
                this.challenge_source_id = 0;
                this.finish_challenge ();
                return GLib.Source.REMOVE;
            }

            this.update_challenge_labels ();
            return GLib.Source.CONTINUE;
        }

        private bool on_challenge_key_pressed (Gtk.EventControllerKey event_controller,
                                               uint                   keyval,
                                               uint                   keycode,
                                               Gdk.ModifierType       state)
        {
            if (!this.challenge_active) {
                return false;
            }

            if (is_modifier_key (keyval)) {
                return true;
            }

            this.challenge_idle = 0;
            this.challenge_key_label.remove_css_class ("wrong");

            if (Gdk.keyval_to_lower (keyval) != this.challenge_keyval) {
                this.challenge_remaining = CHALLENGE_DURATION;
                this.challenge_key_label.add_css_class ("wrong");
            }

            this.update_challenge_labels ();
            return true;
        }

        private void pick_challenge_key ()
        {
            var offset = GLib.Random.int_range (0, 26);

            this.challenge_keyval = (uint) Gdk.Key.a + (uint) offset;
            this.challenge_key_label.label = ((char) ('A' + offset)).to_string ();
        }

        private void update_challenge_labels ()
        {
            this.challenge_time_label.label = "%02u:%02u".printf (
                                this.challenge_remaining / 60U,
                                this.challenge_remaining % 60U);
        }

        private static bool is_modifier_key (uint keyval)
        {
            switch (keyval)
            {
                case Gdk.Key.Shift_L:
                case Gdk.Key.Shift_R:
                case Gdk.Key.Control_L:
                case Gdk.Key.Control_R:
                case Gdk.Key.Alt_L:
                case Gdk.Key.Alt_R:
                case Gdk.Key.Meta_L:
                case Gdk.Key.Meta_R:
                case Gdk.Key.Super_L:
                case Gdk.Key.Super_R:
                case Gdk.Key.Hyper_L:
                case Gdk.Key.Hyper_R:
                case Gdk.Key.Caps_Lock:
                case Gdk.Key.Shift_Lock:
                case Gdk.Key.Num_Lock:
                case Gdk.Key.ISO_Level3_Shift:
                    return true;
                default:
                    return false;
            }
        }

        public override void dispose ()
        {
            this.stop_challenge ();

            this.lock_screen = null;

            base.dispose ();
        }
    }
}
