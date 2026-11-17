/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Tests
{
    private class MockBackgroundProvider : Ft.Provider, Ft.BackgroundProvider
    {
        public bool background_allowed { get { return this.allowed; } }
        public bool autostart_allowed { get { return false; } }
        public bool allow_request = false;
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

        public async void request_background (bool autostart, string parent_window)
        {
            GLib.Idle.add (() => {
                this.request_background.callback ();
                return GLib.Source.REMOVE;
            });
            yield;
            this.allowed = this.allow_request;
            this.notify_property ("background-allowed");
        }
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
            this.add_test ("pending_permission_is_not_active", this.test_pending_permission);
            this.add_test ("permission_revoked", this.test_permission_revoked);
            this.add_test ("retry_after_denial", this.test_retry_after_denial);
            this.add_test ("no_provider", this.test_no_provider);
            this.add_test ("hold_sync_before_provider_ready", this.test_hold_sync_before_provider_ready);
        }

        public override void setup ()
        {
            base.setup ();
            this.application = new GLib.Application (null, GLib.ApplicationFlags.NON_UNIQUE);
            Ft.get_settings ().set_boolean ("autostart", false);
            this.mock = new MockBackgroundProvider ();
            this.manager = new Ft.BackgroundManager.with_provider (this.mock);
            if (!this.manager.enabled || this.manager.provider != this.mock) {
                var handler_id = this.manager.notify["enabled"].connect (() => {
                    if (this.manager.enabled && this.manager.provider == this.mock) {
                        this.quit_main_loop ();
                    }
                });
                assert (this.run_main_loop ());
                this.manager.disconnect (handler_id);
            }
        }

        public override void teardown ()
        {
            if (this.manager != null) {
                this.manager.destroy ();
            }
            this.manager = null;
            this.mock = null;
            this.application = null;
            base.teardown ();
        }

        private uint request_hold (bool allowed)
        {
            uint hold_id = 0U;
            this.mock.allow_request = allowed;
            this.manager.hold.begin ("x11:1", (obj, res) => {
                hold_id = this.manager.hold.end (res);
                this.quit_main_loop ();
            });
            assert (this.run_main_loop ());
            return hold_id;
        }

        private void test_no_provider ()
        {
            this.mock.available = false;
            GLib.Idle.add (() => {
                this.quit_main_loop ();
                return GLib.Source.REMOVE;
            });
            assert (this.run_main_loop ());
            this.manager.hold.begin ("", (obj, res) => {
                var hold_id = this.manager.hold.end (res);
                assert ((hold_id != 0U) == !Ft.is_flatpak ());
                assert (this.manager.active == !Ft.is_flatpak ());
                this.manager.release (hold_id);
                GLib.Idle.add (() => {
                    this.quit_main_loop ();
                    return GLib.Source.REMOVE;
                });
            });
            assert (this.run_main_loop ());
            assert (!this.manager.active);
        }

        private void test_hold_sync_before_provider_ready ()
        {
            this.manager.destroy ();
            this.manager = null;
            this.mock = new MockBackgroundProvider ();
            this.mock.allow_request = true;
            this.manager = new Ft.BackgroundManager.with_provider (this.mock);
            assert (!this.manager.enabled);
            var hold_id = this.manager.hold_sync ();
            assert (hold_id != 0U);
            assert (this.manager.active == !Ft.is_flatpak ());
            var handler_id = this.manager.notify["background-allowed"].connect (() => {
                if (this.manager.background_allowed) {
                    // Let the permission request finish updating the application hold.
                    GLib.Idle.add (() => {
                        this.quit_main_loop ();
                        return GLib.Source.REMOVE;
                    });
                }
            });
            assert (this.run_main_loop ());
            this.manager.disconnect (handler_id);
            assert (this.manager.active);
            this.manager.release (hold_id);
            assert (!this.manager.active);
        }

        private void test_permission_granted ()
        {
            var hold_id = this.request_hold (true);
            assert (hold_id != 0U);
            assert (this.manager.active);
            this.manager.release (hold_id);
            assert (!this.manager.active);
        }

        private void test_permission_denied ()
        {
            assert (this.request_hold (false) == 0U);
            assert (!this.manager.active);
        }

        private void test_pending_permission ()
        {
            this.manager.hold.begin ("x11:1", (obj, res) => {
                assert (this.manager.hold.end (res) == 0U);
                this.quit_main_loop ();
            });
            assert (!this.manager.active);
            assert (this.run_main_loop ());
        }

        private void test_permission_revoked ()
        {
            var hold_id = this.request_hold (true);
            assert (hold_id != 0U);
            assert (this.request_hold (false) == 0U);
            assert (!this.manager.active);
            this.manager.release (hold_id);
        }

        private void test_retry_after_denial ()
        {
            assert (this.request_hold (false) == 0U);
            var hold_id = this.request_hold (true);
            assert (hold_id != 0U);
            this.manager.release (hold_id);
            // A failed request must not leave a hold that keeps the app alive.
            assert (!this.manager.active);
        }
    }

    public int main (string[] args)
    {
        string config_dir;
        try {
            config_dir = GLib.DirUtils.make_tmp ("focus-timer-test-config-XXXXXX");
        }
        catch (GLib.Error error) {
            assert_not_reached ();
        }
        GLib.Environment.set_variable ("XDG_CONFIG_HOME", config_dir, true);
        Tests.init (args);
        var flatpak = GLib.Environment.get_variable ("FOCUS_TIMER_TEST_FLATPAK") == "1";
        GLib.Environment.set_variable ("container", flatpak ? "flatpak" : "", true);
        if (flatpak) {
            GLib.Environment.unset_variable ("G_TEST_ROOT_PROCESS");
        }
        assert (Ft.is_flatpak () == flatpak);
        var result = Tests.run (new BackgroundManagerTest ());
        GLib.DirUtils.remove (config_dir);
        return result;
    }
}
