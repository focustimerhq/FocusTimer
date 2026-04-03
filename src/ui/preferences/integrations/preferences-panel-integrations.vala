/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/integrations/preferences-panel-integrations.ui")]
    public class PreferencesPanelIntegrations : Ft.PreferencesPanel
    {
        [GtkChild]
        private unowned Adw.PreferencesPage page;
        [GtkChild]
        private unowned Adw.SwitchRow autostart_switchrow;
        [GtkChild]
        private unowned Gtk.Label autostart_label;

        private GLib.Settings? settings = null;

        construct
        {
            this.settings = Ft.get_settings ();
            this.settings.bind (
                    "autostart",
                    this.autostart_switchrow,
                    "active",
                    GLib.SettingsBindFlags.DEFAULT);

            var background_manager = new Ft.BackgroundManager ();
            background_manager.bind_property (
                    "autostart-allowed",
                    this.autostart_label,
                    "visible",
                    GLib.BindingFlags.SYNC_CREATE);
        }

        public override unowned Adw.PreferencesPage get_preferences_page ()
        {
            return this.page;
        }

        public override void dispose ()
        {
            this.settings = null;

            base.dispose ();
        }
    }
}
