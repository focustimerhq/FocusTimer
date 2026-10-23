/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Mpris
{
    public class PreferencesWindowExtension : Ft.PreferencesWindowExtension
    {
        private GLib.Settings?                  settings = null;
        private Ft.PreferencesPanel?            last_panel = null;
        private unowned Adw.PreferencesGroup?   media_playback_group = null;

        construct
        {
            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.mpris");

            this.notify["window"].connect (this.on_notify_window);
        }

        private void setup_integrations_panel (Ft.PreferencesPanel panel)
        {
            if (this.settings == null) {
                this.taredown_integrations_panel (panel);
                return;
            }

            if (this.media_playback_group == null)
            {
                var media_playback_group = new Adw.PreferencesGroup ();
                media_playback_group.title = _("Media Playback");
                panel.add_group ("media-playback", media_playback_group);

                var manage_notifications_row = new Adw.SwitchRow ();
                manage_notifications_row.title = _("Auto-Pause Media");
                manage_notifications_row.subtitle = _("Pauses during breaks, resumes at the next Pomodoro");
                media_playback_group.add (manage_notifications_row);

                this.media_playback_group = media_playback_group;
                this.settings.bind ("control-media-playback",
                                    manage_notifications_row, "active",
                                    GLib.SettingsBindFlags.DEFAULT);
            }
        }

        private void taredown_integrations_panel (Ft.PreferencesPanel panel)
        {
            this.media_playback_group?.unparent ();
            this.media_playback_group = null;
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
