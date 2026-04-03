/*
 * Copyright (c) 2025-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    public interface BackgroundProvider : Ft.Provider
    {
        public abstract bool background_allowed { get; }
        public abstract bool autostart_allowed  { get; }

        public abstract async void request_background (bool   autostart,
                                                       string parent_window);
    }


    [SingleInstance]
    public class BackgroundManager : Ft.ProvidedObject<Ft.BackgroundProvider>
    {
        public bool active {
            get {
                return this.has_application_hold;
            }
        }

        public bool background_allowed {
            get {
                return this._background_allowed;
            }
        }

        public bool autostart_allowed {
            get {
                return this._autostart_allowed;
            }
        }

        private unowned GLib.Application?        application = null;
        private GLib.Settings?                   settings = null;
        private bool                             has_application_hold = false;
        private GLib.GenericSet<uint>            holds = null;
        private static uint                      next_hold_id = 1U;
        private bool                             _background_allowed = false;
        private bool                             _autostart_allowed = false;

        private async void request_background (string parent_window)
        {
            if (this.provider == null || !this.provider.enabled) {
                return;
            }

            this.application.hold ();

            yield this.provider.request_background (this.settings.get_boolean ("autostart"),
                                                    parent_window);

            this.update_application_hold ();
            this.application.release ();
        }

        private void hold_application ()
        {
            if (!this.has_application_hold) {
                this.application.hold ();
                this.has_application_hold = true;
            }
        }

        private void release_application ()
        {
            if (this.has_application_hold) {
                this.application.release ();
                this.has_application_hold = false;
            }
        }

        private void update_application_hold ()
        {
            var is_provider_enabled = this.provider != null && this.provider.enabled;

            if (this.holds.length > 0U && (this._background_allowed || !is_provider_enabled)) {
                this.hold_application ();
            }
            else {
                this.release_application ();
            }
        }

        public async uint hold (string parent_window = "")
        {
            var hold_id = Ft.BackgroundManager.next_hold_id;
            BackgroundManager.next_hold_id++;

            this.holds.add (hold_id);
            this.hold_application ();

            yield this.request_background (parent_window);

            return hold_id;
        }

        public uint hold_sync (string parent_window = "")
        {
            var hold_id = Ft.BackgroundManager.next_hold_id;
            BackgroundManager.next_hold_id++;

            this.holds.add (hold_id);
            this.hold_application ();

            this.request_background.begin (parent_window);

            return hold_id;
        }

        public void release (uint hold_id)
        {
            var removed = this.holds.remove (hold_id);

            if (removed) {
                this.update_application_hold ();
            }
        }

        private void update_properties ()
        {
            var provider = this.provider;
            var background_allowed = provider != null ? provider.background_allowed : false;
            var autostart_allowed = provider != null ? provider.autostart_allowed : false;

            if (this._background_allowed != background_allowed) {
                this._background_allowed = background_allowed;
                this.notify_property ("background-allowed");
            }

            if (this._autostart_allowed != autostart_allowed) {
                this._autostart_allowed = autostart_allowed;
                this.notify_property ("autostart-allowed");
            }
        }

        protected override void initialize ()
        {
            this.application = GLib.Application.get_default ();
            this.holds = new GLib.GenericSet<uint> (GLib.direct_hash, GLib.direct_equal);

            this.settings = Ft.get_settings ();
            this.settings.changed.connect (this.on_settings_changed);
        }

        protected override void setup_providers ()
        {
            // TODO: add a permissive provider if the Background portal is not available
        }

        protected override void provider_enabled (Ft.BackgroundProvider provider)
        {
            provider.notify["background-allowed"].connect (this.on_notify_background_allowed);
            provider.notify["autostart-allowed"].connect (this.on_notify_autostart_allowed);
            this.update_properties ();

            if (this.holds.length > 0U || this.settings.get_boolean ("autostart")) {
                this.request_background.begin ("");
            }
        }

        protected override void provider_disabled (Ft.BackgroundProvider provider)
        {
            // TODO: use SetStatus to withdraw request?

            provider.notify["background-allowed"].disconnect (this.on_notify_background_allowed);
            provider.notify["autostart-allowed"].disconnect (this.on_notify_autostart_allowed);
            this.update_properties ();

            this.release_application ();
        }

        private void on_notify_background_allowed (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            this.update_properties ();
        }

        private void on_notify_autostart_allowed (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            this.update_properties ();
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "autostart":
                    if (settings.get_boolean (key) != this._autostart_allowed) {
                        this.request_background.begin ("");
                    }

                    break;
            }
        }

        public void destroy ()
        {
            this.holds?.remove_all ();
            this.release_application ();
        }

        public override void dispose ()
        {
            this.destroy ();

            if (this.settings != null) {
                this.settings.changed.disconnect (this.on_settings_changed);
                this.settings = null;
            }

            this.application = null;
            this.holds = null;

            base.dispose ();
        }
    }
}
