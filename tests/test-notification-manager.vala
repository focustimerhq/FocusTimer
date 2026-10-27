namespace Tests
{
    private class MockNotificationBackend : GLib.Object, Ft.NotificationBackendInterface
    {
        public string[] log;

        construct
        {
            this.log = {};
        }

        public void withdraw_notification (string id)
        {
            this.log += @"withdraw:$(id)";
        }

        public void send_notification (string          id,
                                       Ft.Notification notification)
        {
            var entry = @"send:$(id):$(notification.title):$(notification.body)";

            this.log += entry;
            this.logged (entry);
        }

        public void clear ()
        {
            this.log = {};
        }

        public signal void logged (string entry);

        public override void dispose ()
        {
            this.log = null;

            base.dispose ();
        }
    }


    public class NotificationManagerTest : Tests.MainLoopTestSuite
    {
        private Ft.Timer timer;
        private Ft.SessionManager session_manager;
        private Ft.NotificationManager notification_manager;

        public NotificationManagerTest ()
        {
            this.add_test ("time_block_started", this.test_time_block_started);
            this.add_test ("time_block_running", this.test_time_block_running);
            this.add_test ("time_block_about_to_end", this.test_time_block_about_to_end);
            this.add_test ("time_block_ended", this.test_time_block_ended);
            this.add_test ("confirm_advancement__break", this.test_confirm_advancement__break);
            this.add_test ("confirm_advancement__pomodoro", this.test_confirm_advancement__pomodoro);
            this.add_test ("withdraw_notifications__pause", this.test_withdraw_notifications__pause);
            this.add_test ("withdraw_notifications__stop", this.test_withdraw_notifications__stop);
            this.add_test ("request_screen_overlay", this.test_request_screen_overlay);
            this.add_test ("request_screen_overlay__extend", this.test_request_screen_overlay__extend);
        }

        public override void setup ()
        {
            base.setup ();

            Ft.Timestamp.freeze_to (2000000000 * Ft.Interval.SECOND);
            Ft.Timestamp.set_auto_advance (Ft.Interval.MICROSECOND);

            this.timer = new Ft.Timer ();
            Ft.Timer.set_default (this.timer);

            this.session_manager = new Ft.SessionManager.with_timer (this.timer);
            Ft.SessionManager.set_default (this.session_manager);

            this.notification_manager = new Ft.NotificationManager.with_backend (
                    new MockNotificationBackend ());
            assert (!this.notification_manager.get_data<bool> ("teardown"));

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1500);
            settings.set_uint ("short-break-duration", 300);
            settings.set_uint ("long-break-duration", 900);
            settings.set_uint ("cycles", 4);
            settings.set_boolean ("announce-about-to-end", false);
            settings.set_boolean ("confirm-starting-break", false);
            settings.set_boolean ("confirm-starting-pomodoro", false);
            settings.set_boolean ("screen-overlay", false);

            this.session_manager.ensure_session ();
        }

        public override void teardown ()
        {
            this.notification_manager.set_data<bool> ("teardown", true);
            this.notification_manager.destroy ();

            this.notification_manager = null;
            this.session_manager = null;
            this.timer = null;

            Ft.SessionManager.set_default (null);
            Ft.Timer.set_default (null);

            base.teardown ();
        }

        private MockNotificationBackend get_mock_backend ()
        {
            return this.notification_manager.backend as MockNotificationBackend;
        }

        public void test_time_block_started ()
        {
            var backend = this.get_mock_backend ();
            backend.clear ();

            this.timer.start ();
            assert_cmpstrv (backend.log, {
                "send:timer:Pomodoro:25 minutes remaining"
            });
        }

        public void test_time_block_running ()
        {
            this.timer.start ();

            // Pause and resume to trigger notify_time_block_running
            Ft.Timestamp.advance (Ft.Interval.MINUTE);

            var backend = this.get_mock_backend ();
            backend.clear ();

            this.timer.pause ();
            assert_cmpstrv (backend.log, {
                "withdraw:timer"
            });

            backend.clear ();
            this.timer.resume ();
            assert_cmpstrv (backend.log, {
                "send:timer:Pomodoro:24 minutes remaining"
            });
        }

        public void test_time_block_about_to_end ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("announce-about-to-end", true);

            this.timer.start ();

            var backend = this.get_mock_backend ();
            backend.clear ();

            var time_block = this.session_manager.current_time_block;

            // Advance time to just BEFORE about-to-end threshold
            var timestamp_1 = time_block.end_time - 16 * Ft.Interval.SECOND;
            Ft.Timestamp.freeze_to (timestamp_1);
            this.timer.tick (timestamp_1);
            assert_cmpint (backend.log.length, GLib.CompareOperator.EQ, 0);

            // Advance time into the threshold
            var timestamp_2 = time_block.end_time - 10 * Ft.Interval.SECOND;
            Ft.Timestamp.freeze_to (timestamp_2);
            this.timer.tick (timestamp_2);
            assert_cmpstrv (backend.log, {
                @"send:timer:Pomodoro is about to end:"
            });

            // Another tick should NOT trigger another notification
            backend.clear ();
            var timestamp_3 = time_block.end_time - 9 * Ft.Interval.SECOND;
            Ft.Timestamp.freeze_to (timestamp_3);
            this.timer.tick (timestamp_3);
            assert_cmpstrv (backend.log, {});
        }

        public void test_time_block_ended ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-pomodoro", false);

            this.session_manager.advance_to_state (Ft.State.SHORT_BREAK);

            var backend = this.get_mock_backend ();
            backend.clear ();

            var now = this.session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (now);
            this.timer.finish (now);
            assert_cmpstrv (backend.log, {
                "send:timer:Break is over!:Get ready…"
            });
        }

        public void test_confirm_advancement__break ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);

            this.session_manager.advance_to_state (Ft.State.POMODORO);

            var backend = this.get_mock_backend ();
            backend.clear ();

            var confirm_advancement_emitted = 0;

            this.session_manager.confirm_advancement.connect (
                (current_time_block, next_time_block) => {
                    confirm_advancement_emitted++;
                });

            var now = this.session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (now);
            this.timer.finish (now);
            assert_cmpint (
                confirm_advancement_emitted,
                GLib.CompareOperator.EQ,
                1
            );
            assert_cmpstrv (backend.log, {
                "send:timer:Pomodoro is over!:Confirm the start of a short break…"
            });
        }

        public void test_confirm_advancement__pomodoro ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-pomodoro", true);

            this.session_manager.advance_to_state (Ft.State.SHORT_BREAK);

            var backend = this.get_mock_backend ();
            backend.clear ();

            var confirm_advancement_emitted = 0;

            this.session_manager.confirm_advancement.connect (
                (current_time_block, next_time_block) => {
                    confirm_advancement_emitted++;
                });

            var now = this.session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (now);
            this.timer.finish (now);
            assert_cmpint (
                confirm_advancement_emitted,
                GLib.CompareOperator.EQ,
                1
            );
            assert_cmpstrv (backend.log, {
                "send:timer:Break is over!:Confirm the start of a Pomodoro…"
            });
        }

        public void test_withdraw_notifications__pause ()
        {
            this.session_manager.advance_to_state (Ft.State.POMODORO);

            var backend = this.get_mock_backend ();
            backend.clear ();

            this.timer.pause ();
            assert_cmpstrv (backend.log, {
                "withdraw:timer"
            });
        }

        public void test_withdraw_notifications__stop ()
        {
            this.session_manager.advance_to_state (Ft.State.POMODORO);

            var backend = this.get_mock_backend ();
            backend.clear ();

            this.timer.reset ();
            assert_cmpstrv (backend.log, {
                "withdraw:timer"
            });
        }

        public void test_request_screen_overlay ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("screen-overlay", true);

            var backend = this.get_mock_backend ();

            var open_requested = false;

            this.notification_manager.request_screen_overlay_open.connect (() => {
                open_requested = true;
            });

            this.session_manager.advance_to_state (Ft.State.POMODORO);
            backend.clear ();

            this.session_manager.advance_to_state (Ft.State.SHORT_BREAK);
            assert_true (open_requested);
            assert_cmpstrv (backend.log, {});

            // Simulate overlay opened
            this.notification_manager.emit_screen_overlay_opened ();
            assert_cmpstrv (backend.log, {
                "withdraw:timer"
            });

            // Simulate overlay closed
            // Expect notification to be sent after a delay
            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            backend.clear ();
            backend.logged.connect ((entry) => {
                this.quit_main_loop ();
            });

            this.notification_manager.emit_screen_overlay_closed ();
            assert_cmpstrv (backend.log, {});

            assert_true (this.run_main_loop (500));
            assert_cmpstrv (backend.log, {
                @"send:timer:Short Break:4 minutes remaining"
            });
        }

        public void test_request_screen_overlay__extend ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("screen-overlay", true);

            var backend = this.get_mock_backend ();
            var open_requested = 0;

            this.notification_manager.request_screen_overlay_open.connect (() => {
                open_requested++;
            });

            this.session_manager.advance_to_state (Ft.State.POMODORO);
            backend.clear ();

            this.session_manager.advance_to_state (Ft.State.SHORT_BREAK);
            assert_cmpint (open_requested, GLib.CompareOperator.EQ, 1);
            assert_cmpstrv (backend.log, {});

            // Dismiss the overlay, then change only the break duration.
            this.notification_manager.emit_screen_overlay_opened ();
            this.notification_manager.emit_screen_overlay_closed ();

            backend.clear ();
            this.timer.extend (Ft.Interval.MINUTE);
            assert_cmpint (open_requested, GLib.CompareOperator.EQ, 1);
            assert_cmpstrv (backend.log, {
                "send:timer:Short Break:6 minutes remaining"
            });

            backend.clear ();
            this.timer.extend (-Ft.Interval.MINUTE);
            assert_cmpint (open_requested, GLib.CompareOperator.EQ, 1);
            assert_cmpstrv (backend.log, {
                "send:timer:Short Break:5 minutes remaining"
            });
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.NotificationManagerTest ()
    );
}
