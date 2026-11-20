/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Tests
{
    private class MockBackgroundProvider : Ft.Provider, Ft.BackgroundProvider
    {
        public bool background_allowed {
            get { return this.allowed; }
        }

        public bool autostart_allowed {
            get { return false; }
        }

        public bool allow_request = false;
        public bool block_request = false;
        public int pending = 0;
        public string last_parent_window = "";
        public bool last_autostart = false;

        private bool allowed = false;

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.available = true;
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
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
            this.pending++;
            this.last_parent_window = parent_window;
            this.last_autostart = autostart;

            var cancelled = cancellable != null && cancellable.is_cancelled ();

            if (!cancelled)
            {
                if (this.block_request)
                {
                    if (cancellable != null) {
                        cancellable.cancelled.connect (() => {
                            this.request_background.callback ();
                        });

                        yield;

                        cancelled = cancellable.is_cancelled ();
                    }
                }
                else {
                    GLib.Idle.add (() => {
                        this.request_background.callback ();
                        return GLib.Source.REMOVE;
                    });

                    yield;

                    cancelled = cancellable != null && cancellable.is_cancelled ();
                }
            }

            if (!cancelled && this.allowed != this.allow_request) {
                this.allowed = this.allow_request;
                this.notify_property ("background-allowed");
            }

            this.pending--;

            if (this.pending == 0) {
                this.requests_settled ();
            }

            // A finished portal request can still deny background access.
            // Cancellation is the failure result.
            return !cancelled;
        }

        public signal void requests_settled ();
    }

    public class BackgroundManagerTest : Tests.MainLoopTestSuite
    {
        private GLib.Application application;
        private Ft.BackgroundManager manager;
        private MockBackgroundProvider mock;

        public BackgroundManagerTest ()
        {
            this.add_test ("permission_granted", this.test_permission_granted);
            this.add_test ("permission_denied", this.test_permission_denied);
            this.add_test ("pending_hold_is_independent_of_permission", this.test_pending_permission);
            this.add_test ("permission_revoked", this.test_permission_revoked);
            this.add_test ("retry_after_denial", this.test_retry_after_denial);
            this.add_test ("request_timeout_preserves_permission", this.test_request_timeout);
            this.add_test ("hold_before_provider_ready", this.test_hold_before_provider_ready);
        }

        public override void setup ()
        {
            base.setup ();

            this.application = new GLib.Application (null, GLib.ApplicationFlags.NON_UNIQUE);
            this.mock = new MockBackgroundProvider ();
            this.manager = new Ft.BackgroundManager.with_provider (this.mock);

            GLib.Application.set_default (this.application);
            Ft.get_settings ().set_boolean ("autostart", false);

            if (!this.manager.enabled || this.manager.provider != this.mock)
            {
                var handler_id = this.manager.notify["enabled"].connect (() => {
                    if (this.manager.enabled && this.manager.provider == this.mock) {
                        this.quit_main_loop ();
                    }
                });
                assert_true (this.run_main_loop ());
                this.manager.disconnect (handler_id);
            }

            this.wait_until_settled ();
            assert_true (this.manager.enabled);
            assert_true (this.manager.provider == this.mock);
            assert_false (this.manager.active);
            assert_false (this.manager.background_allowed);
        }

        public override void teardown ()
        {
            this.wait_until_settled ();

            if (this.manager != null) {
                this.manager.destroy ();
            }

            GLib.Application.set_default (null);

            this.manager = null;
            this.mock = null;
            this.application = null;

            base.teardown ();
        }

        private void wait_until_settled ()
        {
            while (this.mock != null && this.mock.pending > 0)
            {
                var handler_id = this.mock.requests_settled.connect (() => {
                    this.quit_main_loop ();
                });

                if (this.mock.pending == 0) {
                    this.mock.disconnect (handler_id);
                    return;
                }

                var finished = this.run_main_loop ();
                this.mock.disconnect (handler_id);
                assert_true (finished);
            }
        }

        private bool request_permission (bool   allowed,
                                         string parent_window = "",
                                         int    timeout = 0)
        {
            var success = false;

            this.mock.allow_request = allowed;

            this.manager.request_background.begin (parent_window, timeout, (obj, res) => {
                success = this.manager.request_background.end (res);
                this.quit_main_loop ();
            });

            assert_true (this.run_main_loop ());
            this.wait_until_settled ();

            return success;
        }

        private uint hold_until_settled ()
        {
            var hold_id = this.manager.hold ();

            this.wait_until_settled ();

            return hold_id;
        }

        private void test_permission_granted ()
        {
            var success = false;
            var finished = false;

            this.mock.allow_request = true;

            this.manager.request_background.begin ("x11:1", 0, (obj, res) => {
                success = this.manager.request_background.end (res);
                finished = true;
                this.quit_main_loop ();
            });
            assert_false (finished);
            assert_false (this.manager.active);
            assert_cmpstr (this.mock.last_parent_window, GLib.CompareOperator.EQ, "x11:1");
            assert_false (this.mock.last_autostart);
            assert_true (this.run_main_loop ());
            assert_true (finished);
            assert_true (success);
            assert_false (this.manager.active);
            assert_true (this.manager.background_allowed);

            var hold_id = this.manager.hold ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_true (this.manager.active);
            // Permission is already granted, so holding does not ask again.
            assert_cmpint (this.mock.pending, GLib.CompareOperator.EQ, 0);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_true (this.manager.background_allowed);
        }

        private void test_permission_denied ()
        {
            assert_true (this.request_permission (false));
            assert_false (this.manager.background_allowed);
            assert_false (this.manager.active);

            var hold_id = this.hold_until_settled ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_false (this.manager.background_allowed);
            // Missing permission does not drop the application hold.
            assert_true (this.manager.active);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_false (this.manager.background_allowed);
        }

        private void test_pending_permission ()
        {
            this.mock.allow_request = false;

            var hold_id = this.manager.hold ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_true (this.manager.active);
            assert_false (this.manager.background_allowed);
            assert_cmpint (this.mock.pending, GLib.CompareOperator.GT, 0);

            this.wait_until_settled ();
            assert_false (this.manager.background_allowed);
            assert_true (this.manager.active);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_false (this.manager.background_allowed);
        }

        private void test_permission_revoked ()
        {
            assert_true (this.request_permission (true));

            var hold_id = this.hold_until_settled ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_true (this.manager.active);
            assert_true (this.manager.background_allowed);

            assert_true (this.request_permission (false));
            assert_false (this.manager.background_allowed);
            // Revoking permission leaves existing holds in place.
            assert_true (this.manager.active);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_false (this.manager.background_allowed);
        }

        private void test_retry_after_denial ()
        {
            assert_true (this.request_permission (false));
            assert_false (this.manager.background_allowed);
            assert_false (this.manager.active);

            var hold_id = this.hold_until_settled ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_true (this.manager.active);
            assert_false (this.manager.background_allowed);

            assert_true (this.request_permission (true));
            assert_true (this.manager.background_allowed);
            // Granting permission leaves the hold taken during the denial in place.
            assert_true (this.manager.active);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_true (this.manager.background_allowed);
        }

        private void test_request_timeout ()
        {
            assert_true (this.request_permission (true));
            assert_true (this.manager.background_allowed);

            var success = true;

            this.mock.block_request = true;

            this.manager.request_background.begin ("", 20, (obj, res) => {
                success = this.manager.request_background.end (res);
                this.quit_main_loop ();
            });
            assert_false (this.manager.active);
            assert_true (this.run_main_loop (100));
            this.mock.block_request = false;

            this.wait_until_settled ();
            assert_false (success);
            assert_true (this.manager.background_allowed);
            assert_false (this.manager.active);
        }

        private void test_hold_before_provider_ready ()
        {
            this.manager.destroy ();
            this.manager = null;
            this.mock = new MockBackgroundProvider ();
            this.mock.allow_request = true;
            this.manager = new Ft.BackgroundManager.with_provider (this.mock);
            assert_false (this.manager.enabled);

            var hold_id = this.manager.hold ();
            assert_cmpuint (hold_id, GLib.CompareOperator.NE, 0U);
            assert_true (this.manager.active);
            assert_false (this.manager.background_allowed);

            var handler_id = this.manager.notify["background-allowed"].connect (() => {
                if (this.manager.background_allowed && this.manager.provider == this.mock) {
                    GLib.Idle.add (() => {
                        this.quit_main_loop ();
                        return GLib.Source.REMOVE;
                    });
                }
            });
            assert_true (this.run_main_loop ());
            this.manager.disconnect (handler_id);

            this.wait_until_settled ();
            assert_true (this.manager.background_allowed);
            assert_true (this.manager.active);

            this.manager.release (hold_id);
            assert_false (this.manager.active);
            assert_true (this.manager.background_allowed);
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.BackgroundManagerTest ()
    );
}
