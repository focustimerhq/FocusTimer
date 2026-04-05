/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public class PreferencesWindowExtension : Ft.PreferencesWindowExtension
    {
        private Gnome.ShellExtension?           shell_extension = null;
        private Gnome.ShellExtensionSettings?   settings = null;
        private Ft.PreferencesPanel?            last_panel = null;
        private unowned Adw.PreferencesGroup?   indicator_group = null;
        private unowned Adw.PreferencesGroup?   screen_overlay_group = null;
        private unowned Adw.PreferencesGroup?   desktop_group = null;
        private unowned Gtk.Switch?             shell_extension_toggle = null;
        private unowned Adw.SwitchRow?          manage_notifications_row = null;
        private GLib.Binding?                   manage_notifications_binding = null;
        private bool                            installing_extension = false;

        construct
        {
            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["settings"].connect (this.on_notify_settings);
            this.shell_extension.notify["available"].connect (this.on_notify_available);

            this.notify["window"].connect (this.on_notify_window);

            this.update_settings ();
        }

        private Adw.Toggle create_toggle (string name,
                                          string label)
        {
            var toggle = new Adw.Toggle ();
            toggle.name = name;
            toggle.label = label;

            return toggle;
        }

        private void setup_appearance_panel (Ft.PreferencesPanel panel)
        {
            var page = panel.get_preferences_page ();

            if (this.settings == null) {
                this.taredown_appearance_panel (panel);
                return;
            }

            if (this.indicator_group == null)
            {
                var indicator_group = new Adw.PreferencesGroup ();
                indicator_group.title = _("Indicator");
                page.add (indicator_group);

                var indicator_type_toggle_group = new Adw.ToggleGroup ();
                indicator_type_toggle_group.homogeneous = true;
                indicator_type_toggle_group.can_shrink = false;
                indicator_type_toggle_group.valign = Gtk.Align.CENTER;
                indicator_type_toggle_group.add (this.create_toggle ("icon", _("Icon")));
                indicator_type_toggle_group.add (this.create_toggle ("text", _("Text")));
                this.settings.bind_property (
                               "indicator-type",
                               indicator_type_toggle_group, "active-name",
                               GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);

                var indicator_type_row = new Adw.ActionRow ();
                indicator_type_row.title = _("Display As");
                indicator_type_row.activatable = false;
                indicator_type_row.add_suffix (indicator_type_toggle_group);
                indicator_group.add (indicator_type_row);

                this.indicator_group = indicator_group;
            }

            if (this.screen_overlay_group == null)
            {
                var screen_overlay_group = new Adw.PreferencesGroup ();
                screen_overlay_group.title = _("Screen Overlay");
                page.add (screen_overlay_group);

                var blur_effect_row = new Adw.SwitchRow ();
                blur_effect_row.title = _("Blur Effect");
                this.settings.bind_property (
                               "blur-effect",
                               blur_effect_row, "active",
                               GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
                screen_overlay_group.add (blur_effect_row);

                var dismiss_gesture_row = new Adw.SwitchRow ();
                dismiss_gesture_row.title = _("Dismiss Gesture");
                this.settings.bind_property (
                               "dismiss-gesture",
                               dismiss_gesture_row, "active",
                               GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
                screen_overlay_group.add (dismiss_gesture_row);

                this.screen_overlay_group = screen_overlay_group;
            }
        }

        private void taredown_appearance_panel (Ft.PreferencesPanel panel)
        {
            this.indicator_group?.unparent ();
            this.indicator_group = null;

            this.screen_overlay_group?.unparent ();
            this.screen_overlay_group = null;
        }

        private void setup_integrations_panel (Ft.PreferencesPanel panel)
        {
            var page = panel.get_preferences_page ();

            if (this.shell_extension == null || !this.shell_extension.available) {
                this.taredown_integrations_panel (panel);
                return;
            }

            if (this.desktop_group == null)
            {
                var desktop_group = new Adw.PreferencesGroup ();
                desktop_group.title = _("Desktop");
                page.add (desktop_group);

                var install_button = new Gtk.Button.with_label (_("Install"));
                install_button.add_css_class ("suggested-action");
                install_button.clicked.connect (() => this.install_extension ());

                /* translators: verb */
                var update_button = new Gtk.Button.with_label (_("Update"));
                update_button.add_css_class ("suggested-action");
                update_button.clicked.connect (
                        () => this.install_extension (_("Log out to finish the update")));  // XXX: not tested

                var toggle = new Gtk.Switch ();
                toggle.valign = Gtk.Align.CENTER;
                toggle.notify["active"].connect (
                    (object, pspec) => {
                        if (toggle.active == this.shell_extension.enabled) {
                            return;
                        }

                        if (toggle.active) {
                            this.shell_extension.enable_extension.begin ();
                        }
                        else {
                            this.shell_extension.disable_extension.begin ();
                        }
                    });

                var outdated_button = new Gtk.Button.with_label (_("Outdated"));
                outdated_button.sensitive = false;

                var state_stack = new Gtk.Stack ();
                state_stack.hhomogeneous = false;
                state_stack.vhomogeneous = true;
                state_stack.valign = Gtk.Align.CENTER;
                state_stack.add_named (install_button, "uninstalled");
                state_stack.add_named (toggle, "installed");
                state_stack.add_named (outdated_button, "outdated");
                state_stack.add_named (update_button, "update");

                var extension_row = new Adw.ActionRow ();
                extension_row.title = _("GNOME Shell Extension");
                extension_row.add_suffix (state_stack);
                extension_row.set_activatable_widget (toggle);
                desktop_group.add (extension_row);

                var manage_notifications_row = new Adw.SwitchRow ();
                manage_notifications_row.title = _("Manage Notifications");
                manage_notifications_row.subtitle = _("Toggle Do Not Disturb mode during Pomodoro.");
                desktop_group.add (manage_notifications_row);

                state_stack.bind_property (
                        "visible-child-name",
                        extension_row, "activatable",
                        GLib.BindingFlags.SYNC_CREATE,
                        this.transform_visible_child_name_to_activatable);

                this.shell_extension.bind_property (
                        "enabled",
                        toggle, "active",
                        GLib.BindingFlags.SYNC_CREATE);

                this.shell_extension.bind_property (
                        "state",
                        state_stack, "visible-child-name",
                        GLib.BindingFlags.SYNC_CREATE,
                        this.transform_state_to_visible_child_name);

                this.shell_extension.bind_property (
                        "state",
                        desktop_group, "visible",
                        GLib.BindingFlags.SYNC_CREATE,
                        this.transform_state_to_can_install);

                this.shell_extension.bind_property (
                        "state",
                        manage_notifications_row, "visible",
                        GLib.BindingFlags.SYNC_CREATE,
                        this.transform_state_to_is_installed);

                // TODO: display indicators about extension error or update

                this.desktop_group = desktop_group;
                this.shell_extension_toggle = toggle;
                this.manage_notifications_row = manage_notifications_row;
            }

            if (this.shell_extension_toggle != null) {
                this.shell_extension_toggle.state = this.settings != null;
            }

            if (this.manage_notifications_row != null) {
                this.manage_notifications_row.sensitive = this.settings != null;
            }

            if (this.manage_notifications_row != null && this.settings != null) {
                this.manage_notifications_binding?.unbind ();
                this.manage_notifications_binding = this.settings.bind_property (
                        "manage-notifications",
                        this.manage_notifications_row, "active",
                        GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
            }
        }

        private void taredown_integrations_panel (Ft.PreferencesPanel panel)
        {
            this.shell_extension_toggle = null;
            this.manage_notifications_row = null;

            this.manage_notifications_binding?.unbind ();
            this.manage_notifications_binding = null;

            this.desktop_group?.unparent ();
            this.desktop_group = null;
        }

        private bool transform_state_to_can_install (GLib.Binding   binding,
                                                     GLib.Value     source_value,
                                                     ref GLib.Value target_value)
        {
            target_value.set_boolean (this.shell_extension.is_installed () ||
                                      Gnome.ShellExtension.IS_PUBLISHED);

            return true;
        }

        private bool transform_state_to_is_installed (GLib.Binding   binding,
                                                      GLib.Value     source_value,
                                                      ref GLib.Value target_value)
        {
            target_value.set_boolean (this.shell_extension.is_installed ());

            return true;
        }

        private bool transform_state_to_visible_child_name (GLib.Binding   binding,
                                                            GLib.Value     source_value,
                                                            ref GLib.Value target_value)
        {
            var state = (Gnome.ExtensionState) source_value.get_enum ();

            switch (state)
            {
                case Gnome.ExtensionState.UNINSTALLED:
                case Gnome.ExtensionState.DOWNLOADING:
                    target_value.set_string ("uninstalled");
                    break;

                case Gnome.ExtensionState.ENABLED:
                case Gnome.ExtensionState.INACTIVE:
                case Gnome.ExtensionState.DEACTIVATING:
                case Gnome.ExtensionState.ACTIVATING:
                case Gnome.ExtensionState.INITIALIZED:
                case Gnome.ExtensionState.ERROR:
                    target_value.set_string ("installed");
                    break;

                case Gnome.ExtensionState.OUT_OF_DATE:
                    // TODO: Not sure how `has_update` works. Does it return `true` when update is
                    //       available or has been already downloaded?
                    // if (this.shell_extension.has_update () && Gnome.ShellExtension.IS_PUBLISHED) {
                    //     target_value.set_string ("update");
                    // }
                    // else {
                    target_value.set_string ("outdated");
                    // }
                    break;

                default:
                    return false;
            }

            return true;
        }

        private bool transform_visible_child_name_to_activatable (GLib.Binding   binding,
                                                                  GLib.Value     source_value,
                                                                  ref GLib.Value target_value)
        {
            target_value.set_boolean (source_value.get_string () == "installed");

            return true;
        }

        /**
         * Modify visible_panel of the PreferencesWindow.
         *
         * We allow to rerun setup functions as `settings` may vanish and reappear.
         */
        private void setup ()
        {
            var panel = this.window?.visible_panel;

            if (panel != this.last_panel)
            {
                switch (this.last_panel?.tag)
                {
                    case "appearance":
                        this.taredown_appearance_panel (this.last_panel);
                        break;

                    case "integrations":
                        this.taredown_integrations_panel (this.last_panel);
                        break;
                }

                this.last_panel = panel;
            }

            switch (panel?.tag)
            {
                case "appearance":
                    this.setup_appearance_panel (panel);
                    break;

                case "integrations":
                    this.setup_integrations_panel (panel);
                    break;

                default:
                    this.taredown ();
                    break;
            }
        }

        private void taredown ()
        {
            if (this.last_panel == null) {
                return;
            }

            this.taredown_appearance_panel (this.last_panel);
            this.taredown_integrations_panel (this.last_panel);
            this.last_panel = null;
        }

        private void install_extension (string success_message = "")
        {
            var shell_extension = this.shell_extension;

            if (this.installing_extension) {
                return;
            }

            this.installing_extension = true;

            shell_extension.install_extension.begin (
                (obj, res) => {
                    string message = "";

                    try {
                        var success = shell_extension.install_extension.end (res);

                        if (success) {
                            message = success_message;
                        }
                    }
                    catch (Gnome.ShellExtensionError error)
                    {
                        switch (error.code)
                        {
                            case Gnome.ShellExtensionError.TIMED_OUT:
                                message = _("Time-out reached");
                                break;

                            case Gnome.ShellExtensionError.NOT_ALLOWED:
                                message = _("Installing extensions is not allowed");
                                break;

                            case Gnome.ShellExtensionError.DOWNLOAD_FAILED:
                                message = _("Failed to download the extension");
                                break;

                            default:
                                message = _("Something went wrong");
                                return;
                        }
                    }

                    if (message != "") {
                        this.window?.add_toast (new Adw.Toast (message));
                    }

                    this.installing_extension = false;
                });
        }

        private void update_settings ()
        {
            var settings = this.shell_extension?.settings;

            if (this.settings != settings) {
                this.settings = settings;
                this.setup ();
            }
        }

        private void on_notify_window (GLib.Object    object,
                                       GLib.ParamSpec pspec)
        {
            if (this.window != null) {
                this.window.notify["visible-panel"].connect (this.on_notify_visible_panel);
            }
        }

        private void on_notify_settings (GLib.Object    object,
                                         GLib.ParamSpec pspec)
        {
            this.update_settings ();
        }

        private void on_notify_available (GLib.Object    object,
                                          GLib.ParamSpec pspec)
        {
            this.setup ();
        }

        private void on_notify_visible_panel ()
        {
            this.setup ();
        }

        public override void dispose ()
        {
            this.taredown ();

            if (this.shell_extension != null) {
                this.shell_extension.notify["settings"].disconnect (this.on_notify_settings);
                this.shell_extension.notify["available"].disconnect (this.on_notify_available);
                this.shell_extension = null;
            }

            this.settings = null;

            base.dispose ();
        }
    }
}
