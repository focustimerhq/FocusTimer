/*
 * Copyright (c) 2025-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Portal
{
    private bool is_cancelled (GLib.Cancellable? cancellable_1,
                               GLib.Cancellable? cancellable_2)
    {
        if (cancellable_1 != null && cancellable_1.is_cancelled ()) {
            return true;
        }

        if (cancellable_2 != null && cancellable_2.is_cancelled ()) {
            return true;
        }

        return false;
    }


    [CCode (has_target = true)]
    private delegate void Callback ();


    public class BackgroundProvider : Ft.Provider, Ft.BackgroundProvider
    {
        /**
         * Warn if underlying `Background` API version changes. Bump this value after testing.
         */
        private const uint COMAPTIBLE_VERSION = 2U;

        private const string[] COMMANDLINE = {"focus-timer", "--gapplication-service"};

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

        private bool                                 _background_allowed = false;
        private bool                                 _autostart_allowed = false;
        private GLib.DBusConnection?                 connection = null;
        private Portal.Background?                   proxy = null;
        private GLib.Cancellable?                    cancellable = null;
        private uint                                 dbus_watcher_id = 0U;

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
                this.cancellable = null;
            }

            this.proxy = null;
        }

        public override async void uninitialize () throws GLib.Error
        {
            if (this.dbus_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.dbus_watcher_id);
                this.dbus_watcher_id = 0;
            }
        }

        private bool handle_response (uint         response,
                                      GLib.Variant results)
        {
            var background_variant = results.lookup_value ("background", null);
            var autostart_variant = results.lookup_value ("autostart", null);
            var background_allowed = background_variant != null
                    ? background_variant.get_boolean ()
                    : this._background_allowed;
            var autostart_allowed = autostart_variant != null
                    ? autostart_variant.get_boolean ()
                    : this._autostart_allowed;

            if (this._background_allowed != background_allowed) {
                this._background_allowed = background_allowed;
                this.notify_property ("background-allowed");
            }

            if (this._autostart_allowed != autostart_allowed) {
                this._autostart_allowed = autostart_allowed;
                this.notify_property ("autostart-allowed");
            }

            return response == 0;
        }

        public async bool request_background (bool              autostart,
                                              string            parent_window,
                                              GLib.Cancellable? cancellable)
        {
            if (this.proxy == null || is_cancelled (this.cancellable, cancellable)) {
                return false;
            }

            var proxy = this.proxy;
            var self_cancellable = this.cancellable;
            var success = false;
            Portal.Callback? finish_request = null;
            string handle_token;

            finish_request = () => {
                finish_request = null;

                this.request_background.callback ();
            };

            try {
                handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        success = this.handle_response (response, results);

                        if (this._autostart_allowed != autostart) {
                            GLib.warning ("Failed to set `autostart = %s`",
                                          autostart.to_string ());
                        }

                        if (finish_request != null) {
                            finish_request ();
                        }
                    });
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while requesting background: %s", error.message);
                finish_request = null;

                return false;
            }

            if (proxy != null && !is_cancelled (self_cancellable, cancellable))
            {
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
                            GLib.warning ("Error while requesting background: %s",
                                          error.message);

                            // No response is coming. Keep the last permission.
                            if (finish_request != null) {
                                finish_request ();
                            }
                        }
                    });

                var self_cancelled_id = 0UL;
                var cancelled_id = 0UL;

                if (self_cancellable != null) {
                    self_cancelled_id = self_cancellable.connect (() => {
                        GLib.Idle.add (() => {
                            if (finish_request != null) {
                                finish_request ();
                            }

                            return GLib.Source.REMOVE;
                        });
                    });
                }

                if (cancellable != null) {
                    cancelled_id = cancellable.connect (() => {
                        GLib.Idle.add (() => {
                            if (finish_request != null) {
                                finish_request ();
                            }

                            return GLib.Source.REMOVE;
                        });
                    });
                }

                yield;  // Wait for response

                if (self_cancelled_id != 0UL) {
                    self_cancellable.disconnect (self_cancelled_id);
                }

                if (cancelled_id != 0UL) {
                    cancellable.disconnect (cancelled_id);
                }
            }

            finish_request = null;

            try {
                yield Portal.close_request (handle_token);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error closing background request: %s", error.message);
            }

            return success;
        }
    }
}
