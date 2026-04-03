/*
 * Copyright (c) 2025-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Gnome
{
    [GtkTemplate (ui = "/plugins/gnome/install-extension-dialog.ui")]
    public class InstallExtensionDialog : Adw.Dialog
    {
        private uint CLOSE_TIMEOUT_SECONDS = 3;

        [GtkChild]
        private unowned Gtk.Stack stack;
        [GtkChild]
        private unowned Gtk.Label error_message_label;
        [GtkChild]
        private unowned Gtk.TextView error_text_view;

        private Gnome.ShellExtension? shell_extension = null;
        private uint                  timeout_id = 0U;

        construct
        {
            this.shell_extension = new Gnome.ShellExtension ();
        }

        private void close_after_timeout (uint seconds)
        {
            if (this.timeout_id != 0U) {
                GLib.Source.remove (this.timeout_id);
            }

            this.timeout_id = GLib.Timeout.add_seconds (
                seconds,
                () => {
                    this.timeout_id = 0U;
                    this.close ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.timeout_id,
                                        "Gnome.InstallExtensionDialog.close_after_timeout");
        }

        private void show_spinner ()
        {
            this.stack.visible_child_name = "spinner";
            this.can_close = false;
        }

        [GtkCallback]
        private void on_install_clicked ()
        {
            if (!this.can_close) {
                return;
            }

            this.show_spinner ();

            this.shell_extension.install_extension.begin (
                (obj, res) => {
                    try {
                        var success = this.shell_extension.install_extension.end (res);

                        this.can_close = true;

                        if (success) {
                            this.stack.visible_child_name = "success";
                            this.close_after_timeout (CLOSE_TIMEOUT_SECONDS);
                        }
                        else {
                            this.close ();
                        }
                    }
                    catch (Gnome.ShellExtensionError error)
                    {
                        switch (error.code)
                        {
                            case Gnome.ShellExtensionError.TIMED_OUT:
                                this.error_message_label.label = _("Time-out reached");
                                this.error_message_label.visible = true;
                                break;

                            case Gnome.ShellExtensionError.NOT_ALLOWED:
                                this.error_message_label.label = _("Installing extensions is not allowed");
                                this.error_message_label.visible = true;
                                break;

                            case Gnome.ShellExtensionError.DOWNLOAD_FAILED:
                                this.error_message_label.label = _("Failed to download the extension");
                                this.error_message_label.visible = true;
                                break;

                            default:
                                this.error_text_view.buffer.text = error.message;
                                this.error_message_label.visible = false;
                                break;
                        }

                        this.can_close = true;
                        this.stack.visible_child_name = "failure";
                    }
                });
        }

        [GtkCallback]
        private void on_cancel_clicked ()
        {
            if (!this.can_close) {
                return;
            }

            this.close ();
        }

        [GtkCallback]
        private void on_abort_clicked ()
        {
            if (!this.can_close) {
                return;
            }

            this.close ();
        }

        [GtkCallback]
        private void on_copy_to_clipboard_clicked (Gtk.Button button)
        {
            var display = Gdk.Display.get_default ();
            var error_message = this.error_text_view.buffer.text;

            if (display != null) {
                var clipboard = display.get_clipboard ();
                clipboard.set_text (error_message);
            }
        }

        public override void dispose ()
        {
            if (this.timeout_id != 0U) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0U;
            }

            this.shell_extension = null;

            base.dispose ();
        }
    }
}
