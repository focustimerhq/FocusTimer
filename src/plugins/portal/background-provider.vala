/*
 * Copyright (c) 2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Portal
{
    public class BackgroundProvider : Ft.Provider, Ft.BackgroundProvider
    {
        /**
         * Warn if underlying `Background` API version changes. Bump this value after testing.
         */
        private const uint COMAPTIBLE_VERSION = 2U;

        private const string[] COMMANDLINE = {"focus-timer", "--gapplication-service"};

        public new bool background_allowed {
            get {
                return this._background_allowed;
            }
        }

        public new bool autostart_allowed  {
            get {
                return this._autostart_allowed;
            }
        }

        private GLib.DBusConnection?                 connection = null;
        private Portal.Background?                   proxy = null;
        private GLib.Cancellable?                    cancellable = null;
        private GLib.HashTable<uint, Portal.Request> requests = null;
        private uint                                 dbus_watcher_id = 0U;
        private bool                                 _background_allowed = false;
        private bool                                 _autostart_allowed = false;

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
        {
            this.available = true;
            this.connection = connection;
        }

        private void on_name_vanished (GLib.DBusConnection? connection,
                                       string               name)
        {
            this.available = false;
            this.connection = null;
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.requests = new GLib.HashTable<uint, Portal.Request> (GLib.direct_hash,
                                                                      GLib.direct_equal);

            if (this.dbus_watcher_id == 0) {
                this.dbus_watcher_id = GLib.Bus.watch_name (GLib.BusType.SESSION,
                                                            "org.freedesktop.portal.Desktop",
                                                            GLib.BusNameWatcherFlags.NONE,
                                                            this.on_name_appeared,
                                                            this.on_name_vanished);
            }
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            if (this.proxy != null) {
                return;
            }

            this.cancellable = cancellable != null
                    ? cancellable
                    : new GLib.Cancellable ();

            try {
                this.proxy = yield GLib.Bus.get_proxy<Portal.Background>
                                    (GLib.BusType.SESSION,
                                     "org.freedesktop.portal.Desktop",
                                     "/org/freedesktop/portal/desktop",
                                     GLib.DBusProxyFlags.NONE,
                                     this.cancellable);

                if (this.proxy.version > COMAPTIBLE_VERSION) {
                    GLib.warning ("Using Background API version %u. Implementation was aimed for older version.",
                                  this.proxy.version);
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while creating global shortcuts session: %s", error.message);
                throw error;
            }
        }

        public override async void disable () throws GLib.Error
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
            }

            // XXX: the request does not get withdrawn
            // if (this._autostart_allowed) {
            //     this._autostart_allowed = false;
            //     this.notify_property ("autostart-allowed");
            // }
            //
            // if (this._background_allowed) {
            //     this._background_allowed = false;
            //     this.notify_property ("background-allowed");
            // }

            this.proxy = null;
            this.requests = null;
        }

        public override async void uninitialize () throws GLib.Error
        {
            if (this.dbus_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.dbus_watcher_id);
                this.dbus_watcher_id = 0;
            }

            this.cancellable = null;
        }

        public async void request_background (bool   autostart,
                                              string parent_window)
        {
            string handle_token;

            try {
                handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        if (results != null)
                        {
                            var background_variant = results.lookup ("background");
                            var autostart_variant = results.lookup ("autostart");
                            var background_allowed = background_variant != null
                                    ? background_variant.get_boolean ()
                                    : this._background_allowed;
                            var autostart_allowed = autostart_variant != null
                                    ? autostart_variant.get_boolean ()
                                    : this._autostart_allowed;

                            if (autostart_allowed != autostart) {
                                GLib.warning ("Failed to set `autostart = %s`",
                                              autostart.to_string ());
                            }

                            if (this._background_allowed != background_allowed) {
                                this._background_allowed = background_allowed;
                                this.notify_property ("background-allowed");
                            }

                            if (this._autostart_allowed != autostart_allowed) {
                                this._autostart_allowed = autostart_allowed;
                                this.notify_property ("autostart-allowed");
                            }
                        }

                        this.request_background.callback ();
                    });
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while requesting background: %s", error.message);
                return;
            }

            var options = new GLib.HashTable<string, GLib.Variant> (GLib.str_hash, GLib.str_equal);
            options.insert ("handle_token", new GLib.Variant.string (handle_token));
            options.insert ("autostart", new GLib.Variant.boolean (autostart));
            options.insert ("commandline", new GLib.Variant.strv (COMMANDLINE));

            this.proxy.request_background.begin (
                parent_window,
                options,
                (obj, res) => {
                    try {
                        this.proxy.request_background.end (res);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while requesting background: %s", error.message);
                    }
                });

            yield;  // wait for response
        }
    }
}
