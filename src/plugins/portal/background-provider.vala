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

        /**
         * A request that failed or got cancelled may never emit `Request::Response`.
         * Do not keep the caller waiting for a response that will not come.
         */
        public uint response_timeout { get; set; default = 60U; }

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
            var proxy = this.proxy;
            var cancellable = this.cancellable;

            if (proxy == null || (cancellable != null && cancellable.is_cancelled ())) {
                return;
            }

            string? handle_token = null;
            ulong cancelled_id = 0;
            uint timeout_id = 0U;
            var completed = false;
            var waiting = false;
            var received_response = false;
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
                        // A response is authoritative; cancellation and transport errors
                        // do not revoke permissions already granted by the portal.
                        received_response = true;
                        if (response == 0U) {
                            var background = results.lookup_value ("background", GLib.VariantType.BOOLEAN);
                            var autostart_result = results.lookup_value ("autostart", GLib.VariantType.BOOLEAN);
                            this.update_permissions (
                                background != null ? background.get_boolean () : this._background_allowed,
                                autostart_result != null ? autostart_result.get_boolean () : this._autostart_allowed);
                        }
                        if (!completed) {
                            complete ();
                        }
                    });

                if (cancellable != null) {
                    cancelled_id = cancellable.cancelled.connect (() => {
                        GLib.Idle.add (() => {
                            if (!completed) {
                                complete ();
                            }
                            return GLib.Source.REMOVE;
                        });
                    });
                }

                if (cancellable != null && cancellable.is_cancelled ()) {
                    complete ();
                }
                else {
                    var options = new GLib.VariantDict ();
                    options.insert_value ("handle_token", new GLib.Variant.string (handle_token));
                    options.insert_value ("autostart", new GLib.Variant.boolean (autostart));
                    options.insert_value ("commandline", new GLib.Variant.strv (COMMANDLINE));

                    // GDBus supplies the method-call timeout. The portal's separate
                    // Response signal may wait for user interaction for longer.
                    proxy.request_background.begin (parent_window, options.end (), (obj, res) => {
                        try {
                            proxy.request_background.end (res);
                            if (!completed) {
                                // This timer only covers a missing Response after the
                                // method returned. The interface bounds the method call.
                                timeout_id = GLib.Timeout.add_seconds (this.response_timeout, () => {
                                    timeout_id = 0U;
                                    GLib.warning ("Timed out waiting for background response");
                                    return complete ();
                                });
                            }
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while requesting background: %s", error.message);
                            if (!completed) {
                                complete ();
                            }
                        }
                    });
                }

                if (!completed) {
                    waiting = true;
                    yield;
                    waiting = false;
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while requesting background: %s", error.message);
            }
            finally {
                completed = true;
                if (timeout_id != 0U) {
                    GLib.Source.remove (timeout_id);
                }
                if (cancelled_id != 0) {
                    GLib.SignalHandler.disconnect (cancellable, cancelled_id);
                }
                if (handle_token != null) {
                    if (received_response) {
                        Portal.destroy_request (handle_token);
                    }
                    else {
                        Portal.close_request (handle_token);
                    }
                }
                complete = null;
            }
        }
    }
}
