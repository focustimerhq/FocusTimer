/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public class ApplicationExtension : Ft.ApplicationExtension
    {
        private Gnome.ShellExtension? shell_extension = null;
        private Ft.BackgroundManager? background_manager = null;
        private uint                  background_hold_id = 0U;
        private bool                  enabled = false;

        construct
        {
            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["enabled"].connect (this.on_shell_extension_notify_enabled);

            this.background_manager = new Ft.BackgroundManager ();

            this.update ();
        }

        private void update ()
        {
            var notification_manager = new Ft.NotificationManager ();
            var enabled = this.shell_extension.enabled;

            if (this.enabled == enabled) {
                return;
            }

            this.enabled = enabled;

            if (enabled)
            {
                if (this.background_hold_id == 0U) {
                    this.background_hold_id = this.background_manager.hold_sync ();
                }

                notification_manager.inhibit ();
            }
            else {
                if (this.background_hold_id != 0U) {
                    this.background_manager.release (this.background_hold_id);
                    this.background_hold_id = 0U;
                }

                notification_manager.uninhibit ();
            }
        }

        private void on_shell_extension_notify_enabled (GLib.Object    object,
                                                        GLib.ParamSpec pspec)
        {
            this.update ();
        }

        public override void dispose ()
        {
            if (this.background_hold_id != 0U) {
                this.background_manager.release (this.background_hold_id);
                this.background_hold_id = 0U;
            }

            this.shell_extension = null;
            this.background_manager = null;

            base.dispose ();
        }
    }
}
