/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Tests
{
    [DBus (name = "org.freedesktop.portal.Background")]
    private class MockBackgroundPortal : GLib.Object
    {
        [DBus (name = "version")]
        public uint version { get { return 1U; } }

        private GLib.DBusConnection connection;

        public MockBackgroundPortal (GLib.DBusConnection connection)
        {
            this.connection = connection;
        }

        public GLib.ObjectPath request_background (
                string parent_window,
                [DBus (signature = "a{sv}")] GLib.Variant options,
                GLib.BusName sender) throws GLib.DBusError, GLib.IOError
        {
            if (parent_window == "error") {
                throw new GLib.DBusError.FAILED ("Background portal unavailable");
            }

            var token = options.lookup_value ("handle_token", GLib.VariantType.STRING).get_string ();
            var sender_escaped = sender.replace (":", "").replace (".", "_");
            var path = @"/org/freedesktop/portal/desktop/request/$(sender_escaped)/$(token)";

            if (parent_window == "grant-then-error") {
                var granted = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
                granted.add ("{sv}", "background", new GLib.Variant.boolean (true));
                try {
                    this.connection.emit_signal (
                            sender, path, "org.freedesktop.portal.Request", "Response",
                            new GLib.Variant ("(ua{sv})", 0U, granted));
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
                throw new GLib.DBusError.FAILED ("Error after successful response");
            }

            if (parent_window != "no-response" && parent_window != "no-method-reply") {
                GLib.Idle.add (() => {
                    var results = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
                    if (parent_window != "empty") {
                        results.add ("{sv}", "background", new GLib.Variant.boolean (parent_window != "deny"));
                        results.add ("{sv}", "autostart", new GLib.Variant.boolean (false));
                    }
                    try {
                        this.connection.emit_signal (
                                sender, path, "org.freedesktop.portal.Request", "Response",
                                new GLib.Variant ("(ua{sv})", parent_window == "cancel" ? 1U : 0U, results));
                    }
                    catch (GLib.Error error) {
                        assert_not_reached ();
                    }
                    return GLib.Source.REMOVE;
                });
            }
            return new GLib.ObjectPath (path);
        }
    }

    public class BackgroundPortalTest : Tests.MainLoopTestSuite
    {
        private Portal.BackgroundProvider provider;

        public BackgroundPortalTest ()
        {
            this.add_test ("permission_granted", this.test_permission_granted);
            this.add_test ("permission_denied", this.test_permission_denied);
            this.add_test ("cancelled_response", this.test_cancelled_response);
            this.add_test ("method_error_completes", this.test_method_error_completes);
            this.add_test ("empty_response_preserves_permission", this.test_empty_response);
            this.add_test ("disable_preserves_permission", this.test_disable_preserves_permission);
            this.add_test ("disable_completes_pending_request", this.test_disable);
            this.add_test ("disable_during_request_creation", this.test_disable_during_creation);
            this.add_test ("missing_response_times_out", this.test_timeout);
            this.add_test ("missing_method_reply_times_out", this.test_method_timeout);
            this.add_test ("retry_after_denial", this.test_retry_after_denial);
            this.add_test ("cancel_preserves_granted_permission", this.test_cancel_preserves_permission);
            this.add_test ("response_wins_over_method_error", this.test_response_wins);
        }

        public override void setup ()
        {
            base.setup ();
            this.provider = new Portal.BackgroundProvider ();
            this.provider.response_timeout = 1U;
            this.provider.initialize.begin (null, (obj, res) => {
                try {
                    this.provider.initialize.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
            });
            var handler_id = this.provider.notify["available"].connect (() => {
                if (this.provider.available) {
                    this.provider.enable.begin (null, (obj, res) => {
                        try {
                            this.provider.enable.end (res);
                        }
                        catch (GLib.Error error) {
                            assert_not_reached ();
                        }
                        this.quit_main_loop ();
                    });
                }
            });
            assert (this.run_main_loop (3000));
            this.provider.disconnect (handler_id);
        }

        public override void teardown ()
        {
            if (this.provider == null) {
                base.teardown ();
                return;
            }

            var provider = this.provider;
            provider.disable.begin ((obj, res) => {
                try {
                    provider.disable.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
            });
            provider.uninitialize.begin ((obj, res) => {
                try {
                    provider.uninitialize.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
            });
            this.provider = null;
            base.teardown ();
        }

        private void request (string scenario,
                              uint   timeout = 2000)
        {
            this.provider.request_background.begin (false, scenario, (obj, res) => {
                this.provider.request_background.end (res);
                this.quit_main_loop ();
            });
            assert (this.run_main_loop (timeout));
        }

        private void test_permission_granted ()
        {
            this.request ("grant");
            assert (this.provider.background_allowed);
        }

        private void test_permission_denied ()
        {
            this.request ("deny");
            assert (!this.provider.background_allowed);
        }

        private void test_cancelled_response ()
        {
            this.request ("cancel");
            assert (!this.provider.background_allowed);
        }

        private void test_method_error_completes ()
        {
            this.request ("grant");
            this.request ("error");
            assert (this.provider.background_allowed);
        }

        private void test_empty_response ()
        {
            this.request ("grant");
            this.request ("empty");
            assert (this.provider.background_allowed);
        }

        private void test_disable_preserves_permission ()
        {
            this.request ("grant");
            var provider = this.provider;
            provider.disable.begin ((obj, res) => {
                try {
                    provider.disable.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
                GLib.Idle.add (() => {
                    this.quit_main_loop ();
                    return GLib.Source.REMOVE;
                });
            });
            assert (this.run_main_loop (2000));
            assert (provider.background_allowed);
            assert (!provider.autostart_allowed);
        }

        private void test_disable ()
        {
            GLib.Timeout.add (50, () => {
                var provider = this.provider;
                provider.disable.begin ((obj, res) => {
                    try {
                        provider.disable.end (res);
                    }
                    catch (GLib.Error error) {
                        assert_not_reached ();
                    }
                });
                return GLib.Source.REMOVE;
            });
            this.request ("no-response");
            assert (!this.provider.background_allowed);
        }

        private void test_retry_after_denial ()
        {
            this.request ("deny");
            this.request ("grant");
            assert (this.provider.background_allowed);
        }

        private void test_cancel_preserves_permission ()
        {
            this.request ("grant");
            this.request ("cancel");
            assert (this.provider.background_allowed);
        }

        private void test_response_wins ()
        {
            this.request ("grant-then-error");
            assert (this.provider.background_allowed);
        }

        private void test_disable_during_creation ()
        {
            var provider = this.provider;
            provider.request_background.begin (false, "no-response", (obj, res) => {
                provider.request_background.end (res);
                this.quit_main_loop ();
            });
            provider.disable.begin ((obj, res) => {
                try {
                    provider.disable.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
            });
            assert (this.run_main_loop (2000));
            assert (!provider.background_allowed);
        }

        private void test_method_timeout ()
        {
            // A short signal watchdog must not mask the interface's method timeout.
            this.provider.response_timeout = 1U;
            var started = GLib.get_monotonic_time ();
            this.request ("no-method-reply", 13000);
            var elapsed = GLib.get_monotonic_time () - started;
            assert (elapsed >= 9 * GLib.TimeSpan.SECOND);
            assert (elapsed < 13 * GLib.TimeSpan.SECOND);
            assert (!this.provider.background_allowed);
        }

        private void test_timeout ()
        {
            this.request ("no-response");
            assert (!this.provider.background_allowed);
        }

    }

    public int main (string[] args)
    {
        Tests.init (args);
        var desktop_address = GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS");
        var bus = new GLib.TestDBus (GLib.TestDBusFlags.NONE);
        bus.up ();
        var address = bus.get_bus_address ();
        assert (address != desktop_address);

        // The replacement portal only exists on this test's private bus. Use an
        // explicit connection so it cannot accidentally own the desktop portal name.
        GLib.MainLoop? service_loop = null;
        var ready = new GLib.AsyncQueue<string> ();
        var service = new GLib.Thread<void*> ("private-portal", () => {
            var context = new GLib.MainContext ();
            context.push_thread_default ();
            try {
                var connection = new GLib.DBusConnection.for_address_sync (
                        address,
                        GLib.DBusConnectionFlags.AUTHENTICATION_CLIENT |
                        GLib.DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
                connection.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus",
                        "org.freedesktop.DBus", "RequestName",
                        new GLib.Variant ("(su)", "org.freedesktop.portal.Desktop", 0U),
                        null, GLib.DBusCallFlags.NONE, -1);
                uint drop_reply_serial = 0U;
                var filter = connection.add_filter ((conn, message, incoming) => {
                    if (incoming && message.get_message_type () == GLib.DBusMessageType.METHOD_CALL &&
                        message.get_member () == "RequestBackground") {
                        assert ((message.get_flags () & GLib.DBusMessageFlags.NO_REPLY_EXPECTED) == 0);
                        if (message.get_body ().get_child_value (0).get_string () == "no-method-reply") {
                            drop_reply_serial = message.get_serial ();
                        }
                    }
                    if (!incoming && drop_reply_serial != 0U &&
                        message.get_reply_serial () == drop_reply_serial) {
                        return null;
                    }
                    return message;
                });
                var registration = connection.register_object (
                        "/org/freedesktop/portal/desktop", new MockBackgroundPortal (connection));
                service_loop = new GLib.MainLoop (context);
                ready.push ("ready");
                service_loop.run ();
                connection.unregister_object (registration);
                connection.remove_filter (filter);
                connection.close_sync ();
            }
            catch (GLib.Error error) {
                GLib.error ("Private portal failed: %s", error.message);
            }
            context.pop_thread_default ();
            return null;
        });
        ready.pop ();
        var result = Tests.run (new BackgroundPortalTest ());
        service_loop.quit ();
        service.join ();
        bus.down ();
        return result;
    }
}
