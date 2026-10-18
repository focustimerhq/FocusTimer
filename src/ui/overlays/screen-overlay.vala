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
        [GtkChild]
        private unowned Gtk.Button lock_screen_button;

        private Ft.LockScreen? lock_screen;

        construct
        {
            this.lock_screen = new Ft.LockScreen ();

            this.lock_screen.bind_property ("enabled",
                                            this.lock_screen_button,
                                            "visible",
                                            GLib.BindingFlags.SYNC_CREATE);
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

        // public override void map ()
        // {
        //     base.map ();
        //
        //    // TODO: Reset user idle-time to delay the screen-saver.
        //    // Ft.wake_up_screen ();
        // }

        public override void dispose ()
        {
            this.lock_screen = null;

            base.dispose ();
        }
    }
}
