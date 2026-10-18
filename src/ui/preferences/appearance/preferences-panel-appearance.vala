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
        [GtkChild]
        private unowned Adw.PreferencesGroup screen_overlay_group;
        [GtkChild]
        private unowned Adw.SwitchRow blur_effect_switchrow;

        private GLib.Settings?              settings = null;
        private Ft.ScreenOverlayManager?    screen_overlay_manager = null;

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
            this.settings.bind ("blur-effect",
                                this.blur_effect_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);

            this.screen_overlay_manager = new Ft.ScreenOverlayManager ();
            this.screen_overlay_manager.notify["provider"].connect (
                    this.on_screen_overlay_manager_notify_provider);

            this.update_screen_overlay_group ();
        }

        private void update_screen_overlay_group ()
        {
            if (this.screen_overlay_manager?.provider is Ft.DefaultScreenOverlayProvider) {
                this.screen_overlay_group.visible = true;

                // TODO: hide blur-effect if not supported
            }
            else {
                this.screen_overlay_group.visible = true;
            }

            // TODO: hide screen_overlay_group when none of the rows are visible
        }

        private void on_screen_overlay_manager_notify_provider (GLib.Object    object,
                                                                GLib.ParamSpec pspec)
        {
            this.update_screen_overlay_group ();
        }

        public override unowned Adw.PreferencesPage get_preferences_page ()
        {
            return this.page;
        }

        public override void dispose ()
        {
            this.settings = null;

            if (this.screen_overlay_manager != null) {
                this.screen_overlay_manager.notify["provider"].disconnect (
                        this.on_screen_overlay_manager_notify_provider);
                this.screen_overlay_manager = null;
            }

            base.dispose ();
        }
    }
}
