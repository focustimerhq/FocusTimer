/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public class WindowExtension : Ft.WindowExtension
    {
        private Gnome.ShellExtension? shell_extension = null;
        private Adw.Toast?            install_extension_toast = null;
        private static bool           install_extension_toast_dismissed = false;

        construct
        {
            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["available"].connect (this.on_extension_notify_available);

            this.notify["window"].connect (this.on_notify_window);
        }

        private void show_install_extension_toast ()
        {
            if (Gnome.WindowExtension.install_extension_toast_dismissed ||
                this.install_extension_toast != null ||
                this.window == null)
            {
                return;
            }

            var toast = new Adw.Toast (_("GNOME Shell extension available"));
            toast.button_label = _("Learn More");
            toast.priority = Adw.ToastPriority.HIGH;
            toast.timeout = 0;
            toast.button_clicked.connect (
                () => {
                    var dialog = new Gnome.InstallExtensionDialog ();

                    dialog.present (this.window);
                    this.install_extension_toast = null;
                });
            toast.dismissed.connect (this.on_install_extension_toast_dismissed);

            this.install_extension_toast = toast;

            this.window.add_toast (toast);
        }

        private void update_install_extension_toast ()
        {
            if (!Gnome.ShellExtension.IS_PUBLISHED) {
                return;
            }

            if (this.window == null || !this.window.get_mapped ()) {
                return;
            }

            if (this.shell_extension.available && !this.shell_extension.is_installed ()) {
                this.show_install_extension_toast ();
            }
            else if (this.install_extension_toast != null) {
                this.install_extension_toast.dismissed.disconnect (
                        this.on_install_extension_toast_dismissed);
                this.install_extension_toast.dismiss ();
                this.install_extension_toast = null;
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
            this.update_install_extension_toast ();
        }

        private void on_extension_notify_available (GLib.Object    object,
                                                    GLib.ParamSpec pspec)
        {
            this.update_install_extension_toast ();
        }

        private void on_install_extension_toast_dismissed (Adw.Toast toast)
        {
            this.install_extension_toast = null;

            Gnome.WindowExtension.install_extension_toast_dismissed = true;
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

            this.install_extension_toast = null;

            base.dispose ();
        }
    }
}
