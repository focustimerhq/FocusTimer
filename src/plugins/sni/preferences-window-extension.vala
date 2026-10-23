/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    /**
     * Offer to disable the indicator as it may be buggy or less useful with some hosts.
     * Other indicator implementations can't be disabled, so the toggle is specific to
     * SNI plugin.
     */
    public class PreferencesWindowExtension : Ft.PreferencesWindowExtension
    {
        private GLib.Settings?                  settings = null;
        private Ft.Indicator?                   indicator = null;
        private Ft.PreferencesPanel?            last_panel = null;
        private unowned Adw.PreferencesGroup?   indicator_group = null;

        construct
        {
            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.sni");

            this.indicator = new Ft.Indicator ();
            this.indicator.notify["provider"].connect (this.on_notify_provider);

            this.notify["window"].connect (this.on_notify_window);
        }

        private void setup_appearance_panel (Ft.PreferencesPanel panel)
        {
            if (this.settings == null) {
                this.taredown_appearance_panel (panel);
                return;
            }

            if (this.indicator_group == null)
            {
                var indicator_group = new Adw.PreferencesGroup ();
                indicator_group.title = _("System Tray");
                panel.add_group ("system-tray", indicator_group);

                var indicator_row = new Adw.SwitchRow ();
                indicator_row.title = _("Show Tray Icon");
                indicator_row.subtitle = _("Closing the window keeps the app running in the background.");
                indicator_group.add (indicator_row);
                this.settings.bind ("indicator",
                                    indicator_row, "active",
                                    GLib.SettingsBindFlags.DEFAULT);

                this.indicator_group = indicator_group;
            }
        }

        private void taredown_appearance_panel (Ft.PreferencesPanel panel)
        {
            this.indicator_group?.unparent ();
            this.indicator_group = null;
        }

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
                }

                this.last_panel = panel;
            }

            switch (panel?.tag)
            {
                case "appearance":
                    this.setup_appearance_panel (panel);
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
            this.last_panel = null;
        }

        private void update ()
        {
            if (this.indicator?.provider is Sni.IndicatorProvider) {
                this.setup ();
            }
            else {
                this.taredown ();
            }
        }

        private void on_notify_provider (GLib.Object    object,
                                         GLib.ParamSpec pspec)
        {
            this.update ();
        }

        private void on_notify_visible_panel (GLib.Object    object,
                                              GLib.ParamSpec pspec)
        {
            this.update ();
        }

        private void on_notify_window (GLib.Object    object,
                                       GLib.ParamSpec pspec)
        {
            if (this.window != null) {
                this.window.notify["visible-panel"].connect (this.on_notify_visible_panel);
            }
        }

        public override void dispose ()
        {
            this.taredown ();

            if (this.window != null) {
                this.window.notify["visible-panel"].disconnect (this.on_notify_visible_panel);
            }

            if (this.indicator != null) {
                this.indicator.notify["provider"].disconnect (this.on_notify_provider);
                this.indicator = null;
            }

            this.settings = null;

            base.dispose ();
        }
    }
}
