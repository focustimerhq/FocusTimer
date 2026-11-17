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

            if (parent_window != "no-response") {
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
            this.add_test ("empty_response_revokes_permission", this.test_empty_response);
            this.add_test ("disable_clears_permission", this.test_disable_clears_permission);
            this.add_test ("disable_completes_pending_request", this.test_disable);
            this.add_test ("disable_during_request_creation", this.test_disable_during_creation);
            this.add_test ("missing_response_times_out", this.test_timeout);
            this.add_test ("retry_after_denial", this.test_retry_after_denial);
        }

        public override void setup ()
        {
            base.setup ();
            this.provider = new Portal.BackgroundProvider ();
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
            assert (!this.provider.background_allowed);
        }

        private void test_empty_response ()
        {
            this.request ("grant");
            this.request ("empty");
            assert (!this.provider.background_allowed);
        }

        private void test_disable_clears_permission ()
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
            assert (!provider.background_allowed);
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

        private void test_timeout ()
        {
            this.request ("no-response", 65000);
            assert (!this.provider.background_allowed);
        }
    }

    public int main (string[] args)
    {
        if (args.length > 1 && args[1] == "--mock-portal") {
            var loop = new GLib.MainLoop ();
            GLib.Bus.own_name (GLib.BusType.SESSION, "org.freedesktop.portal.Desktop",
                    GLib.BusNameOwnerFlags.NONE, (connection) => {
                try {
                    connection.register_object ("/org/freedesktop/portal/desktop",
                                                new MockBackgroundPortal (connection));
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
            });
            loop.run ();
            return 0;
        }

        Tests.init (args);
        var bus = new GLib.TestDBus (GLib.TestDBusFlags.NONE);
        bus.up ();
        int result = 1;
        try {
            var service = new GLib.Subprocess (GLib.SubprocessFlags.NONE, args[0], "--mock-portal");
            result = Tests.run (new BackgroundPortalTest ());
            service.force_exit ();
            service.wait ();
        }
        catch (GLib.Error error) {
            assert_not_reached ();
        }
        bus.down ();
        return result;
    }
}
