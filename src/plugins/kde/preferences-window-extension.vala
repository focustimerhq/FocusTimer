/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Kde
{
    public class PreferencesWindowExtension : Ft.PreferencesWindowExtension
    {
        private GLib.Settings?                  settings = null;
        private Ft.PreferencesPanel?            last_panel = null;
        private unowned Adw.PreferencesGroup?   notification_group = null;
        private unowned Adw.PreferencesGroup?   desktop_group = null;

        construct
        {
            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.kde");

            this.notify["window"].connect (this.on_notify_window);
        }

        private void setup_notifications_panel (Ft.PreferencesPanel panel)
        {
            var page = panel.get_preferences_page ();

            if (this.notification_group == null)
            {
                // translators: abbreviate it to just "Settings" if it gets too long
                var notification_settings_button = new Gtk.Button.with_label (_("Open Settings"));
                notification_settings_button.valign = Gtk.Align.CENTER;
                notification_settings_button.margin_start = 12;
                notification_settings_button.clicked.connect (
                    () => {
                        try {
                            if (Ft.is_flatpak ()) {
                                GLib.AppInfo.launch_default_for_uri (
                                        "systemsettings://kcm_notifications",
                                        null);
                            }
                            else {
                                var app_info = GLib.AppInfo.create_from_commandline (
                                        @"kcmshell6 kcm_notifications --args --desktop-entry=$(Config.APPLICATION_ID)",
                                        null,
                                        GLib.AppInfoCreateFlags.NONE);
                                app_info.launch (null, null);
                            }
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error opening notification settings: %s", error.message);
                        }
                    });

                var notification_group = new Adw.PreferencesGroup ();
                notification_group.description = _("For reliable break reminders, allow this app's notifications during Do Not Disturb and disable its notification history");
                notification_group.header_suffix = notification_settings_button;
                page.add (notification_group);

                notification_group.insert_after (notification_group.parent, null);  // move to top

                this.notification_group = notification_group;
            }
        }

        private void taredown_notifications_panel (Ft.PreferencesPanel panel)
        {
            this.notification_group?.unparent ();
            this.notification_group = null;
        }

        private void setup_integrations_panel (Ft.PreferencesPanel panel)
        {
            if (this.settings == null) {
                this.taredown_integrations_panel (panel);
                return;
            }

            if (this.desktop_group == null)
            {
                var desktop_group = new Adw.PreferencesGroup ();
                desktop_group.title = _("Desktop");
                panel.add_group ("desktop", desktop_group);

                var manage_notifications_row = new Adw.SwitchRow ();
                manage_notifications_row.title = _("Do Not Disturb");
                manage_notifications_row.subtitle = _("Hide non-critical notifications while using the timer");
                desktop_group.add (manage_notifications_row);

                this.desktop_group = desktop_group;
                this.settings.bind ("manage-notifications",
                                    manage_notifications_row, "active",
                                    GLib.SettingsBindFlags.DEFAULT);
            }
        }

        private void taredown_integrations_panel (Ft.PreferencesPanel panel)
        {
            this.desktop_group?.unparent ();
            this.desktop_group = null;
        }

        /**
         * Modify visible_panel of the PreferencesWindow.
         */
        private void setup ()
        {
            var panel = this.window?.visible_panel;

            if (panel != this.last_panel)
            {
                this.taredown ();

                this.last_panel = panel;
            }

            switch (panel?.tag)
            {
                case "notifications":
                    this.setup_notifications_panel (panel);
                    break;

                case "integrations":
                    this.setup_integrations_panel (panel);
                    break;

                default:
                    break;
            }
        }

        private void taredown ()
        {
            switch (this.last_panel?.tag)
            {
                case "notifications":
                    this.taredown_notifications_panel (this.last_panel);
                    break;

                case "integrations":
                    this.taredown_integrations_panel (this.last_panel);
                    break;

                default:
                    break;
            }

            this.last_panel = null;
        }

        private void on_notify_window (GLib.Object    object,
                                       GLib.ParamSpec pspec)
        {
            if (this.window != null) {
                this.window.notify["visible-panel"].connect (this.on_notify_visible_panel);
            }
        }

        private void on_notify_visible_panel ()
        {
            this.setup ();
        }

        public override void dispose ()
        {
            this.taredown ();

            if (this.window != null) {
                this.window.notify["visible-panel"].disconnect (this.on_notify_visible_panel);
            }

            this.settings = null;

            base.dispose ();
        }
    }
}
