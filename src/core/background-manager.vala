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

        public abstract async bool request_background (bool              autostart,
                                                       string            parent_window,
                                                       GLib.Cancellable? cancellable);
    }


    /**
     * A fallback implementation for missing Background portal.
     *
     * `BackgroundManager` already handles the application hold. Only thing to do
     * is managing the autostart file.
     */
    private class DefaultBackgroundProvider : Ft.Provider, Ft.BackgroundProvider
    {
        private const string AUTOSTART_TEMPLATE = """[Desktop Entry]
Type=Application
Name=${APPLICATION_ID}
X-XDP-Autostart=${APPLICATION_ID}
Exec=focus-timer --gapplication-service
""";

        public bool background_allowed {
            get {
                return this.available;
            }
        }

        public bool autostart_allowed  {
            get {
                return this._autostart_allowed;
            }
        }

        private bool _autostart_allowed = false;

        private GLib.File get_autostart_file ()
        {
            var path = GLib.Path.build_filename (
                    GLib.Environment.get_user_config_dir (),
                    "autostart",
                    @"$(Config.APPLICATION_ID).desktop");

            return GLib.File.new_for_path (path);
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.available = !Ft.is_flatpak ();
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            var autostart_file = this.get_autostart_file ();
            var autostart_allowed = false;

            try {
                yield autostart_file.query_info_async (
                        GLib.FileAttribute.STANDARD_TYPE,
                        GLib.FileQueryInfoFlags.NONE,
                        GLib.Priority.DEFAULT,
                        cancellable);
                autostart_allowed = true;
            }
            catch (GLib.IOError.NOT_FOUND error) {
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to query autostart file: %s", error.message);
            }

            this._autostart_allowed = autostart_allowed;
            this.notify_property ("autostart-allowed");
        }

        public override async void disable () throws GLib.Error
        {
        }

        public override async void uninitialize () throws GLib.Error
        {
        }

        public async bool request_background (bool              autostart,
                                              string            parent_window,
                                              GLib.Cancellable? cancellable)
        {
            var autostart_file = this.get_autostart_file ();
            var autostart_contents = AUTOSTART_TEMPLATE.replace (
                    "${APPLICATION_ID}",
                    Config.APPLICATION_ID);

            try {
                if (autostart) {
                    yield autostart_file.replace_contents_async (
                            autostart_contents.data,
                            null,
                            false,
                            GLib.FileCreateFlags.NONE,
                            null,
                            null);
                }
                else {
                    yield autostart_file.delete_async ();
                }
            }
            catch (GLib.IOError.NOT_FOUND error) {
                // already removed
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to update autostart file: %s", error.message);
                return true;
            }

            if (this._autostart_allowed != autostart) {
                this._autostart_allowed = autostart;
                this.notify_property ("autostart-allowed");
            }

            return true;
        }
    }


    /**
     * Wrapper around `Application.hold()` and `.release()` methods.
     *
     * Acquiring a hold indicates that the app can run in background. We may still not have the
     * permission to do so, and the sandbox will close it when there are no windows.
     */
    [SingleInstance]
    public class BackgroundManager : Ft.ProvidedObject<Ft.BackgroundProvider>
    {
        public bool active {
            get {
                return this._active;
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

        private bool                        _active = false;
        private bool                        _background_allowed = false;
        private bool                        _autostart_allowed = false;
        private unowned GLib.Application?   application = null;
        private GLib.Settings?              settings = null;
        private GLib.GenericSet<uint>       holds = null;
        private static uint                 next_hold_id = 1U;

        public BackgroundManager.with_provider (Ft.BackgroundProvider provider)
        {
            this.providers.add (provider, Ft.Priority.HIGH);
        }

        private void hold_application ()
        {
            if (!this._active) {
                this.application.hold ();
                this._active = true;
                this.notify_property ("active");
            }
        }

        private void release_application ()
        {
            if (this._active) {
                this.application.release ();
                this._active = false;
                this.notify_property ("active");
            }
        }

        private void update_application_hold ()
        {
            if (this.holds.length > 0U) {
                this.hold_application ();
            }
            else {
                this.release_application ();
            }
        }

        /**
         * Increment application hold count.
         */
        public uint hold ()
        {
            var hold_id = Ft.BackgroundManager.next_hold_id;
            Ft.BackgroundManager.next_hold_id++;

            this.holds.add (hold_id);
            this.hold_application ();

            if (!this._background_allowed) {
                this.request_background.begin ();
            }

            return hold_id;
        }

        public void release (uint hold_id)
        {
            var removed = this.holds.remove (hold_id);

            if (removed) {
                this.update_application_hold ();
            }
        }

        /**
         * Request to run in background without incrementing application hold count.
         * Secondary use is to check latest permissions.
         */
        public async bool request_background (string parent_window = "",
                                              int    timeout = 60000)
        {
            if (this.provider == null || !this.provider.enabled) {
                return false;
            }

            this.application.hold ();

            var autostart = this.settings.get_boolean ("autostart");
            var cancellable = new GLib.Cancellable ();
            var timeout_id = 0U;

            if (timeout > 1000)
            {
                timeout_id = GLib.Timeout.add_seconds (timeout / 1000, () => {
                    timeout_id = 0U;
                    cancellable.cancel ();

                    return GLib.Source.REMOVE;
                });
            }
            else if (timeout > 0)
            {
                timeout_id = GLib.Timeout.add (timeout, () => {
                    timeout_id = 0U;
                    cancellable.cancel ();

                    return GLib.Source.REMOVE;
                });
            }

            var success = yield this.provider.request_background (
                    autostart, parent_window, cancellable);

            if (timeout_id != 0U) {
                GLib.Source.remove (timeout_id);
            }

            this.application.release ();

            return success;
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
            this.providers.add (new Ft.DefaultBackgroundProvider ());
        }

        protected override void provider_enabled (Ft.BackgroundProvider provider)
        {
            provider.notify["background-allowed"].connect (this.on_notify_background_allowed);
            provider.notify["autostart-allowed"].connect (this.on_notify_autostart_allowed);
            this.update_properties ();

            this.request_background.begin ();
        }

        protected override void provider_disabled (Ft.BackgroundProvider provider)
        {
            provider.notify["background-allowed"].disconnect (this.on_notify_background_allowed);
            provider.notify["autostart-allowed"].disconnect (this.on_notify_autostart_allowed);
            this.update_properties ();
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
                        this.request_background.begin ();
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
