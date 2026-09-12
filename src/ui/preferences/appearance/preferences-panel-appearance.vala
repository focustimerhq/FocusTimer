/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/appearance/preferences-panel-appearance.ui")]
    public class PreferencesPanelAppearance : Ft.PreferencesPanel
    {
        [GtkChild]
        private unowned Adw.PreferencesPage page;
        [GtkChild]
        private unowned Adw.SwitchRow dark_theme_switchrow;
        [GtkChild]
        private unowned Adw.SwitchRow compact_mode_switchrow;

        private GLib.Settings? settings = null;

        construct
        {
            this.settings = Ft.get_settings ();
            this.settings.bind ("dark-theme",
                                this.dark_theme_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("prefer-compact-size",
                                this.compact_mode_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);
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
