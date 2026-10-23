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
        private const string[] GROUP_ORDER = {
            "main-window",
            "indicator",
            "system-tray",
            "screen-overlay",
        };

        [GtkChild]
        private unowned Adw.PreferencesPage page;
        [GtkChild]
        private unowned Adw.PreferencesGroup main_window_group;
        [GtkChild]
        private unowned Adw.ComboRow color_scheme_comborow;
        [GtkChild]
        private unowned Adw.SwitchRow compact_mode_switchrow;
        [GtkChild]
        private unowned Adw.PreferencesGroup screen_overlay_group;
        [GtkChild]
        private unowned Adw.SwitchRow blur_effect_switchrow;
        [GtkChild]
        private unowned Adw.SwitchRow dismiss_gesture_switchrow;

        private GLib.Settings?              settings = null;
        private Ft.ScreenOverlayManager?    screen_overlay_manager = null;

        construct
        {
            this.settings = Ft.get_settings ();
            this.settings.bind_with_mapping (
                                "color-scheme",
                                this.color_scheme_comborow,
                                "selected",
                                GLib.SettingsBindFlags.DEFAULT,
                                color_scheme_get_mapping,
                                color_scheme_set_mapping,
                                null,
                                null);
            this.settings.bind ("prefer-compact-size",
                                this.compact_mode_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("blur-effect",
                                this.blur_effect_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("dismiss-gesture",
                                this.dismiss_gesture_switchrow,
                                "active",
                                GLib.SettingsBindFlags.DEFAULT);

            this.screen_overlay_manager = new Ft.ScreenOverlayManager ();
            this.screen_overlay_manager.notify["provider"].connect (
                    this.on_screen_overlay_manager_notify_provider);

            this.main_window_group.set_data<string> ("name", "main-window");
            this.screen_overlay_group.set_data<string> ("name", "screen-overlay");

            this.update_screen_overlay_group ();
        }

        private static bool color_scheme_get_mapping (GLib.Value   value,
                                                      GLib.Variant variant,
                                                      void*        user_data)
        {
            var color_scheme = Ft.ColorScheme.from_string (variant.get_string ());

            value.set_uint ((uint) color_scheme);

            return true;
        }

        private static GLib.Variant color_scheme_set_mapping (GLib.Value       value,
                                                              GLib.VariantType expected_type,
                                                              void*            user_data)
        {
            var color_scheme = (Ft.ColorScheme) value.get_uint ();

            return new GLib.Variant.string (color_scheme.to_string ());
        }

        private void update_screen_overlay_group ()
        {
            if (this.screen_overlay_manager?.provider is Ft.DefaultScreenOverlayProvider) {
                this.screen_overlay_group.visible = true;
                this.blur_effect_switchrow.visible = Ft.have_blur_effect ();
            }
            else {
                this.screen_overlay_group.visible = false;
            }
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

        protected override unowned string[]? get_group_order ()
        {
            return GROUP_ORDER;
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
