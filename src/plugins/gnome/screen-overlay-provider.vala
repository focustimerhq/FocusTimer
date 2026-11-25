/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Gnome
{
    /**
     * Provider for the screen overlay when the extension is enabled.
     *
     * Extension manages the overlay. Here we only need support for manually opening the overlay.
     */
    public class ScreenOverlayProvider : Ft.Provider, Ft.ScreenOverlayProvider
    {
        public bool active {
            get {
                return this.shell_extension != null &&
                       this.shell_extension.screen_overlay_active;
            }
        }

        public bool handles_lock_delay {
            get {
                return true;
            }
        }

        private bool                    _active = false;
        private Gnome.ShellExtension?   shell_extension = null;
        private Ft.SessionManager?      session_manager = null;
        private uint                    idle_inhibit_cookie = 0U;

        private void update_available ()
        {
            this.available = this.shell_extension != null &&
                             this.shell_extension.enabled;
        }

        private void update_active ()
        {
            var active = this.shell_extension != null &&
                         this.shell_extension.screen_overlay_active;

            if (this._active != active) {
                this._active = active;
                this.notify_property ("active");
            }
        }

        private void update_idle_inhibitor ()
        {
            var inhibit_idle = this.enabled &&
                               this._active &&
                               this.shell_extension != null &&
                               this.shell_extension.enabled &&
                               Gnome.is_version_at_least (this.shell_extension.version, "6") &&
                               this.session_manager != null &&
                               !this.session_manager.lockscreen_active;
            var is_idle_inhibited = this.idle_inhibit_cookie != 0U;

            if (inhibit_idle == is_idle_inhibited) {
                return;
            }

            var application = GLib.Application.get_default () as Gtk.Application;

            if (application == null) {
                return;
            }

            if (inhibit_idle) {
                // translators: reason for inhibiting the session from going idle
                this.idle_inhibit_cookie = application.inhibit (null,
                                                                Gtk.ApplicationInhibitFlags.IDLE,
                                                                _("Screen overlay is open"));
            }
            else if (this.idle_inhibit_cookie != 0U) {
                application.uninhibit (this.idle_inhibit_cookie);
                this.idle_inhibit_cookie = 0U;
            }
        }

        private void on_notify_extension_enabled (GLib.Object    object,
                                                  GLib.ParamSpec pspec)
        {
            this.update_available ();
            this.update_idle_inhibitor ();
        }

        private void on_notify_screen_overlay_active (GLib.Object    object,
                                                      GLib.ParamSpec pspec)
        {
            this.update_active ();
            this.update_idle_inhibitor ();
        }

        private void on_session_manager_notify_lockscreen_active (GLib.Object    object,
                                                                  GLib.ParamSpec pspec)
        {
            this.update_idle_inhibitor ();
        }

        public void open ()
        {
            var proxy = this.shell_extension?.get_shell_integration_proxy ();

            if (proxy != null) {
                proxy.open_screen_overlay.begin (
                    (obj, res) => {
                        try {
                            proxy.open_screen_overlay.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error opening screen overlay: %s", error.message);
                        }
                    });
            }
            else {
                GLib.debug ("Unable to open screen overlay. No ShellIntegration.");
            }
        }

        public void close ()
        {
        }

        protected override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.session_manager = Ft.SessionManager.get_default ();
            this.session_manager.notify["lockscreen-active"].connect (
                    this.on_session_manager_notify_lockscreen_active);

            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["enabled"].connect (this.on_notify_extension_enabled);
            this.shell_extension.notify["screen-overlay-active"].connect (this.on_notify_screen_overlay_active);

            yield this.shell_extension.wait ();

            this.update_available ();
            this.update_active ();
            this.update_idle_inhibitor ();
        }

        protected override async void uninitialize () throws GLib.Error
        {
            if (this.session_manager != null) {
                this.session_manager.notify["lockscreen-active"].disconnect (
                        this.on_session_manager_notify_lockscreen_active);
                this.session_manager = null;
            }

            if (this.shell_extension != null)
            {
                this.shell_extension.notify["enabled"].disconnect (this.on_notify_extension_enabled);
                this.shell_extension.notify["screen-overlay-active"].disconnect (this.on_notify_screen_overlay_active);
                this.shell_extension = null;

                this.update_available ();
                this.update_active ();
            }

            this.update_idle_inhibitor ();
        }

        protected override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
        }

        protected override async void disable () throws GLib.Error
        {
            this.close ();
            this.update_idle_inhibitor ();
        }
    }
}
