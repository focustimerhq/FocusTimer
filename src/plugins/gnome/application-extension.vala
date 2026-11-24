/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public class ApplicationExtension : Ft.ApplicationExtension
    {
        private Ft.BackgroundManager?   background_manager = null;
        private Ft.NotificationManager? notification_manager = null;
        private Gnome.Shell?            shell_proxy = null;
        private Gnome.ShellExtension?   shell_extension = null;
        private bool                    shell_extension_enabled = false;
        private uint                    shell_watcher_id = 0;
        private uint                    background_hold_id = 0U;

        construct
        {
            this.background_manager = new Ft.BackgroundManager ();

            this.notification_manager = new Ft.NotificationManager ();
            this.notification_manager.screen_overlay_opened.connect (this.on_screen_overlay_opened);

            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["enabled"].connect (this.on_shell_extension_notify_enabled);

            this.shell_watcher_id = GLib.Bus.watch_name (
                    GLib.BusType.SESSION,
                    "org.gnome.Shell",
                    GLib.BusNameWatcherFlags.NONE,
                    this.on_shell_name_appeared,
                    this.on_shell_name_vanished);

            this.update ();
        }

        private void update ()
        {
            var notification_manager = new Ft.NotificationManager ();
            var shell_extension_enabled = this.shell_extension.enabled;

            if (this.shell_extension_enabled == shell_extension_enabled) {
                return;
            }

            this.shell_extension_enabled = shell_extension_enabled;

            if (shell_extension_enabled)
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

        private void on_shell_name_appeared (GLib.DBusConnection connection,
                                             string              name,
                                             string              name_owner)
        {
            if (this.shell_proxy != null) {
                return;
            }

            try {
                this.shell_proxy = GLib.Bus.get_proxy_sync<Gnome.Shell> (
                        GLib.BusType.SESSION,
                        "org.gnome.Shell",
                        "/org/gnome/Shell",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START |
                        GLib.DBusProxyFlags.DO_NOT_CONNECT_SIGNALS,
                        null);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while initializing shell proxy: %s", error.message);
            }
        }

        private void on_shell_name_vanished (GLib.DBusConnection? connection,
                                             string               name)
        {
            this.shell_proxy = null;
        }

        private void on_shell_extension_notify_enabled (GLib.Object    object,
                                                        GLib.ParamSpec pspec)
        {
            this.update ();
        }

        private void on_screen_overlay_opened ()
        {
            if (this.shell_extension.enabled) {
                return;
            }

            if (this.shell_proxy != null && this.shell_proxy.overview_active) {
                this.shell_proxy.overview_active = false;
            }
        }

        public override void dispose ()
        {
            if (this.shell_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.shell_watcher_id);
                this.shell_watcher_id = 0;
            }

            if (this.background_hold_id != 0U) {
                this.background_manager.release (this.background_hold_id);
                this.background_hold_id = 0U;
            }

            if (this.notification_manager != null) {
                this.notification_manager.screen_overlay_opened.disconnect (this.on_screen_overlay_opened);
                this.notification_manager = null;
            }

            this.shell_extension = null;
            this.shell_proxy = null;
            this.background_manager = null;

            base.dispose ();
        }
    }
}