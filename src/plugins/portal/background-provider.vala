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
        private const uint REQUEST_TIMEOUT_SECONDS = 60U;

        public Ft.Priority priority {
            get {
                return Ft.Priority.HIGH;
            }
        }

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
            this.available = has_dbus_interface (connection,
                                                 name,
                                                 "/org/freedesktop/portal/desktop",
                                                 "org.freedesktop.portal.Background");
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
                GLib.warning ("Error while enabling background provider: %s", error.message);
                throw error;
            }
        }

        public override async void disable () throws GLib.Error
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
            }

            this.update_permissions (false, false);

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

        private void update_permissions (bool background_allowed,
                                          bool autostart_allowed)
        {
            if (this._background_allowed != background_allowed) {
                this._background_allowed = background_allowed;
                this.notify_property ("background-allowed");
            }
            if (this._autostart_allowed != autostart_allowed) {
                this._autostart_allowed = autostart_allowed;
                this.notify_property ("autostart-allowed");
            }
        }

        public async void request_background (bool   autostart,
                                              string parent_window)
        {
            string handle_token;
            var proxy = this.proxy;
            var cancellable = this.cancellable;

            if (proxy == null || cancellable == null || cancellable.is_cancelled ()) {
                this.update_permissions (false, false);
                return;
            }

            var completed = false;
            var waiting = false;
            uint response_code = 2U;
            GLib.Variant? response_results = null;
            GLib.SourceFunc complete = () => {
                if (!completed) {
                    completed = true;
                    if (waiting) {
                        this.request_background.callback ();
                    }
                }
                return GLib.Source.REMOVE;
            };

            try {
                handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        if (!completed) {
                            response_code = response;
                            response_results = results;
                            complete ();
                        }
                    });
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while requesting background: %s", error.message);
                this.update_permissions (false, false);
                completed = true;
                complete = null;
                return;
            }

            if (cancellable.is_cancelled ()) {
                Portal.destroy_request (handle_token, true);
                this.update_permissions (false, false);
                completed = true;
                complete = null;
                return;
            }

            // Cancellation and method errors do not emit Request::Response.
            // Resume the caller on every completion path, including a lost portal.
            var cancelled_id = cancellable.cancelled.connect (() => {
                GLib.Idle.add (() => {
                    if (!completed) {
                        complete ();
                    }
                    return GLib.Source.REMOVE;
                });
            });
            uint timeout_id = 0U;
            timeout_id = GLib.Timeout.add_seconds (REQUEST_TIMEOUT_SECONDS, () => {
                timeout_id = 0U;
                GLib.warning ("Timed out while requesting background access");
                return complete ();
            });

            var options = new GLib.VariantDict ();
            options.insert_value ("handle_token", new GLib.Variant.string (handle_token));
            options.insert_value ("autostart", new GLib.Variant.boolean (autostart));
            options.insert_value ("commandline", new GLib.Variant.strv (COMMANDLINE));

            proxy.request_background.begin (
                parent_window,
                options.end (),
                (obj, res) => {
                    try {
                        proxy.request_background.end (res);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while requesting background: %s", error.message);
                        if (!completed) {
                            complete ();
                        }
                    }
                });

            if (!completed) {
                waiting = true;
                yield;  // wait for response, error, cancellation or timeout
                waiting = false;
            }

            if (timeout_id != 0U) {
                GLib.Source.remove (timeout_id);
            }
            GLib.SignalHandler.disconnect (cancellable, cancelled_id);
            Portal.destroy_request (handle_token, response_results == null);
            // The completion closure captures this request's state. Break its
            // reference cycle once late callbacks can no longer resume it.
            complete = null;

            var background_variant = response_results?.lookup_value ("background", GLib.VariantType.BOOLEAN);
            var autostart_variant = response_results?.lookup_value ("autostart", GLib.VariantType.BOOLEAN);
            var background_allowed = response_code == 0U && !cancellable.is_cancelled () &&
                                     background_variant != null && background_variant.get_boolean ();
            var autostart_allowed = response_code == 0U && !cancellable.is_cancelled () &&
                                    autostart_variant != null && autostart_variant.get_boolean ();

            this.update_permissions (background_allowed, autostart_allowed);
        }
    }
}
