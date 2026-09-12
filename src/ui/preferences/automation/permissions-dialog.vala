/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/automation/permissions-dialog.ui")]
    public sealed class PermissionsDialog : Adw.Dialog
    {
        private const string GRANT_PERMISSION_COMMAND = "flatpak override --user --talk-name=org.freedesktop.Flatpak %s";

        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild]
        private unowned Gtk.Label talk_name_label;
        [GtkChild]
        private unowned Gtk.Label command_label;

        construct
        {
            this.command_label.label = GRANT_PERMISSION_COMMAND.printf (Config.APPLICATION_ID);
        }

        private void copy_to_clipboard (string text)
        {
            var display = Gdk.Display.get_default ();
            var clipboard = display?.get_clipboard ();

            if (clipboard != null) {
                clipboard.set_text (text);

                var toast = new Adw.Toast (_("Copied"));
                this.toast_overlay.add_toast (toast);
            }
        }

        [GtkCallback]
        private void on_talk_name_button_clicked (Gtk.Button button)
        {
            this.copy_to_clipboard (this.talk_name_label.label);
        }

        [GtkCallback]
        private void on_command_button_clicked (Gtk.Button button)
        {
            this.copy_to_clipboard (this.command_label.label);
        }
    }
}
