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

        private void on_notify_extension_enabled (GLib.Object    object,
                                                  GLib.ParamSpec pspec)
        {
            this.update_available ();
        }

        private void on_notify_screen_overlay_active (GLib.Object    object,
                                                      GLib.ParamSpec pspec)
        {
            this.update_active ();
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
            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["enabled"].connect (this.on_notify_extension_enabled);
            this.shell_extension.notify["screen-overlay-active"].connect (this.on_notify_screen_overlay_active);

            yield this.shell_extension.wait ();

            this.update_available ();
            this.update_active ();
        }

        protected override async void uninitialize () throws GLib.Error
        {
            if (this.shell_extension != null)
            {
                this.shell_extension.notify["enabled"].disconnect (this.on_notify_extension_enabled);
                this.shell_extension.notify["screen-overlay-active"].disconnect (this.on_notify_screen_overlay_active);
                this.shell_extension = null;

                this.update_available ();
                this.update_active ();
            }
        }

        protected override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
        }

        protected override async void disable () throws GLib.Error
        {
            this.close ();
        }
    }
}
