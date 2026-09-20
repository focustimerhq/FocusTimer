/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public class WindowExtension : Ft.WindowExtension
    {
        private const int64 INSTALL_EXTENSION_TOAST_INTERVAL = Ft.Interval.DAY * 14;

        private GLib.Settings?          settings = null;
        private Gnome.ShellExtension?   shell_extension = null;
        private Adw.Toast?              extension_toast = null;
        private static bool             extension_toast_dismissed = false;

        construct
        {
            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.gnome");

            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["available"].connect (this.on_extension_notify_available);

            this.notify["window"].connect (this.on_notify_window);
        }

        private void show_install_extension_toast ()
        {
            if (Gnome.WindowExtension.extension_toast_dismissed ||
                this.extension_toast != null ||
                this.window == null)
            {
                return;
            }

            var toast = new Adw.Toast (_("Try the GNOME extension"));
            toast.button_label = _("Details");
            toast.priority = Adw.ToastPriority.HIGH;
            toast.timeout = 0;
            toast.button_clicked.connect (
                () => {
                    var dialog = new Gnome.InstallExtensionDialog ();
                    dialog.present (this.window);

                    this.extension_toast = null;
                });
            toast.dismissed.connect (
                (_toast) => {
                    if (this.extension_toast == _toast) {
                        this.extension_toast = null;
                        this.settings.set_int64 (
                                "last-toast-dismissed-time",
                                Ft.Timestamp.from_now () / Ft.Interval.SECOND);

                        Gnome.WindowExtension.extension_toast_dismissed = true;
                    }
                });

            this.extension_toast = toast;

            this.window.add_toast (toast);
        }

        private void show_enable_extension_toast ()
        {
            if (Gnome.WindowExtension.extension_toast_dismissed ||
                this.extension_toast != null ||
                this.window == null)
            {
                return;
            }

            var toast = new Adw.Toast (_("GNOME extension is disabled"));
            toast.button_label = _("Enable");
            toast.priority = Adw.ToastPriority.HIGH;
            toast.timeout = 0;
            toast.button_clicked.connect (
                () => {
                    this.shell_extension.enable_extension.begin ();
                    this.extension_toast = null;
                });
            toast.dismissed.connect (
                (_toast) => {
                    if (this.extension_toast == _toast) {
                        this.extension_toast = null;

                        Gnome.WindowExtension.extension_toast_dismissed = true;
                    }
                });

            this.extension_toast = toast;

            this.window.add_toast (toast);
        }

        private bool has_toast_been_dismissed ()
        {
            var now = Ft.Timestamp.from_now ();
            var last_dismissed_timestamp = this.settings.get_int64 (
                    "last-toast-dismissed-time").clamp (0, now / Ft.Interval.SECOND);
            if (last_dismissed_timestamp <= 0) {
                return false;
            }

            return now - last_dismissed_timestamp * Ft.Interval.SECOND <
                   INSTALL_EXTENSION_TOAST_INTERVAL;
        }

        private void update_extension_toast ()
        {
            if (this.window == null || !this.window.get_mapped ()) {
                return;
            }

            if (this.shell_extension.available &&
                !this.shell_extension.is_installed () &&
                !this.has_toast_been_dismissed ())
            {
                this.show_install_extension_toast ();
            }
            else if (this.shell_extension.available &&
                !this.shell_extension.enabled &&
                this.shell_extension.is_installed ())
            {
                this.show_enable_extension_toast ();
            }
            else if (this.extension_toast != null) {
                var extension_toast = this.extension_toast;

                this.extension_toast = null;
                extension_toast.dismiss ();
            }
        }

        private void on_notify_window (GLib.Object    object,
                                       GLib.ParamSpec pspec)
        {
            if (this.window != null) {
                this.window.map.connect (this.on_map);
            }
        }

        private void on_map ()
        {
            this.update_extension_toast ();
        }

        private void on_extension_notify_available (GLib.Object    object,
                                                    GLib.ParamSpec pspec)
        {
            this.update_extension_toast ();
        }

        public override void dispose ()
        {
            if (this.window != null) {
                this.window.map.disconnect (this.on_map);
            }

            if (this.shell_extension != null) {
                this.shell_extension.notify["available"].disconnect (this.on_extension_notify_available);
                this.shell_extension = null;
            }

            this.extension_toast = null;
            this.settings = null;

            base.dispose ();
        }
    }
}
