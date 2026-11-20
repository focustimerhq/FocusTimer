/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Tests
{
    [DBus (name = "org.freedesktop.portal.Background")]
    public class MockBackgroundPortal : GLib.Object
    {
        [DBus (name = "version")]
        public uint version {
            get { return 1U; }
        }

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

            if (parent_window == "no-response") {
                return new GLib.ObjectPath (path);
            }

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

            GLib.Idle.add (() => {
                var results = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
                var failed = parent_window == "cancel" ||
                             parent_window == "revoke" ||
                             parent_window == "cancel-grant";
                // Keys that are present update the cached permission, including
                // when the request itself failed. Missing keys keep the previous value.
                if (parent_window != "empty" && parent_window != "cancel") {
                    var background = parent_window != "deny" && parent_window != "revoke";
                    results.add ("{sv}", "background", new GLib.Variant.boolean (background));
                    results.add ("{sv}", "autostart", new GLib.Variant.boolean (false));
                }
                try {
                    this.connection.emit_signal (
                            sender, path, "org.freedesktop.portal.Request", "Response",
                            new GLib.Variant ("(ua{sv})", failed ? 1U : 0U, results));
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
                return GLib.Source.REMOVE;
            });
            return new GLib.ObjectPath (path);
        }
    }

    public class BackgroundProviderTest : Tests.MainLoopTestSuite
    {
        private Portal.BackgroundProvider provider;

        public BackgroundProviderTest ()
        {
            this.add_test ("permission_granted", this.test_permission_granted);
            this.add_test ("permission_denied", this.test_permission_denied);
            this.add_test ("cancelled_response", this.test_cancelled_response);
            this.add_test ("failed_response_updates_permissions", this.test_failed_response_updates);
            this.add_test ("empty_response_preserves_permission", this.test_empty_response);
            this.add_test ("method_error_preserves_permission", this.test_method_error);
            this.add_test ("cancellation_preserves_permission", this.test_cancellation);
            this.add_test ("disable_preserves_permission", this.test_disable_preserves_permission);
            this.add_test ("disable_completes_pending_request", this.test_disable_pending);
            this.add_test ("disable_during_request_creation", this.test_disable_during_creation);
            this.add_test ("disable_rejects_new_request", this.test_disable_rejects_request);
            this.add_test ("retry_after_denial", this.test_retry_after_denial);
            this.add_test ("cancel_preserves_granted_permission", this.test_cancel_preserves_permission);
            this.add_test ("response_wins_over_method_error", this.test_response_wins);
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

            this.flush_main_context ();
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

        private void flush_main_context ()
        {
            var context = GLib.MainContext.default ();

            // The portal method reply is completed on a later idle than
            // Request.Response. Dispatch it before disable() drops the proxy.
            for (var pass = 0; pass < 3; pass++) {
                while (context.pending ()) {
                    context.iteration (false);
                }

                if (pass == 2) {
                    break;
                }

                GLib.Timeout.add (10, () => {
                    this.quit_main_loop ();
                    return GLib.Source.REMOVE;
                });
                this.main_loop.run ();
            }
        }

        private bool request (string            scenario,
                              GLib.Cancellable? cancellable = null,
                              uint              timeout = 2000)
        {
            bool success = false;
            this.provider.request_background.begin (false, scenario, cancellable, (obj, res) => {
                success = this.provider.request_background.end (res);
                this.quit_main_loop ();
            });
            assert (this.run_main_loop (timeout));
            // The portal method reply can be dispatched after Request.Response.
            // Let it finish before a later disable() drops the proxy.
            this.flush_main_context ();
            return success;
        }

        private void test_permission_granted ()
        {
            assert (this.request ("grant"));
            assert (this.provider.background_allowed);
            assert (!this.provider.autostart_allowed);
        }

        private void test_permission_denied ()
        {
            // The portal answered; background access itself is denied.
            assert (this.request ("deny"));
            assert (!this.provider.background_allowed);
        }

        private void test_cancelled_response ()
        {
            assert (!this.request ("cancel"));
            assert (!this.provider.background_allowed);
        }

        private void test_failed_response_updates ()
        {
            assert (this.request ("grant"));
            assert (this.provider.background_allowed);
            assert (!this.request ("revoke"));
            assert (!this.provider.background_allowed);
            assert (!this.provider.autostart_allowed);

            assert (!this.request ("cancel-grant"));
            assert (this.provider.background_allowed);
        }

        private void test_method_error ()
        {
            assert (this.request ("grant"));
            assert (!this.request ("error"));
            assert (this.provider.background_allowed);
            assert (!this.provider.autostart_allowed);
        }

        private void test_cancellation ()
        {
            assert (this.request ("grant"));
            var cancellable = new GLib.Cancellable ();
            GLib.Timeout.add (50, () => {
                cancellable.cancel ();
                return GLib.Source.REMOVE;
            });
            assert (!this.request ("no-response", cancellable));
            assert (this.provider.background_allowed);
            assert (!this.provider.autostart_allowed);
        }

        private void test_disable_pending ()
        {
            assert (this.request ("grant"));
            var provider = this.provider;
            GLib.Timeout.add (50, () => {
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
            assert (!this.request ("no-response"));
            assert (provider.background_allowed);
            assert (!provider.autostart_allowed);
        }

        private void test_disable_during_creation ()
        {
            var provider = this.provider;
            bool success = true;
            bool finished = false;
            provider.request_background.begin (false, "no-response", null, (obj, res) => {
                success = provider.request_background.end (res);
                finished = true;
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
            assert (finished);
            assert (!success);
            assert (!provider.background_allowed);
        }

        private void test_empty_response ()
        {
            assert (this.request ("grant"));
            assert (this.request ("empty"));
            assert (this.provider.background_allowed);
        }

        private void test_disable_preserves_permission ()
        {
            assert (this.request ("grant"));
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

        private void test_disable_rejects_request ()
        {
            assert (this.request ("grant"));
            var provider = this.provider;
            provider.disable.begin ((obj, res) => {
                try {
                    provider.disable.end (res);
                }
                catch (GLib.Error error) {
                    assert_not_reached ();
                }
                this.quit_main_loop ();
            });
            assert (this.run_main_loop (2000));
            assert (provider.background_allowed);
            assert (!this.request ("grant"));
            assert (provider.background_allowed);
        }

        private void test_retry_after_denial ()
        {
            assert (this.request ("deny"));
            assert (!this.provider.background_allowed);
            assert (this.request ("grant"));
            assert (this.provider.background_allowed);
        }

        private void test_cancel_preserves_permission ()
        {
            assert (this.request ("grant"));
            assert (!this.request ("cancel"));
            assert (this.provider.background_allowed);
            assert (!this.provider.autostart_allowed);
        }

        private void test_response_wins ()
        {
            assert (this.request ("grant-then-error"));
            assert (this.provider.background_allowed);
        }

    }
}


public static int main (string[] args)
{
    Tests.init (args);

    var dbus = new Tests.DBus ();

    dbus.register_object ("org.freedesktop.portal.Desktop",
                  "/org/freedesktop/portal/desktop",
                  new Tests.MockBackgroundPortal (dbus.connection));

    return Tests.run (
        new Tests.BackgroundProviderTest ()
    );
}
