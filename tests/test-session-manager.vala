/*
 * This file is part of focus-timer
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Tests
{
    private double EPSILON = 0.0001;


    public class SessionManagerTest : Tests.TestSuite
    {
        private Ft.Timer timer;

        private Ft.SessionTemplate session_template = Ft.SessionTemplate () {
            pomodoro_duration = 25 * Ft.Interval.MINUTE,
            short_break_duration = 5 * Ft.Interval.MINUTE,
            long_break_duration = 15 * Ft.Interval.MINUTE,
            cycles = 4
        };

        public SessionManagerTest ()
        {
            this.add_test ("new", this.test_new);
            this.add_test ("new_with_timer", this.test_new_with_timer);

            this.add_test ("set_current_session",
                           this.test_set_current_session);
            this.add_test ("set_current_session__while_entering_session",
                           this.test_set_current_session__while_entering_session);
            this.add_test ("set_current_session__while_leaving_session",
                           this.test_set_current_session__while_leaving_session);
            this.add_test ("set_current_session__while_entering_time_block",
                           this.test_set_current_session__while_entering_time_block);
            this.add_test ("set_current_session__while_leaving_time_block",
                           this.test_set_current_session__while_leaving_time_block);
            this.add_test ("set_current_session__null",
                           this.test_set_current_session__null);

            this.add_test ("set_current_time_block",
                           this.test_set_current_time_block);
            this.add_test ("set_current_time_block__while_entering_session",
                           this.test_set_current_time_block__while_entering_session);
            this.add_test ("set_current_time_block__while_leaving_session",
                           this.test_set_current_time_block__while_leaving_session);
            this.add_test ("set_current_time_block__while_entering_time_block",
                           this.test_set_current_time_block__while_entering_time_block);
            this.add_test ("set_current_time_block__while_leaving_time_block",
                           this.test_set_current_time_block__while_leaving_time_block);
            this.add_test ("set_current_time_block__null",
                           this.test_set_current_time_block__null);
            this.add_test ("set_current_time_block__with_new_session",
                           this.test_set_current_time_block__with_new_session);
            this.add_test ("set_current_time_block__in_progress",
                           this.test_set_current_time_block__in_progress);
            this.add_test ("set_current_time_block__in_progress_with_gaps",
                           this.test_set_current_time_block__in_progress_with_gaps);

            this.add_test ("set_scheduler",
                           this.test_set_scheduler);

            this.add_test ("advance__pomodoro", this.test_advance__pomodoro);
            this.add_test ("advance__paused_pomodoro", this.test_advance__paused_pomodoro);
            this.add_test ("advance__uncompleted_last_pomodoro", this.test_advance__uncompleted_last_pomodoro);
            this.add_test ("advance__uncompleted_long_break", this.test_advance__uncompleted_long_break);
            this.add_test ("advance__completed_long_break", this.test_advance__completed_long_break);
            this.add_test ("advance__uniform_breaks", this.test_advance__uniform_breaks);
            this.add_test ("advance_to_state__pomodoro", this.test_advance_to_state__pomodoro);
            this.add_test ("advance_to_state__short_break", this.test_advance_to_state__short_break);
            this.add_test ("advance_to_state__stopped", this.test_advance_to_state__stopped);
            this.add_test ("advance_to_state__extend_pomodoro", this.test_advance_to_state__extend_pomodoro);
            this.add_test ("advance_to_state__extend_short_break", this.test_advance_to_state__extend_short_break);
            this.add_test ("advance_to_state__extend_long_break", this.test_advance_to_state__extend_long_break);
            this.add_test ("advance_to_state__switch_breaks", this.test_advance_to_state__switch_breaks);
            this.add_test ("advance_to_state__confirm_advancement", this.test_advance_to_state__confirm_advancement);
            this.add_test ("advance_to_state__skip_advancement", this.test_advance_to_state__skip_advancement);
            this.add_test ("advance_to_state__completed_session", this.test_advance_to_state__completed_session);
            this.add_test ("advance_to_state__uncompleted_session", this.test_advance_to_state__uncompleted_session);

            this.add_test ("confirm_starting_break", this.test_confirm_starting_break);
            this.add_test ("confirm_starting_pomodoro", this.test_confirm_starting_pomodoro);

            this.add_test ("reset__empty_session", this.test_reset__empty_session);
            this.add_test ("reset", this.test_reset);
            this.add_test ("expire_session__after_timeout", this.test_expire_session__after_timeout);
            this.add_test ("expire_session__after_suspend", this.test_expire_session__after_suspend);

            this.add_test ("settings_change", this.test_settings_change);
        }

        public override void setup ()
        {
            Ft.Timestamp.freeze_to (2000000000 * Ft.Interval.SECOND);
            Ft.Timestamp.set_auto_advance (Ft.Interval.MICROSECOND);

            this.timer = new Ft.Timer ();
            Ft.Timer.set_default (this.timer);

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1500);
            settings.set_uint ("short-break-duration", 300);
            settings.set_uint ("long-break-duration", 900);
            settings.set_uint ("cycles", 4);
            settings.set_boolean ("confirm-starting-break", false);
            settings.set_boolean ("confirm-starting-pomodoro", false);
        }

        public override void teardown ()
        {
            var settings = Ft.get_settings ();
            settings.revert ();

            Ft.SessionManager.set_default (null);
            Ft.Timer.set_default (null);
        }

        public Ft.Session create_session (Ft.SessionManager session_manager)
        {
            var scheduler = session_manager.scheduler;
            var session = new Ft.Session.from_template (scheduler.session_template);
            session.@foreach (
                (time_block) => {
                    time_block.set_intended_duration (time_block.duration);
                    time_block.set_completion_time (scheduler.calculate_time_block_completion_time (time_block));
                }
            );

            return session;
        }


        /*
         * Tests for constructors
         */

        public void test_new ()
        {
            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1);
            settings.set_uint ("short-break-duration", 2);
            settings.set_uint ("long-break-duration", 3);
            settings.set_uint ("cycles", 5);

            var session_manager = new Ft.SessionManager ();

            assert_true (session_manager.timer == this.timer);
            assert_true (session_manager.timer.is_default ());
            assert_false (session_manager.timer.is_started ());
            assert_false (session_manager.timer.is_running ());

            assert_null (session_manager.current_session);
            assert_null (session_manager.current_time_block);

            assert_cmpvariant (
                session_manager.scheduler.session_template.to_variant (),
                Ft.SessionTemplate.with_defaults ().to_variant ()
            );
        }

        public void test_new_with_timer ()
        {
            var timer = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            assert_true (session_manager.timer == timer);
            assert_false (session_manager.timer.is_default ());
            assert_false (session_manager.timer.is_started ());
            assert_false (session_manager.timer.is_running ());

            assert_null (session_manager.current_session);
            assert_null (session_manager.current_time_block);
        }


        /*
         * Tests for current-session property
         */

        public void test_set_current_session ()
        {
            var timer           = this.timer;
            var session_manager = new Ft.SessionManager.with_timer (this.timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var resolve_state_emitted = 0;
            var state_changed_emitted = 0;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });
            timer.resolve_state.connect (() => { resolve_state_emitted++; });
            timer.state_changed.connect (() => { state_changed_emitted++; });

            var session_1 = new Ft.Session ();
            var session_2 = new Ft.Session.from_template (this.session_template);

            // Set empty session. Expect session to be set as current despite having no time-blocks.
            session_manager.current_session = session_1;
            assert_true (session_manager.current_session == session_1);
            assert_null (session_manager.current_time_block);
            assert_cmpstrv (signals, {"enter-session"});
            signals.resize (0);

            // Set non-empty session. Expect current-time-block to become null.
            session_manager.current_session = session_2;
            assert_true (session_manager.current_session == session_2);
            assert_null (session_manager.current_time_block);
            assert_cmpstrv (signals, {
                "leave-session",
                "enter-session"
            });
            assert_null (timer.user_data);
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.duration),
                new GLib.Variant.int64 (0 * Ft.Interval.SECOND)
            );
            assert_false (timer.is_started ());
            assert_false (timer.is_running ());
            signals.resize (0);

            // Set current-session with same session. Expect to it to be ignored.
            session_manager.current_session = session_manager.current_session;
            assert_cmpstrv (signals, {});

            // Set current-session to null.
            session_manager.current_session = null;
            assert_cmpstrv (signals, {
                "leave-session"
            });
            assert_null (timer.user_data);
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.duration),
                new GLib.Variant.int64 (0 * Ft.Interval.SECOND)
            );
            assert_false (timer.is_started ());
            assert_false (timer.is_running ());
            signals.resize (0);
        }

        public void test_set_current_session__while_entering_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);

            session_manager.enter_session.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_session = session_2;
                }
            });
            session_manager.current_session = session_1;
            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "enter-session",
                "leave-session",
                "enter-session"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 0);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 2);
        }

        public void test_set_current_session__while_leaving_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);
            var session_3 = new Ft.Session.from_template (this.session_template);
            session_manager.current_session = session_1;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            session_manager.leave_session.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_session = session_3;
                }
            });
            session_manager.current_session = session_2;
            assert_true (session_manager.current_session == session_3);
            assert_null (session_manager.current_time_block);
            assert_cmpstrv (signals, {
                "leave-session",
                "enter-session"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 0);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
        }

        public void test_set_current_session__while_entering_time_block ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);

            session_manager.current_time_block = session_1.get_first_time_block ();
            assert_cmpuint (session_manager.ref_count, GLib.CompareOperator.EQ, 1);

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });
            session_manager.enter_time_block.connect ((session_manager_, time_block) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_session = session_2;
                }
            });

            session_manager.current_time_block = session_1.get_nth_time_block (1);

            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "enter-time-block",
                "leave-time-block",
                "leave-session",
                "enter-session"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 2);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);

            wait_for_object_finalized ((owned) session_manager);
        }

        public void test_set_current_session__while_leaving_time_block ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);
            session_manager.current_time_block = session_1.get_first_time_block ();

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });
            session_manager.leave_time_block.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_session = session_2;
                }
            });

            session_manager.current_time_block = session_1.get_nth_time_block (1);
            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session",
                "enter-session"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);

            wait_for_object_finalized ((owned) session_manager);
        }

        public void test_set_current_session__null ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var session = new Ft.Session.from_template (this.session_template);
            session_manager.current_time_block = session.get_first_time_block ();
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            session_manager.current_session = null;
            assert_null (session_manager.current_time_block);
            assert_null (session_manager.current_session);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
            assert_false (timer.is_started ());

            wait_for_object_finalized ((owned) session_manager);
        }


        /*
         * Tests for current-time-block property
         */

        public void test_set_current_time_block ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            var session_1    = new Ft.Session.from_template (this.session_template);
            var time_block_1 = session_1.get_first_time_block ();
            var time_block_2 = session_1.get_next_time_block (time_block_1);

            var session_2    = new Ft.Session.from_template (this.session_template);
            var time_block_3 = session_2.get_first_time_block ();

            // Set empty session. Expect to set session as current, despite having no time-block yet.
            session_manager.current_time_block = time_block_1;
            assert_true (session_manager.current_time_block == time_block_1);
            assert_true (session_manager.current_session == session_1);
            assert_cmpstrv (signals, {
                "enter-session",
                "enter-time-block"
            });
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            signals.resize (0);
            notify_current_time_block_emitted = 0;
            notify_current_session_emitted = 0;

            // Set current time-block. Expect signals not to be emitted
            session_manager.current_time_block = session_manager.current_time_block;
            assert_cmpstrv (signals, {});
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 0);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 0);
            signals.resize (0);
            notify_current_time_block_emitted = 0;
            notify_current_session_emitted = 0;

            // Set current-time-block within same session.
            session_manager.current_time_block = time_block_2;
            assert_true (session_manager.current_time_block == time_block_2);
            assert_true (session_manager.current_session == session_1);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 0);
            signals.resize (0);
            notify_current_time_block_emitted = 0;
            notify_current_session_emitted = 0;

            // Set current-time-block with new session.
            session_manager.current_time_block = time_block_3;
            assert_true (session_manager.current_time_block == time_block_3);
            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session",
                "enter-session",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
            signals.resize (0);
            notify_current_time_block_emitted = 0;
            notify_current_session_emitted = 0;

            // Set current-time-block to null. Expect session not to be changed.
            session_manager.current_time_block = null;
            assert_null (session_manager.current_time_block);
            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "leave-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 0);
            signals.resize (0);
            notify_current_time_block_emitted = 0;
            notify_current_session_emitted = 0;
        }

        public void test_set_current_time_block__while_entering_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);

            session_manager.enter_session.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_time_block = session_2.get_first_time_block ();
                }
            });
            session_manager.current_session = session_1;
            assert_true (session_manager.current_session == session_2);
            assert_cmpstrv (signals, {
                "enter-session",
                "leave-session",
                "enter-session",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 2);
        }

        public void test_set_current_time_block__while_leaving_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            var session_1 = new Ft.Session.from_template (this.session_template);
            var session_2 = new Ft.Session.from_template (this.session_template);
            var session_3 = new Ft.Session.from_template (this.session_template);
            session_manager.current_session = session_1;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            session_manager.leave_session.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_time_block = session_3.get_first_time_block ();
                }
            });
            session_manager.current_session = session_2;
            assert_true (session_manager.current_time_block == session_3.get_first_time_block ());
            assert_cmpstrv (signals, {
                "leave-session",
                "enter-session",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
        }

        public void test_set_current_time_block__while_entering_time_block ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            var session = new Ft.Session.from_template (this.session_template);
            var time_block_1 = session.get_nth_time_block (0);
            var time_block_2 = session.get_nth_time_block (1);

            session_manager.enter_time_block.connect ((session_manager_, session) => {
                if (!handler_called) {
                    handler_called = true;
                    session_manager_.current_time_block = time_block_2;
                }
            });
            session_manager.current_time_block = time_block_1;
            assert_true (session_manager.current_time_block == time_block_2);
            assert_cmpstrv (signals, {
                "enter-session",
                "enter-time-block",
                "leave-time-block",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 2);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 1);
        }

        public void test_set_current_time_block__while_leaving_time_block ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var handler_called = false;

            var session = new Ft.Session.from_template (this.session_template);
            var time_block_1 = session.get_nth_time_block (0);
            var time_block_2 = session.get_nth_time_block (1);
            var time_block_3 = session.get_nth_time_block (2);

            session_manager.current_time_block = time_block_1;

            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect ((session_manager_, session) => {
                signals += "leave-time-block";

                if (!handler_called) {
                    assert_true (session_manager_.current_time_block == time_block_1);
                    handler_called = true;
                    session_manager_.current_time_block = time_block_3;
                }
            });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            // Expect switching to `time_block_2` to be interrupted
            session_manager.current_time_block = time_block_2;
            assert_true (session_manager.current_time_block == time_block_3);
            assert_cmpstrv (signals, {
                "leave-time-block",
                "enter-time-block"
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 0);
        }

        public void test_set_current_time_block__null ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals = new string[0];
            var notify_current_time_block_emitted = 0;
            var notify_current_session_emitted = 0;
            var session = new Ft.Session.from_template (this.session_template);
            session_manager.current_time_block = session.get_first_time_block ();
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.notify["current-session"].connect (() => {
                notify_current_session_emitted++;
            });
            session_manager.notify["current-time-block"].connect (() => {
                notify_current_time_block_emitted++;
            });

            session_manager.current_time_block = null;
            assert_null (session_manager.current_time_block);
            assert_true (session_manager.current_session == session);
            assert_cmpstrv (signals, {
                "leave-time-block",
            });
            assert_cmpint (notify_current_time_block_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpint (notify_current_session_emitted, GLib.CompareOperator.EQ, 0);
            assert_false (timer.is_started ());
        }

        public void test_set_current_time_block__with_new_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);
            var time_block      = session.get_first_time_block ();

            session_manager.current_time_block = time_block;

            assert_true (session_manager.current_session == session);
            assert_true (session_manager.current_time_block == time_block);
        }

        /**
         * Allow setting an in-progress time-block, as it's used by restore
         */
        public void test_set_current_time_block__in_progress ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            var time_block = session.get_first_time_block ();
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.notify["start-time"].connect (
                () => {
                    assert_not_reached ();
                });

            var timestamp = time_block.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (timestamp);

            var expected_start_time = time_block.start_time;
            var expected_elapsed = time_block.calculate_elapsed (timestamp);
            var expected_remaining = time_block.calculate_remaining (timestamp);
            var expected_timer_state = Ft.TimerState () {
                duration = time_block.duration,
                offset = 0,
                started_time = time_block.start_time,
                paused_time = Ft.Timestamp.UNDEFINED,
                finished_time = Ft.Timestamp.UNDEFINED,
                user_data = time_block
            };

            session_manager.current_time_block = time_block;

            assert_true (session_manager.current_session == session);
            assert_true (session_manager.current_time_block == time_block);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_null (time_block.get_last_gap ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (timestamp)),
                new GLib.Variant.int64 (expected_elapsed)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (timestamp)),
                new GLib.Variant.int64 (expected_remaining)
            );
            assert_cmpvariant (
                timer.state.to_variant (),
                expected_timer_state.to_variant ()
            );
        }

        public void test_set_current_time_block__in_progress_with_gaps ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            var time_block = session.get_first_time_block ();
            time_block.set_intended_duration (time_block.duration);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (time_block.start_time + Ft.Interval.MINUTE,
                                  time_block.start_time + 3 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_1);
            time_block.end_time += gap_1.duration;

            var gap_2 = new Ft.Gap.with_start_time (
                    time_block.start_time + 4 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);

            var timestamp = gap_2.start_time + 5 * Ft.Interval.MINUTE;

            var expected_start_time = time_block.start_time;
            var expected_elapsed = 2 * Ft.Interval.MINUTE;
            var expected_remaining = time_block.get_intended_duration () - expected_elapsed;
            var expected_cycles = session_manager.scheduler.session_template.cycles;
            var expected_timer_state = Ft.TimerState () {
                duration = time_block.get_intended_duration (),
                offset = gap_2.start_time - time_block.start_time - expected_elapsed,
                started_time = time_block.start_time,
                paused_time = gap_2.start_time,
                finished_time = Ft.Timestamp.UNDEFINED,
                user_data = time_block
            };

            Ft.Timestamp.freeze_to (timestamp);
            session_manager.current_time_block = time_block;

            assert_true (session_manager.current_session == session);
            assert_true (session_manager.current_time_block == time_block);
            assert_true (session_manager.current_gap == gap_2);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (timestamp)),
                new GLib.Variant.int64 (expected_elapsed)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (timestamp)),
                new GLib.Variant.int64 (expected_remaining)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_true (time_block.get_nth_gap (0) == gap_1);
            assert_true (time_block.get_nth_gap (1) == gap_2);
            assert_true (Ft.Timestamp.is_undefined (gap_2.end_time));
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                expected_cycles
            );

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (timestamp)),
                new GLib.Variant.int64 (expected_elapsed)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (timestamp)),
                new GLib.Variant.int64 (expected_remaining)
            );
            assert_cmpvariant (
                timer.state.to_variant (),
                expected_timer_state.to_variant ()
            );
        }


        /*
         * Tests for scheduler property
         */

        public void test_set_scheduler ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var signals = new string[0];
            var session = new Ft.Session.from_template (this.session_template);
            session_manager.current_time_block = session.get_first_time_block ();
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session_manager.notify["scheduler"].connect (() => { signals += "notify::scheduler"; });

            var scheduler_1 = session_manager.scheduler;
            session_manager.scheduler = scheduler_1;
            assert_true (session_manager.scheduler == scheduler_1);
            assert_cmpstrv (signals, {});

            var scheduler_2 = new Ft.SimpleScheduler.with_template (
                Ft.SessionTemplate () {
                    pomodoro_duration = 30 * Ft.Interval.MINUTE,
                    short_break_duration = 5 * Ft.Interval.MINUTE,
                    long_break_duration = 20 * Ft.Interval.MINUTE,
                    cycles = 4
                }
            );
            var expected_session = session_manager.current_session;
            var expected_time_block = session_manager.current_time_block;
            session_manager.scheduler = scheduler_2;
            assert_true (session_manager.scheduler == scheduler_2);
            assert_true (session_manager.current_session == expected_session);
            assert_true (session_manager.current_time_block == expected_time_block);
            assert_cmpstrv (signals, {
                "session-rescheduled",
                "notify::scheduler"
            });
        }


        /*
         * Tests for advance_* methods
         */

        public void test_advance__pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session_changed_emitted = 0;
            var signals = new string[0];

            // Start timer
            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var session = session_manager.current_session;
            var time_block_1 = session.get_nth_time_block (0);
            var time_block_2 = session.get_nth_time_block (1);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block_1))
            );
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);

            // Skip to a short-break after a minute
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance (now);
            assert_true (session_manager.current_session == session);
            assert_false (session_manager.current_time_block == time_block_1);
            assert_true (session_manager.current_time_block == time_block_2);
            assert_true (time_block_1.state == Ft.State.POMODORO);
            assert_true (time_block_2.state == Ft.State.SHORT_BREAK);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_true (time_block_2.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpstrv (signals, {
                "session-rescheduled",
                "leave-time-block",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Skipping while being paused should resume the timer
         */
        public void test_advance__paused_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;

            var pause_time = time_block.start_time + 3 * Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (pause_time);
            timer.pause (pause_time);
            assert_true (timer.is_paused ());

            var advance_time = pause_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (advance_time);
            session_manager.advance (advance_time);
            assert_false (timer.is_paused ());

            var gap = time_block.get_last_gap ();
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.start_time),
                new GLib.Variant.int64 (pause_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.end_time),
                new GLib.Variant.int64 (advance_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (advance_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_time_block.start_time),
                new GLib.Variant.int64 (advance_time)
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
        }

        /**
         * Skipping last pomodoro without completing it should schedule another cycle.
         * However, the number of visible cycles should not change.
         */
        public void test_advance__uncompleted_last_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var cycles = session.count_visible_cycles ();

            var long_break = session.get_last_time_block ();
            assert_true (long_break.state == Ft.State.LONG_BREAK);

            var last_pomodoro = session.get_previous_time_block (long_break);
            assert_true (last_pomodoro.state == Ft.State.POMODORO);

            session.@foreach (
                (time_block) => {
                    if (time_block != last_pomodoro && time_block != long_break) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            Ft.Timestamp.freeze_to (last_pomodoro.start_time);
            session_manager.current_time_block = last_pomodoro;

            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance (now);
            assert_true (last_pomodoro.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            var scheduled_break = session_manager.current_time_block;
            assert_nonnull (scheduled_break);
            assert_true (scheduled_break.state == Ft.State.SHORT_BREAK);
            assert_cmpvariant (
                new GLib.Variant.int64 (scheduled_break.duration),
                new GLib.Variant.int64 (this.session_template.short_break_duration)
            );

            var scheduled_pomodoro = session.get_next_time_block (scheduled_break);
            assert_nonnull (scheduled_pomodoro);
            assert_true (scheduled_pomodoro.state == Ft.State.POMODORO);

            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                cycles
            );
        }

        /**
         * Skipping a long break without completing it should add extra cycle.
         */
        public void test_advance__uncompleted_long_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var cycles = session.get_cycles ().length ();
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var time_block = session_manager.current_session.get_last_time_block ();
            Ft.Timestamp.freeze_to (time_block.start_time);
            session_manager.current_time_block = time_block;

            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance ();

            assert_true (time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_true (session_manager.current_session == session);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                cycles + 1U
            );
        }

        /**
         * Skipping completed long break should start new session.
         */
        public void test_advance__completed_long_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var time_block = session_manager.current_session.get_last_time_block ();
            Ft.Timestamp.freeze_to (time_block.start_time);
            session_manager.current_time_block = time_block;

            Ft.Timestamp.advance (12 * Ft.Interval.MINUTE);
            session_manager.advance ();

            assert_true (time_block.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_true (session_manager.current_session != session);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
        }

        /**
         * When has-uniform-breaks is true, expect POMODORO advance to a BREAK.
         */
        public void test_advance__uniform_breaks ()
        {
            var settings = Ft.get_settings ();
            settings.set_uint ("cycles", 1);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            // Start timer
            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var session = session_manager.current_session;
            var time_block_1 = session.get_nth_time_block (0);
            var time_block_2 = session.get_nth_time_block (1);

            assert_true (session_manager.has_uniform_breaks);
            assert_true (time_block_1.state == Ft.State.POMODORO);
            assert_true (time_block_2.state == Ft.State.BREAK);

            // Advance to a break once pomodoro finishes
            session_manager.advance (time_block_1.end_time);
            assert_true (session_manager.current_session == session);
            assert_false (session_manager.current_time_block == time_block_1);
            assert_true (session_manager.current_time_block == time_block_2);
            assert_true (time_block_1.state == Ft.State.POMODORO);
            assert_true (time_block_2.state == Ft.State.BREAK);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.duration),
                new GLib.Variant.int64 (session_manager.scheduler.session_template.short_break_duration)
            );
        }

        public void test_advance_to_state__pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            var time_block_1 = session.get_nth_time_block (1);  // Short break

            var session_changed_emitted = 0U;
            var signals = new string[0];

            session_manager.current_time_block = time_block_1;

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            var now = time_block_1.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            session_manager.advance_to_state (Ft.State.POMODORO, now);
            assert_true (session_manager.current_session == session);

            var time_block_2 = session_manager.current_time_block;
            assert_true (time_block_2.state == Ft.State.POMODORO);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block_2))
            );

            assert_true (time_block_1.session == session);
            assert_true (time_block_2.session == session);
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_true (time_block_2.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_true (timer.is_started ());
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1U);
        }

        public void test_advance_to_state__short_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);
            var time_block_1    = session.get_nth_time_block (0);

            var now = Ft.Timestamp.peek ();
            var session_changed_emitted = 0;
            var signals = new string[0];

            // Start a Ft.
            session_manager.current_time_block = time_block_1;

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Switch to a short-break.
            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance_to_state (Ft.State.BREAK, now);

            var time_block_2 = session.get_next_time_block (time_block_1);
            assert_true (time_block_2.state == Ft.State.SHORT_BREAK);
            assert_true (session_manager.current_session == session);
            assert_true (session_manager.current_time_block == time_block_2);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block_2))
            );
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_true (time_block_2.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_true (timer.is_started ());
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);

            var cycle = session_manager.get_current_cycle ();
            assert_cmpfloat (cycle.calculate_progress (now), GLib.CompareOperator.EQ, 0.0);
        }

        public void test_advance_to_state__stopped ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            var time_block_1 = session.get_first_time_block ();

            session_manager.current_time_block = time_block_1;

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance_to_state (Ft.State.STOPPED, now);

            assert_true (session_manager.current_session == session);
            assert_null (session_manager.current_time_block);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            var time_block_2 = session.get_next_time_block (time_block_1);
            assert_true (time_block_2.get_status () == Ft.TimeBlockStatus.SCHEDULED);
            assert_true (time_block_2.state == Ft.State.POMODORO);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (now)
            );

            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_false (timer.is_started ());
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
        }

        /**
         * Advance to pomodoro during ongoing Ft. Expect the time-block to be extended.
         */
        public void test_advance_to_state__extend_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.advance_to_state (Ft.State.POMODORO);

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;
            var expected_start_time = time_block.start_time;
            var expected_remaining_time = time_block.duration;
            var signals = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance_to_state (Ft.State.POMODORO, now);

            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.state == Ft.State.POMODORO);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_null (time_block.get_last_gap ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_true (timer.is_started ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (expected_remaining_time)
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "session-rescheduled",
                "state-changed",
            });

            // Extend once more. Expect it to increase cycle weight.
            now = time_block.end_time - 10 * Ft.Interval.SECOND;
            Ft.Timestamp.freeze_to (now);
            session_manager.advance_to_state (Ft.State.POMODORO, now);
            assert_null (time_block.get_last_gap ());
            assert_cmpfloat (
                session_manager.get_current_cycle ().get_weight (),
                GLib.CompareOperator.EQ,
                2.0
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles - 1U
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (expected_remaining_time)
            );
        }

        public void test_advance_to_state__extend_short_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.advance_to_state (Ft.State.SHORT_BREAK);

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;
            var expected_start_time = time_block.start_time;
            var expected_remaining_time = time_block.duration;
            var signals = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            // Extend the long break using .advance()
            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance_to_state (Ft.State.SHORT_BREAK, now);

            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.state == Ft.State.SHORT_BREAK);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_null (time_block.get_last_gap ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_true (timer.is_started ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (expected_remaining_time)
            );
            assert_cmpfloat_with_epsilon (
                timer.calculate_progress (now),
                1.0 / (1.0 + 5.0),
                0.001
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "session-rescheduled",
                "state-changed",
            });
        }

        public void test_advance_to_state__extend_long_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            // Create a session and mark all time blocks except the long break as completed.
            session_manager.ensure_session ();

            var session = session_manager.current_session;
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            // Start the long break.
            var time_block = session.get_last_time_block ();
            assert_true (time_block.state == Ft.State.LONG_BREAK);

            Ft.Timestamp.freeze_to (time_block.start_time);
            session_manager.current_time_block = time_block;

            var expected_start_time = time_block.start_time;
            var expected_remaining_time = time_block.duration;
            var expected_cycles = this.session_template.cycles;
            var signals = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            // Extend the long break using .advance()
            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance_to_state (Ft.State.LONG_BREAK, now);

            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.state == Ft.State.LONG_BREAK);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_null (time_block.get_last_gap ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                expected_cycles
            );
            assert_true (timer.is_started ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (expected_remaining_time)
            );
            assert_cmpfloat_with_epsilon (
                timer.calculate_progress (now),
                1.0 / (1.0 + 15.0),
                0.001
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "state-changed",
            });
        }

        public void test_advance_to_state__switch_breaks ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var time_block_1 = session.get_nth_time_block (0);  // Pomodoro
            var time_block_2 = session.get_nth_time_block (1);  // Short break

            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            // Start short break
            Ft.Timestamp.freeze_to (time_block_2.start_time);
            session_manager.current_time_block = time_block_2;

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            timer.state_changed.connect (() => {
                assert_true (session_manager.current_state == session_manager.current_time_block.state);
            });

            // Switch to a long break after a minute
            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            var expected_start_time = time_block_2.start_time;

            session_manager.advance_to_state (Ft.State.LONG_BREAK, now);

            assert_true (session_manager.current_time_block.state == Ft.State.LONG_BREAK);
            assert_true (session_manager.current_time_block == time_block_2);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (this.session_template.long_break_duration)
            );
            assert_cmpfloat_with_epsilon (
                timer.calculate_progress (now),
                1.0 / (1.0 + 15.0),
                0.001
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                1U
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "state-changed",
                "session-rescheduled"
            });

            // Switch back to a short break.
            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            signals = {};
            session_manager.advance_to_state (Ft.State.SHORT_BREAK, now);

            assert_true (session_manager.current_time_block.state == Ft.State.SHORT_BREAK);
            assert_true (session_manager.current_time_block == time_block_2);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_time_block.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (this.session_template.short_break_duration)
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                4U
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "state-changed",
                "session-rescheduled"
            });
        }

        /**
         * Manually advance to the same state as the upcoming time-block
         */
        public void test_advance_to_state__confirm_advancement ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);
            settings.set_boolean ("confirm-starting-pomodoro", true);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.advance_to_state (Ft.State.POMODORO);

            var session = session_manager.current_session;
            var pomodoro = session_manager.current_time_block;
            var short_break = session.get_next_time_block (pomodoro);

            Ft.Timestamp.freeze_to (pomodoro.end_time);
            timer.finish (pomodoro.end_time);

            // Confirm after 1 minute.
            var now = pomodoro.end_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            session_manager.advance_to_state (Ft.State.SHORT_BREAK, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.duration),
                new GLib.Variant.int64 (26 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );

            assert_true (session_manager.current_time_block == short_break);
            assert_cmpvariant (
                new GLib.Variant.int64 (short_break.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (5 * Ft.Interval.MINUTE)
            );
            assert_cmpfloat (
                timer.calculate_progress (now),
                GLib.CompareOperator.EQ,
                0.0
            );
        }

        /**
         * Manually extend current state instead of confirming advancement
         */
        public void test_advance_to_state__skip_advancement ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);
            settings.set_boolean ("confirm-starting-pomodoro", true);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            session_manager.advance_to_state (Ft.State.POMODORO);

            var pomodoro = session_manager.current_time_block;
            var expected_start_time = pomodoro.start_time;

            Ft.Timestamp.freeze_to (pomodoro.end_time);
            timer.finish (pomodoro.end_time);

            // Advance to a POMODORO after 1 minute.
            var now = pomodoro.end_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            session_manager.advance_to_state (Ft.State.POMODORO, now);

            assert_true (session_manager.current_time_block == pomodoro);
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.start_time),
                new GLib.Variant.int64 (expected_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_remaining (now)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpfloat_with_epsilon (
                timer.calculate_progress (now),
                (25.0 + 1.0) / (25.0 + 1.0 + 25.0),
                0.001
            );
        }

        /**
         * Skipping to a pomodoro when the session is completed should start a new session.
         */
        public void test_advance_to_state__completed_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var long_break = session.get_last_time_block ();
            Ft.Timestamp.freeze_to (long_break.start_time);
            session_manager.current_time_block = long_break;

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var now = long_break.get_completion_time ();
            Ft.Timestamp.freeze_to (now);
            session_manager.advance (now);

            var next_session = session_manager.current_session;
            var next_time_block = session_manager.current_time_block;

            assert_true (next_session != session);
            assert_nonnull (next_session);
            assert_nonnull (next_time_block);
            assert_true (next_time_block.state == Ft.State.POMODORO);
            assert_true (next_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpvariant (
                new GLib.Variant.int64 (next_time_block.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (timer.is_started ());
            assert_cmpuint (
                next_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session",
                "session-rescheduled",
                "enter-session",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
        }

        /**
         * Skipping to a pomodoro when a long break hasn't been completed should add extra cycle.
         */
        public void test_advance_to_state__uncompleted_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var session = new Ft.Session.from_template (this.session_template);
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var long_break = session.get_last_time_block ();
            Ft.Timestamp.freeze_to (long_break.start_time);
            session_manager.current_time_block = long_break;

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var now = long_break.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            session_manager.advance_to_state (Ft.State.POMODORO, now);
            assert_true (session_manager.current_session == session);

            var pomodoro = session_manager.current_time_block;
            assert_nonnull (pomodoro);
            assert_true (pomodoro.state == Ft.State.POMODORO);
            assert_true (pomodoro.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpvariant (
                new GLib.Variant.int64 (long_break.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (timer.is_started ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
        }

        public void test_confirm_starting_break ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            // Confirm after 1 minute.
            session_manager.advance_to_state (Ft.State.POMODORO);

            var session = session_manager.current_session;
            var time_block_1 = session_manager.current_time_block;
            time_block_1.notify["end-time"].connect (
                () => {
                    assert_true (
                        time_block_1.get_status () == Ft.TimeBlockStatus.IN_PROGRESS
                    );
                });

            var finished_time_1 = time_block_1.end_time;
            Ft.Timestamp.freeze_to (finished_time_1);
            timer.finish (finished_time_1);
            assert_true (timer.user_data == time_block_1);
            assert_true (timer.is_finished ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.finished_time),
                new GLib.Variant.int64 (finished_time_1)
            );

            var confirmation_time_1 = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance (confirmation_time_1);

            var time_block_2 = session_manager.current_time_block;
            assert_true (timer.user_data == time_block_2);
            assert_true (timer.is_started ());
            assert_false (timer.is_finished ());

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (confirmation_time_1)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.offset),
                new GLib.Variant.int64 (0)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (confirmation_time_1)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (confirmation_time_1)
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                4U
            );

            // Confirm after 30 minutes.
            session_manager.advance_to_state (Ft.State.POMODORO);

            var time_block_3 = session_manager.current_time_block;
            time_block_3.notify["end-time"].connect (
                () => {
                    assert_true (
                        time_block_3.get_status () == Ft.TimeBlockStatus.IN_PROGRESS
                    );
                });

            var finished_time_2 = time_block_3.end_time;
            Ft.Timestamp.freeze_to (finished_time_2);
            timer.finish (finished_time_2);
            assert_true (timer.user_data == time_block_3);
            assert_true (timer.is_finished ());

            var confirmation_time_2 = Ft.Timestamp.advance (30 * Ft.Interval.MINUTE);
            session_manager.advance (confirmation_time_2);

            var time_block_4 = session_manager.current_time_block;
            assert_true (timer.user_data == time_block_4);
            assert_true (timer.is_started ());

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (confirmation_time_2)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.offset),
                new GLib.Variant.int64 (0)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_3.end_time),
                new GLib.Variant.int64 (confirmation_time_2)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_4.start_time),
                new GLib.Variant.int64 (confirmation_time_2)
            );

            // Because we extended previous pomodoro, expect one less cycle
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                3U
            );
        }

        public void test_confirm_starting_pomodoro ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-pomodoro", true);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.advance_to_state (Ft.State.SHORT_BREAK);

            var time_block_1 = session_manager.current_time_block;
            time_block_1.notify["end-time"].connect (
                () => {
                    assert_true (
                        time_block_1.get_status () == Ft.TimeBlockStatus.IN_PROGRESS
                    );
                });

            var finished_time = session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (finished_time);
            timer.finish (finished_time);
            assert_true (timer.user_data == time_block_1);
            assert_true (timer.is_finished ());

            // Confirm after 1 minute.
            var confirmation_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_manager.advance (confirmation_time);

            var time_block_2 = session_manager.current_time_block;
            assert_true (time_block_2.state == Ft.State.POMODORO);
            assert_true (timer.user_data == time_block_2);
            assert_true (timer.is_started ());

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (confirmation_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.offset),
                new GLib.Variant.int64 (0)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (confirmation_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (confirmation_time)
            );
        }


        /*
         * Tests for handling session expiry
         */

        public void test_reset__empty_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);

            session_manager.current_session = session;

            // Reset should not do anything if session is scheduled / already empty.
            session_manager.reset ();
            assert_true (session_manager.current_session == session);
        }

        public void test_reset ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);

            var session_changed_emitted = 0;
            var notify_expiry_time_emitted = 0;
            var signals = new string[0];

            session_manager.current_time_block = session.get_first_time_block ();

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });
            session.notify["expiry-time"].connect (() => { notify_expiry_time_emitted++; });

            var timestamp = Ft.Timestamp.peek ();
            session_manager.reset (timestamp);
            assert_true (session_manager.current_session != session);
            assert_null (session_manager.current_time_block);
            assert_cmpvariant (
                new GLib.Variant.int64 (session.expiry_time),
                new GLib.Variant.int64 (timestamp)
            );
            assert_nonnull (session_manager.current_session);
            assert_true (session_manager.current_session.is_scheduled ());
            assert_cmpuint (
                session_manager.current_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_session.expiry_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session",
                "session-rescheduled",
                "enter-session",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (notify_expiry_time_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Check whether session expires after a timeout.
         *
         * In this test we manually set session `expiry-time`, which doesn't happen normally.
         */
        public void test_expire_session__after_timeout ()
        {
            Ft.Timestamp.thaw ();

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);
            var main_context    = GLib.MainContext.@default ();

            session_manager.current_session = session;
            session_manager.current_time_block = session.get_first_time_block ();

            var session_expired_emitted = 0;
            session_manager.session_expired.connect (() => {
                session_expired_emitted++;
            });

            var leave_session_emitted = 0;
            session_manager.leave_session.connect (() => {
                leave_session_emitted++;
            });

            var enter_session_emitted = 0;
            session_manager.enter_session.connect (() => {
                enter_session_emitted++;
            });

            var now = Ft.Timestamp.from_now ();
            var elapsed = 0U;
            var timeout_id = GLib.Timeout.add (100, () => {
                elapsed += 100;
                return GLib.Source.CONTINUE;
            });
            session.expiry_time = now + 500 * Ft.Interval.MILLISECOND;

            while (elapsed < 2000)
            {
                main_context.iteration (true);

                if (session_expired_emitted > 0) {
                    break;
                }
            }

            GLib.Source.remove (timeout_id);

            assert_cmpuint (session_expired_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (leave_session_emitted, GLib.CompareOperator.EQ, 1);
            assert_false (timer.is_started ());

            // Expect to a next session to be initialized.
            assert_cmpuint (enter_session_emitted, GLib.CompareOperator.EQ, 1);
            assert_nonnull (session_manager.current_session);
            assert_true (session_manager.current_session.is_scheduled ());
        }

        /**
         * Check whether session expires after after a mock system suspend.
         */
        public void test_expire_session__after_suspend ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.reset (now);
            assert_false (session_manager.current_session.is_scheduled ());

            var suspend_start = now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.suspending (suspend_start);

            var suspend_end = Ft.Timestamp.advance (session_manager.calculate_expiry_timeout ());
            timer.suspended (suspend_start, suspend_end);

            // Expect to a next session to be initialized.
            assert_nonnull (session_manager.current_session);
            assert_true (session_manager.current_session.is_scheduled ());
        }

        public void test_settings_change ()
        {
            var session_manager = new Ft.SessionManager ();
            var signals         = new string[0];
            var sesssion        = this.create_session (session_manager);
            session_manager.current_session = sesssion;
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 10);
            settings.set_uint ("short-break-duration", 20);
            settings.set_uint ("long-break-duration", 30);
            settings.set_uint ("cycles", 3);

            assert_false (session_manager.has_uniform_breaks);

            // Expect reschedule to be applied at idle.
            assert_cmpstrv (signals, {});

            Ft.Timestamp.advance (Ft.Interval.MINUTE);

            var main_context = GLib.MainContext.@default ();
            while (main_context.iteration (false));

            assert_cmpvariant (
                session_manager.scheduler.session_template.to_variant (),
                Ft.SessionTemplate.with_defaults ().to_variant ()
            );
            assert_cmpstrv (signals, {
                "session-rescheduled",
            });

            // Ensure reschedule done its job.
            var time_block_1 = sesssion.get_nth_time_block (0);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.get_intended_duration ()),
                new GLib.Variant.int64 (10 * Ft.Interval.SECOND)
            );

            var time_block_2 = sesssion.get_nth_time_block (1);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.get_intended_duration ()),
                new GLib.Variant.int64 (20 * Ft.Interval.SECOND)
            );

            // Check whether has-uniform-breaks gets updated
            settings.set_uint ("cycles", 1);
            assert_true (session_manager.has_uniform_breaks);
        }
    }


    /*
     * Tests for SessionManager, but with calls invoked by timer.
     */
    public class SessionManagerTimerTest : Tests.TestSuite
    {
        private Ft.Timer timer;

        private Ft.SessionTemplate session_template = Ft.SessionTemplate () {
            pomodoro_duration = 25 * Ft.Interval.MINUTE,
            short_break_duration = 5 * Ft.Interval.MINUTE,
            long_break_duration = 15 * Ft.Interval.MINUTE,
            cycles = 4
        };

        public SessionManagerTimerTest ()
        {
            // this.add_test ("timer_set_state", this.test_timer_set_state);
            this.add_test ("timer_set_duration", this.test_timer_set_duration);

            this.add_test ("timer_start__initialize_session", this.test_timer_start__initialize_session);
            this.add_test ("timer_start__ignore_call", this.test_timer_start__ignore_call);
            this.add_test ("timer_start__continue_session", this.test_timer_start__continue_session);
            this.add_test ("timer_start__expire_session", this.test_timer_start__expire_session);

            this.add_test ("timer_reset__mark_as_uncompleted", this.test_timer_reset__mark_as_uncompleted);
            this.add_test ("timer_reset__mark_as_completed", this.test_timer_reset__mark_as_completed);
            this.add_test ("timer_reset__paused", this.test_timer_reset__paused);
            this.add_test ("timer_reset__uncompleted_pomodoro", this.test_timer_reset__uncompleted_pomodoro);
            this.add_test ("timer_reset__completed_pomodoro", this.test_timer_reset__completed_pomodoro);
            this.add_test ("timer_reset__uncompleted_last_pomodoro", this.test_timer_reset__uncompleted_last_pomodoro);
            this.add_test ("timer_reset__completed_last_pomodoro", this.test_timer_reset__completed_last_pomodoro);
            this.add_test ("timer_reset__uncompleted_long_break", this.test_timer_reset__uncompleted_long_break);
            this.add_test ("timer_reset__completed_long_break", this.test_timer_reset__completed_long_break);
            this.add_test ("timer_reset__uncompleted_extra_pomodoro", this.test_timer_reset__uncompleted_extra_pomodoro);
            this.add_test ("timer_reset__completed_extra_pomodoro", this.test_timer_reset__completed_extra_pomodoro);
            this.add_test ("timer_reset__ignore_call", this.test_timer_reset__ignore_call);

            this.add_test ("timer_pause", this.test_timer_pause);
            this.add_test ("timer_pause__mark_interruption", this.test_timer_pause__mark_interruption);
            this.add_test ("timer_pause__unmark_interruption", this.test_timer_pause__unmark_interruption);
            this.add_test ("timer_resume", this.test_timer_resume);
            this.add_test ("timer_rewind", this.test_timer_rewind);
            this.add_test ("timer_rewind__multiple", this.test_timer_rewind__multiple);
            this.add_test ("timer_rewind__paused", this.test_timer_rewind__paused);
            this.add_test ("timer_rewind__paused_after_completion", this.test_timer_rewind__paused_after_completion);
            this.add_test ("timer_rewind__paused_multiple", this.test_timer_rewind__paused_multiple);

            this.add_test ("timer_finished__continuous", this.test_timer_finished__continuous);
            this.add_test ("timer_finished__wait_for_activity", this.test_timer_finished__wait_for_activity);
            this.add_test ("timer_finished__confirm", this.test_timer_finished__confirm);
            this.add_test ("timer_finished__extend", this.test_timer_finished__extend);

            // this.add_test ("timer_suspended", this.test_timer_suspended);
        }

        public override void setup ()
        {
            Ft.Timestamp.freeze_to (2000000000 * Ft.Interval.SECOND);
            Ft.Timestamp.set_auto_advance (Ft.Interval.MICROSECOND);

            this.timer = new Ft.Timer ();
            Ft.Timer.set_default (this.timer);

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1500);
            settings.set_uint ("short-break-duration", 300);
            settings.set_uint ("long-break-duration", 900);
            settings.set_uint ("cycles", 4);
            settings.set_boolean ("confirm-starting-break", false);
            settings.set_boolean ("confirm-starting-pomodoro", false);
        }

        public override void teardown ()
        {
            var settings = Ft.get_settings ();
            settings.revert ();

            Ft.Timer.set_default (null);
        }

        // public void test_timer_set_state ()
        // {
        // }

        public void test_timer_set_duration ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals         = new string[0];

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var session = session_manager.current_session;
            var time_block_1 = session.get_nth_time_block (0);
            var time_block_2 = session.get_nth_time_block (1);

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);

            var initial_duration = time_block_1.duration;
            var expected_duration = timer.duration + Ft.Interval.MINUTE;
            var expected_elapsed = timer.calculate_elapsed (now);

            timer.duration = expected_duration;

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (expected_elapsed)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.duration),
                new GLib.Variant.int64 (expected_duration)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.duration),
                new GLib.Variant.int64 (expected_duration)
            );
            assert_cmpvariant (
                time_block_1.get_intended_duration (),
                new GLib.Variant.int64 (initial_duration)
            );
            assert_true (session_manager.current_time_block == time_block_1);
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpstrv (signals, {
                "resolve-state",
                "session-rescheduled",
                "state-changed"
            });
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (time_block_1.start_time + expected_duration)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (time_block_1.end_time)
            );
        }

        /**
         * Check timer.start() call for a timer managed by session manager.
         *
         * Expect session manager to resolve timer state into a POMODORO time-block.
         */
        public void test_timer_start__initialize_session ()
        {
            var timer            = new Ft.Timer ();
            var session_manager  = new Ft.SessionManager.with_timer (timer);
            var session_template = session_manager.scheduler.session_template;

            var signals          = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            assert_null (session_manager.current_session);
            assert_false (timer.is_started ());
            assert_false (timer.is_running ());

            var now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.start (now);

            assert_nonnull (session_manager.current_session);
            assert_cmpuint (
                session_manager.current_session.get_cycles ().length (),
                GLib.CompareOperator.EQ,
                session_template.cycles
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_session.start_time),
                new GLib.Variant.int64 (timer.state.started_time)
            );
            assert_nonnull (session_manager.current_time_block);
            assert_true (session_manager.current_time_block == session_manager.current_session.get_first_time_block ());
            assert_true (session_manager.current_time_block.state == Ft.State.POMODORO);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_time_block.start_time),
                new GLib.Variant.int64 (timer.state.started_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_time_block.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpfloat_with_epsilon (session_manager.current_time_block.get_weight (), 1.0, EPSILON);
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.duration),
                new GLib.Variant.int64 (session_template.pomodoro_duration)
            );
            assert_true (timer.user_data == session_manager.current_time_block);
            assert_true (timer.is_started ());
            assert_true (timer.is_running ());
            assert_cmpstrv (signals, {
                "session-rescheduled",
                "enter-session",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
        }

        /**
         * Call timer.start() while timer is already running. Expect call to be ignored.
         */
        public void test_timer_start__ignore_call ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var expected_time_block = session_manager.current_time_block;
            var expected_state      = timer.state.copy ();
            var signals             = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.start ();

            assert_cmpvariant (
                timer.state.to_variant (),
                expected_state.to_variant ()
            );
            assert_true (session_manager.current_time_block == expected_time_block);
            assert_cmpstrv (signals, {});
        }

        /**
         * Expect to start a new pomodoro when starting the timer again.
         */
        public void test_timer_start__continue_session ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now             = Ft.Timestamp.peek ();
            timer.start (now);

            var time_block_1 = session_manager.current_session.get_nth_time_block (0);
            var session      = time_block_1.session;
            var signals      = new string[0];

            // Stop the timer
            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.reset (now);

            assert_nonnull (session_manager.current_session);
            assert_null (session_manager.current_time_block);
            assert_true (time_block_1.state == Ft.State.POMODORO);
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            // Start the timer again
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.start (now);

            var time_block_2 = session_manager.current_time_block;
            assert_true (time_block_2.state == Ft.State.POMODORO);
            assert_true (session.get_next_time_block (time_block_1) == time_block_2);
            assert_true (time_block_1.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_true (time_block_2.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpstrv (signals, {
                "session-rescheduled",
                "enter-time-block",
                "resolve-state",
                "state-changed"
            });
        }

        /**
         * Start timer after 1h from last time-block. Expect previous session to expire.
         */
        public void test_timer_start__expire_session ()
        {
            var timer                 = new Ft.Timer ();
            var session_manager       = new Ft.SessionManager.with_timer (timer);

            var now                   = Ft.Timestamp.peek ();
            var state_changed_emitted = 0;

            timer.start (now);
            assert_nonnull (session_manager.current_session);
            assert_nonnull (session_manager.current_time_block);
            assert_true (timer.is_started ());

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            var reset_time = now;
            timer.reset (now);
            assert_nonnull (session_manager.current_session);
            assert_null (session_manager.current_time_block);
            assert_false (timer.is_started ());

            now = Ft.Timestamp.advance (session_manager.current_session.expiry_time);
            Ft.Timestamp.freeze_to (now);

            var expired_session = session_manager.current_session;
            expired_session.changed.connect (() => { state_changed_emitted++; });
            assert_true (expired_session.is_expired (now));

            timer.start (now);
            assert_false (session_manager.current_session == expired_session);
            assert_nonnull (session_manager.current_time_block);
            assert_true (timer.is_started ());
            assert_cmpint (state_changed_emitted, GLib.CompareOperator.EQ, 1);
            assert_cmpvariant (
                new GLib.Variant.int64 (expired_session.end_time),
                new GLib.Variant.int64 (reset_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_session.start_time),
                new GLib.Variant.int64 (now)
            );
        }

        public void test_timer_reset__mark_as_uncompleted ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var time_block = session_manager.current_time_block;
            var session    = session_manager.current_session;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_nonnull (session_manager.current_session);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_cmpuint (
                session_manager.current_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed",
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        public void test_timer_reset__mark_as_completed ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var time_block = session_manager.current_time_block;
            var session    = session_manager.current_session;

            var session_changed_emitted = 0;
            var signals    = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            now = time_block.end_time - Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_cmpuint (
                session_manager.current_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed",
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Ensure that pausing the timer will not affect whether time-block will be marked as completed.
         */
        public void test_timer_reset__paused ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var time_block = session_manager.current_time_block;
            var completion_time = time_block.get_completion_time ();

            now = completion_time - Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.pause (now);

            var signals = new string[0];
            var gaps_count = 0U;
            var gap_start_time = Ft.Timestamp.UNDEFINED;
            var gap_end_time = Ft.Timestamp.UNDEFINED;
            var expected_gap_start_time = now;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            now = completion_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_cmpuint (
                session_manager.current_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );

            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_start_time),
                new GLib.Variant.int64 (expected_gap_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed",
            });
        }

        /**
         * Stopping a uncompleted Ft.
         *
         * Expect a pomodoro to be scheduled next and the number of visible cycles to not change.
         */
        public void test_timer_reset__uncompleted_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var session = session_manager.current_session;
            var pomodoro = session_manager.current_time_block;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer before pomodoro is completed
            var now = pomodoro.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_true (pomodoro.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );

            // After stopping pomodoro, another pomodoro should be scheduled
            var scheduled_pomodoro = session.get_next_time_block (pomodoro);
            assert_nonnull (scheduled_pomodoro);
            assert_true (scheduled_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            // Visible cycles should remain the same
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stopping a completed Ft.
         *
         * Expect a pomodoro to be scheduled next and the number of visible cycles to not change.
         */
        public void test_timer_reset__completed_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var session = session_manager.current_session;
            var pomodoro = session_manager.current_time_block;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer after pomodoro is completed
            var now = pomodoro.get_completion_time () + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_true (pomodoro.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );

            // After stopping pomodoro, another pomodoro should be scheduled
            var scheduled_pomodoro = session.get_next_time_block (pomodoro);
            assert_nonnull (scheduled_pomodoro);
            assert_true (scheduled_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            // Visible cycles should remain the same
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stopping last pomodoro should schedule another cycle.
         *
         * Expect a pomodoro to be scheduled next and the number of visible cycles to not change.
         */
        public void test_timer_reset__uncompleted_last_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var long_break = session.get_last_time_block ();
            assert_true (long_break.state == Ft.State.LONG_BREAK);

            var last_pomodoro = session.get_previous_time_block (long_break);
            assert_true (last_pomodoro.state == Ft.State.POMODORO);

            session.@foreach (
                (time_block) => {
                    if (time_block != last_pomodoro && time_block != long_break) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            Ft.Timestamp.freeze_to (last_pomodoro.start_time);
            session_manager.current_time_block = last_pomodoro;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer before pomodoro is completed
            var now = last_pomodoro.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_true (last_pomodoro.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_cmpvariant (
                new GLib.Variant.int64 (last_pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );

            // After stopping pomodoro, another pomodoro should be scheduled
            var scheduled_pomodoro = session.get_next_time_block (last_pomodoro);
            assert_nonnull (scheduled_pomodoro);
            assert_true (scheduled_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            // Visible cycles should remain the same
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stopping a completed last pomodoro should schedule extra cycle.
         *
         * When the last pomodoro (the one before long break) is completed and then stopped,
         * an extra cycle should be scheduled so that the user can take a long break later.
         */
        public void test_timer_reset__completed_last_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var long_break = session.get_last_time_block ();
            assert_true (long_break.state == Ft.State.LONG_BREAK);

            var last_pomodoro = session.get_previous_time_block (long_break);
            assert_true (last_pomodoro.state == Ft.State.POMODORO);

            session.@foreach (
                (time_block) => {
                    if (time_block != last_pomodoro && time_block != long_break) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            Ft.Timestamp.freeze_to (last_pomodoro.start_time);
            session_manager.current_time_block = last_pomodoro;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer after pomodoro is completed
            var now = last_pomodoro.get_completion_time () + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_null (session_manager.current_time_block);
            assert_true (last_pomodoro.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_cmpvariant (
                new GLib.Variant.int64 (last_pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );

            // After stopping pomodoro, another pomodoro should be scheduled.
            // Session gets completed only after completing a long-break.
            var scheduled_pomodoro = session.get_next_time_block (last_pomodoro);
            assert_nonnull (scheduled_pomodoro);
            assert_true (scheduled_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            // Visible cycles should increase by one
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stop a session with completed all cycles, without completing a long-break.
         *
         * Expect an extra cycle.
         */
        public void test_timer_reset__uncompleted_long_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var session         = new Ft.Session.from_template (this.session_template);
            var long_break      = session.get_last_time_block ();

            session.@foreach (
                (time_block) => {
                    time_block.set_completion_time (time_block.end_time);

                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );
            session_manager.scheduler.ensure_session_meta (session);

            Ft.Timestamp.freeze_to (long_break.start_time);
            session_manager.current_time_block = long_break;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            var now = long_break.start_time + Ft.Interval.MINUTE;
            timer.reset (now);
            assert_true (long_break.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Hit stop after completing a long-break.
         *
         * Expect a new session to be initialized.
         */
        public void test_timer_reset__completed_long_break ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            var long_break = session.get_last_time_block ();

            session.@foreach (
                (time_block) => {
                    time_block.set_status (time_block.state != Ft.State.LONG_BREAK
                            ? Ft.TimeBlockStatus.COMPLETED
                            : Ft.TimeBlockStatus.IN_PROGRESS);
                }
            );

            Ft.Timestamp.freeze_to (long_break.start_time);
            session_manager.current_time_block = long_break;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            var now = long_break.get_completion_time () + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_true (session_manager.current_session != session);
            assert_nonnull (session_manager.current_session);
            assert_cmpuint (
                session_manager.current_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpstrv (signals, {
                "leave-time-block",
                "leave-session",
                "session-rescheduled",
                "enter-session",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stopping an uncompleted extra Ft.
         *
         * Expect a pomodoro to be scheduled next and the number of visible cycles to not change -
         * remain one extra above template.
         */
        public void test_timer_reset__uncompleted_extra_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var scheduler       = session_manager.scheduler;

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var uncompleted_long_break = session.get_last_time_block ();
            uncompleted_long_break.duration = Ft.Interval.MINUTE;
            uncompleted_long_break.set_status (Ft.TimeBlockStatus.UNCOMPLETED);

            var extra_pomodoro = new Ft.TimeBlock (Ft.State.POMODORO);
            extra_pomodoro.set_time_range (session.end_time,
                                           session.end_time + 25 * Ft.Interval.MINUTE);
            extra_pomodoro.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
            session.append (extra_pomodoro);

            var long_break = new Ft.TimeBlock (Ft.State.LONG_BREAK);
            long_break.set_time_range (session.end_time,
                                       session.end_time + 15 * Ft.Interval.MINUTE);
            long_break.set_status (Ft.TimeBlockStatus.SCHEDULED);
            session.append (long_break);

            scheduler.ensure_session_meta (session);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );

            var extra_cycle = session.get_cycles ().nth_data (4U);
            assert_true (extra_cycle.is_visible ());

            Ft.Timestamp.freeze_to (extra_pomodoro.start_time);
            session_manager.current_time_block = extra_pomodoro;
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer before extra pomodoro got completed
            var now = extra_pomodoro.start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_cmpvariant (
                new GLib.Variant.int64 (extra_pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (extra_pomodoro.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);
            assert_cmpfloat (
                extra_pomodoro.get_weight (),
                GLib.CompareOperator.EQ,
                0.0
            );
            assert_false (extra_cycle.is_visible ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );

            var scheduled_extra_pomodoro = session.get_next_time_block (extra_pomodoro);
            assert_true (scheduled_extra_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_extra_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Stopping a completed extra pomodoro
         *
         * When stopping a pomodoro always expect a pomodoro to be scheduled next.
         */
        public void test_timer_reset__completed_extra_pomodoro ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var scheduler       = session_manager.scheduler;

            session_manager.ensure_session ();

            var session = session_manager.current_session;
            session.@foreach (
                (time_block) => {
                    if (time_block.state != Ft.State.LONG_BREAK) {
                        time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
                    }
                }
            );

            var uncompleted_long_break = session.get_last_time_block ();
            uncompleted_long_break.duration = Ft.Interval.MINUTE;
            uncompleted_long_break.set_status (Ft.TimeBlockStatus.UNCOMPLETED);

            var extra_pomodoro = new Ft.TimeBlock (Ft.State.POMODORO);
            extra_pomodoro.set_time_range (session.end_time,
                                           session.end_time + 25 * Ft.Interval.MINUTE);
            extra_pomodoro.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
            session.append (extra_pomodoro);

            var long_break = new Ft.TimeBlock (Ft.State.LONG_BREAK);
            long_break.set_time_range (session.end_time,
                                       session.end_time + 15 * Ft.Interval.MINUTE);
            long_break.set_status (Ft.TimeBlockStatus.SCHEDULED);
            session.append (long_break);

            scheduler.ensure_session_meta (session);
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 1U
            );

            var extra_cycle = session.get_cycles ().nth_data (4U);
            assert_true (extra_cycle.is_visible ());

            Ft.Timestamp.freeze_to (extra_pomodoro.start_time);
            session_manager.current_time_block = extra_pomodoro;

            var signals = new string[0];
            var session_changed_emitted = 0;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            // Stop the timer after extra pomodoro is completed
            var completion_time = extra_pomodoro.get_completion_time ();
            var now = completion_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (now);
            timer.reset (now);

            assert_cmpvariant (
                new GLib.Variant.int64 (extra_pomodoro.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_true (extra_pomodoro.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_true (extra_cycle.is_visible ());

            // After stopping completed extra pomodoro, another extra pomodoro should be scheduled
            var scheduled_extra_pomodoro = session.get_next_time_block (extra_pomodoro);
            assert_nonnull (scheduled_extra_pomodoro);
            assert_true (scheduled_extra_pomodoro.state == Ft.State.POMODORO);
            assert_true (scheduled_extra_pomodoro.get_status () == Ft.TimeBlockStatus.SCHEDULED);

            // Visible cycles should increase by one (another extra cycle added)
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles + 2U
            );

            assert_cmpstrv (signals, {
                "leave-time-block",
                "session-rescheduled",
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1);
        }

        /**
         * Timer.reset() should be ignored when there is no current-time-block.
         */
        public void test_timer_reset__ignore_call ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var signals         = new string[0];

            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer.reset ();

            assert_null (session_manager.current_session);
            assert_null (session_manager.current_time_block);
            assert_cmpstrv (signals, {});
        }

        public void test_timer_pause ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var started_time = Ft.Timestamp.peek ();
            timer.start (started_time);

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            var session_changed_emitted = 0U;
            session.changed.connect (() => { session_changed_emitted++; });

            var paused_time = started_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (paused_time);
            var expected_cycle_progress = cycle.calculate_progress (paused_time);
            timer.pause (paused_time);
            assert_true (timer.is_paused ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.paused_time),
                new GLib.Variant.int64 (paused_time)
            );

            assert_nonnull (session_manager.current_gap);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_gap.start_time),
                new GLib.Variant.int64 (paused_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_gap.end_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (paused_time)),
                new GLib.Variant.int64 (Ft.Interval.MINUTE)
            );
            assert_true (cycle.is_visible ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (paused_time),
                expected_cycle_progress,
                EPSILON
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1U);

            // Pause after the completion_time.
            Ft.Timestamp.advance (5 * Ft.Interval.SECOND);
            timer.resume ();
            signals = {};
            session_changed_emitted = 0U;

            var completion_time = time_block.get_completion_time ();
            Ft.Timestamp.freeze_to (completion_time);
            timer.pause (completion_time);
            assert_true (timer.is_paused ());

            assert_nonnull (session_manager.current_gap);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_gap.start_time),
                new GLib.Variant.int64 (completion_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_gap.end_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_true (cycle.is_visible ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (completion_time), 1.0, EPSILON);
            assert_cmpvariant (
                new GLib.Variant.int64 (session.expiry_time),
                new GLib.Variant.int64 (completion_time + session_manager.calculate_expiry_timeout ())
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1U);
        }

        /**
         * Pausing the timer during a pomodoro should mark the created gap as an INTERRUPTION.
         */
        public void test_timer_pause__mark_interruption ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);
            var timer_action_group = new Ft.TimerActionGroup.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer_action_group.activate_action ("start", null);

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer_action_group.activate_action ("pause", null);

            var time_block = session_manager.current_time_block;
            var gap = time_block.get_last_gap ();

            assert_nonnull (gap);
            assert_true (gap.has_flag (Ft.GapFlags.INTERRUPTION));
            assert_true (Ft.Timestamp.is_defined (gap.start_time));
            assert_false (Ft.Timestamp.is_defined (gap.end_time));

            // Resume the timer; expect INTERRUPTION to be preserved
            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer_action_group.activate_action ("resume", null);

            gap = time_block.get_last_gap ();
            assert_true (gap.has_flag (Ft.GapFlags.INTERRUPTION));
            assert_true (Ft.Timestamp.is_defined (gap.end_time));
        }

        /**
         * Pausing then stopping should invalidate the INTERRUPTION by changing gap type to OTHER.
         */
        public void test_timer_pause__unmark_interruption ()
        {
            var timer              = new Ft.Timer ();
            var session_manager    = new Ft.SessionManager.with_timer (timer);
            var timer_action_group = new Ft.TimerActionGroup.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer_action_group.activate_action ("start", null);

            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer_action_group.activate_action ("pause", null);

            var time_block = session_manager.current_time_block;
            var gap = time_block.get_last_gap ();
            assert_nonnull (gap);
            assert_true (gap.has_flag (Ft.GapFlags.INTERRUPTION));
            assert_true (Ft.Timestamp.is_defined (gap.start_time));
            assert_false (Ft.Timestamp.is_defined (gap.end_time));

            // Stop the timer; expect the interruption to be invalidated
            now = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            timer_action_group.activate_action ("reset", null);

            assert_null (session_manager.current_time_block);
            assert_false (gap.has_flag (Ft.GapFlags.INTERRUPTION));
            assert_true (Ft.Timestamp.is_defined (gap.end_time));
        }

        public void test_timer_resume ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var start_time = Ft.Timestamp.peek ();
            timer.start (start_time);

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();

            var pause_time = start_time + 3 * Ft.Interval.MINUTE;
            var expected_time_block_start_time = time_block.start_time;
            var expected_time_block_end_time = time_block.end_time + Ft.Interval.MINUTE;
            var expected_gap_start_time = pause_time;
            var expected_gap_end_time = pause_time + Ft.Interval.MINUTE;
            var expected_cycle_progress = cycle.calculate_progress (pause_time);

            timer.pause (pause_time);
            assert_true (timer.is_paused ());

            var signals = new string[0];
            var session_changed_emitted = 0U;
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });
            session.changed.connect (() => { session_changed_emitted++; });

            var resume_time = expected_gap_end_time;
            Ft.Timestamp.freeze_to (resume_time);
            timer.resume (resume_time);
            assert_false (timer.is_paused ());
            assert_null (session_manager.current_gap);

            var gap = session_manager.current_time_block.get_last_gap ();
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.start_time),
                new GLib.Variant.int64 (expected_gap_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.end_time),
                new GLib.Variant.int64 (expected_gap_end_time)
            );

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (resume_time)),
                new GLib.Variant.int64 (3 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_time_block_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (expected_time_block_end_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block))
            );
            assert_true (cycle.is_visible ());
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (resume_time),
                expected_cycle_progress,
                EPSILON
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "session-rescheduled",
                "state-changed"
            });
            assert_cmpuint (session_changed_emitted, GLib.CompareOperator.EQ, 1U);
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_session.expiry_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
        }

        public void test_timer_rewind ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var start_time = Ft.Timestamp.peek ();
            timer.start (start_time);

            var rewind_time = start_time + 3 * Ft.Interval.MINUTE;

            var session = session_manager.current_session;
            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();

            var expected_time_block_start_time = time_block.start_time;
            var expected_time_block_end_time = time_block.end_time + Ft.Interval.MINUTE;
            var expected_time_block_completion_time = time_block.get_completion_time () + Ft.Interval.MINUTE;
            var expected_gap_end_time = rewind_time;
            var expected_gap_start_time = expected_gap_end_time - Ft.Interval.MINUTE;
            var expected_cycle_progress = cycle.calculate_progress (expected_gap_start_time);

            var signals = new string[0];
            timer.resolve_state.connect (() => { signals += "resolve-state"; });
            timer.state_changed.connect (() => { signals += "state-changed"; });
            session_manager.enter_session.connect (() => { signals += "enter-session"; });
            session_manager.enter_time_block.connect (() => { signals += "enter-time-block"; });
            session_manager.leave_session.connect (() => { signals += "leave-session"; });
            session_manager.leave_time_block.connect (() => { signals += "leave-time-block"; });
            session_manager.session_rescheduled.connect (() => { signals += "session-rescheduled"; });

            timer.rewind (Ft.Interval.MINUTE, rewind_time);
            assert_false (timer.is_paused ());
            assert_true (timer.is_running ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (rewind_time)),
                new GLib.Variant.int64 (2 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (expected_time_block_completion_time)
            );

            var gap = session_manager.current_time_block.get_last_gap ();
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.start_time),
                new GLib.Variant.int64 (expected_gap_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.end_time),
                new GLib.Variant.int64 (expected_gap_end_time)
            );

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (expected_time_block_start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (expected_time_block_end_time)
            );
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (rewind_time),
                expected_cycle_progress,
                EPSILON
            );
            assert_cmpuint (
                session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                this.session_template.cycles
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session.expiry_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpstrv (signals, {
                "resolve-state",
                "session-rescheduled",
                "state-changed"
            });
        }

        /**
         * Use rewind several times.
         *
         * When gaps overlay, expect them to be merged.
         */
        public void test_timer_rewind__multiple ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();
            var gaps_count = 0U;
            var gap_start_time = Ft.Timestamp.UNDEFINED;
            var gap_end_time = Ft.Timestamp.UNDEFINED;

            // First rewind.
            now = Ft.Timestamp.advance (3 * Ft.Interval.MINUTE);

            timer.rewind (Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (2 * Ft.Interval.MINUTE)
            );
            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_start_time),
                new GLib.Variant.int64 (time_block.start_time + 2 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 2.0 / 18.75, EPSILON);

            // Second rewind.
            gaps_count = 0;
            gap_start_time = Ft.Timestamp.UNDEFINED;
            gap_end_time = Ft.Timestamp.UNDEFINED;
            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (65 * Ft.Interval.SECOND)
            );
            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_start_time),
                new GLib.Variant.int64 (time_block.start_time + 65 * Ft.Interval.SECOND)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block))
            );
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (now),
                65.0 / (18.75 * 60.00),
                EPSILON
            );

            // Third rewind.
            gaps_count = 0;
            gap_start_time = Ft.Timestamp.UNDEFINED;
            gap_end_time = Ft.Timestamp.UNDEFINED;
            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (5 * Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (0)
            );
            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_start_time),
                new GLib.Variant.int64 (time_block.start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (session_manager.scheduler.calculate_time_block_completion_time (time_block))
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 0.0, EPSILON);
        }

        public void test_timer_rewind__paused ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            now = Ft.Timestamp.advance (5 * Ft.Interval.MINUTE);
            timer.pause (now);

            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();
            var gaps_count = 0U;
            var expected_completion_time = time_block.get_completion_time () + Ft.Interval.MINUTE;

            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (Ft.Interval.MINUTE, now);
            assert_true (timer.is_paused ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (4 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (expected_completion_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.current_session.expiry_time),
                new GLib.Variant.int64 (now + session_manager.calculate_expiry_timeout ())
            );

            time_block.foreach_gap ((gap) => {
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 2);
            assert_cmpvariant (
                new GLib.Variant.int64 (cycle.get_completion_time ()),
                new GLib.Variant.int64 (expected_completion_time)
            );
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (timer.state.paused_time),
                4.0 / 18.75,
                EPSILON
            );
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());
        }

        public void test_timer_rewind__paused_after_completion ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            now = Ft.Timestamp.advance (22 * Ft.Interval.MINUTE);
            timer.pause (now);

            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();
            var expected_completion_time = time_block.get_completion_time ();

            // First rewind.
            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (Ft.Interval.MINUTE, now);
            assert_true (timer.is_paused ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (21 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (expected_completion_time)
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 1.0, EPSILON);
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());

            // Second rewind.
            timer.rewind (25 * Ft.Interval.MINUTE, now);
            assert_true (timer.is_paused ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (0)
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 0.0 / 20.0, EPSILON);
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());
        }

        public void test_timer_rewind__paused_multiple ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var now = Ft.Timestamp.peek ();
            timer.start (now);

            now = Ft.Timestamp.advance (3 * Ft.Interval.MINUTE);
            timer.pause (now);

            var time_block = session_manager.current_time_block;
            var cycle = session_manager.get_current_cycle ();
            var gaps_count = 0U;
            var gap_start_time = Ft.Timestamp.UNDEFINED;
            var gap_end_time = Ft.Timestamp.UNDEFINED;
            var original_completion_time = time_block.get_completion_time ();

            // First rewind.
            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (2 * Ft.Interval.MINUTE)
            );
            time_block.foreach_gap ((gap) => {
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 2);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (original_completion_time + Ft.Interval.MINUTE)
            );
            assert_cmpfloat_with_epsilon (
                cycle.calculate_progress (timer.state.paused_time),
                2.0 / 18.75,
                EPSILON
            );
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());

            // Second rewind.
            gaps_count = 0;
            gap_start_time = Ft.Timestamp.UNDEFINED;
            gap_end_time = Ft.Timestamp.UNDEFINED;
            now = Ft.Timestamp.advance (5 * Ft.Interval.SECOND);

            timer.rewind (Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (Ft.Interval.MINUTE)
            );
            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 2);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (original_completion_time + 2 * Ft.Interval.MINUTE)
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 1.0 / 18.75, EPSILON);
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());

            // Third rewind.
            gaps_count = 0;
            gap_start_time = Ft.Timestamp.UNDEFINED;
            gap_end_time = Ft.Timestamp.UNDEFINED;
            now = Ft.Timestamp.advance (45 * Ft.Interval.MINUTE);

            timer.rewind (5 * Ft.Interval.MINUTE, now);

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.calculate_elapsed (now)),
                new GLib.Variant.int64 (0)
            );
            assert_true (session_manager.current_time_block == time_block);
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.foreach_gap ((gap) => {
                gap_start_time = gap.start_time;
                gap_end_time = gap.end_time;
                gaps_count++;
            });
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.get_completion_time ()),
                new GLib.Variant.int64 (original_completion_time + 3 * Ft.Interval.MINUTE)
            );
            assert_cmpfloat_with_epsilon (cycle.calculate_progress (now), 0.0, EPSILON);
            assert_cmpfloat_with_epsilon (cycle.get_weight (), 1.0, EPSILON);
            assert_true (cycle.is_visible ());
        }

        public void test_timer_finished__continuous ()
        {
            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            timer.start ();

            var state_changed_call_count = 0;
            var finished_call_count = 0;
            var state_1 = Ft.TimerState ();
            var state_2 = Ft.TimerState ();

            timer.finished.connect (() => {
                finished_call_count++;
            });

            timer.state_changed.connect ((current_state, previous_state) => {
                if (state_changed_call_count == 0) {
                    state_1 = current_state;
                }

                if (state_changed_call_count == 1) {
                    assert_true (previous_state.equals (state_1));
                    state_2 = current_state;
                }

                state_changed_call_count++;
            });

            var finished_time = session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (finished_time);
            timer.finish (finished_time);

            assert_cmpuint (state_changed_call_count, GLib.CompareOperator.EQ, 2);
            assert_cmpuint (finished_call_count, GLib.CompareOperator.EQ, 1);

            assert_true (state_1.is_finished ());
            assert_false (state_2.is_finished ());

            assert_cmpvariant (
                new GLib.Variant.int64 (state_1.finished_time),
                new GLib.Variant.int64 (finished_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (state_2.started_time),
                new GLib.Variant.int64 (finished_time)
            );
        }

        public void test_timer_finished__wait_for_activity ()
        {
            var idle_monitor    = new Ft.IdleMonitor ();
            assert_true (idle_monitor.provider is Ft.DummyIdleMonitorProvider);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            session_manager.advance_to_state (Ft.State.SHORT_BREAK);

            var time_block_1 = session_manager.current_time_block;
            var finished_time = time_block_1.end_time;
            Ft.Timestamp.freeze_to (finished_time);
            timer.finish (finished_time);

            var time_block_2 = session_manager.current_time_block;
            assert_true (time_block_2.state == Ft.State.POMODORO);
            assert_true (timer.user_data == time_block_2);
            assert_false (timer.is_started ());
            assert_false (timer.is_finished ());

            // Simulate inactivity of 1 minute.
            var activity_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            idle_monitor.provider.became_active ();

            assert_true (session_manager.current_time_block == time_block_2);
            assert_true (timer.user_data == time_block_2);
            assert_true (timer.is_started ());

            // Expect previous time-block to be extended by the inactivity time.
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (activity_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.offset),
                new GLib.Variant.int64 (0)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (activity_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (activity_time)
            );
        }

        /**
         * Test for `AdvancementMode.CONFIRM`
         */
        public void test_timer_finished__confirm ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);
            settings.set_boolean ("confirm-starting-pomodoro", true);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var confirm_advancement_call_count = 0;
            session_manager.confirm_advancement.connect (() => {
                confirm_advancement_call_count++;
            });

            timer.start ();

            var time_block_1 = session_manager.current_time_block;

            var finished_time = session_manager.current_time_block.end_time;
            Ft.Timestamp.freeze_to (finished_time);
            timer.finish (finished_time);
            assert_true (time_block_1.state == Ft.State.POMODORO);
            assert_true (timer.state.is_finished ());

            // Confirm after 1 minute.
            var confirmation_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);

            // Note that timer.start() can't be used interchangeably with session_manager.advance(),
            // as the timer has already started.
            session_manager.advance (confirmation_time);

            var time_block_2 = session_manager.current_time_block;
            assert_true (time_block_2.state.is_break ());
            assert_true (timer.user_data == time_block_2);
            assert_true (timer.is_started ());

            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.started_time),
                new GLib.Variant.int64 (confirmation_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.offset),
                new GLib.Variant.int64 (0)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_1.end_time),
                new GLib.Variant.int64 (confirmation_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block_2.start_time),
                new GLib.Variant.int64 (confirmation_time)
            );
            assert_cmpuint (
                confirm_advancement_call_count,
                GLib.CompareOperator.EQ,
                1U
            );
        }

        /**
         * During confirmation user may extend the timer or skip.
         * Ensure the confirmation state is cleared up after extending the timer.
         */
        public void test_timer_finished__extend ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);
            settings.set_boolean ("confirm-starting-pomodoro", false);

            var timer           = new Ft.Timer ();
            var session_manager = new Ft.SessionManager.with_timer (timer);

            var confirm_advancement_call_count = 0;
            session_manager.confirm_advancement.connect (() => {
                confirm_advancement_call_count++;
            });

            timer.start ();

            var pomodoro = session_manager.current_time_block;
            var initial_duration = pomodoro.duration;

            Ft.Timestamp.freeze_to (pomodoro.end_time);
            timer.finish (pomodoro.end_time);

            assert_true (session_manager.current_time_block == pomodoro);
            assert_true (pomodoro.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_true (timer.state.is_finished ());
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.get_next_time_block ().start_time),
                new GLib.Variant.int64 (pomodoro.end_time)
            );
            assert_cmpuint (confirm_advancement_call_count, GLib.CompareOperator.EQ, 1U);

            timer.extend (Ft.Interval.MINUTE);

            assert_true (session_manager.current_time_block == pomodoro);
            assert_true (timer.is_running ());
            assert_cmpvariant (
                new GLib.Variant.int64 (pomodoro.duration),
                new GLib.Variant.int64 (initial_duration + Ft.Interval.MINUTE)
            );

            Ft.Timestamp.freeze_to (pomodoro.end_time);
            timer.finish (pomodoro.end_time);

            assert_true (session_manager.current_time_block == pomodoro);
            assert_true (pomodoro.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_true (timer.state.is_finished ());
            assert_cmpvariant (
                new GLib.Variant.int64 (timer.state.finished_time),
                new GLib.Variant.int64 (pomodoro.end_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (session_manager.get_next_time_block ().start_time),
                new GLib.Variant.int64 (pomodoro.end_time)
            );
            assert_cmpuint (confirm_advancement_call_count, GLib.CompareOperator.EQ, 2U);
        }
    }


    public class SessionManagerDatabaseTest : Tests.TestSuite
    {
        private Ft.Timer?           timer;
        private Ft.SessionManager?  session_manager;
        private Ft.TimezoneHistory? timezone_history;
        private GLib.TimeZone?      new_york_timezone;
        private GLib.TimeZone?      london_timezone;
        private GLib.MainLoop?      main_loop;
        private uint                timeout_id = 0;

        public SessionManagerDatabaseTest ()
        {
            this.add_test ("save__empty_session", this.test_save__empty_session);
            this.add_test ("save__update_time_block_status", this.test_save__update_time_block_status);
            this.add_test ("save__update_time_range", this.test_save__update_time_range);
            this.add_test ("save__delete_extra_time_blocks", this.test_save__delete_extra_time_blocks);
            this.add_test ("save__delete_extra_gaps", this.test_save__delete_extra_gaps);
            this.add_test ("save__delete_empty_session", this.test_save__delete_empty_session);
            this.add_test ("save__advance_session", this.test_save__advance_session);
            this.add_test ("save__timer_start", this.test_save__timer_start);
            this.add_test ("save__timer_pause", this.test_save__timer_pause);
            this.add_test ("save__timer_rewind", this.test_save__timer_rewind);
            this.add_test ("save__concurrent_calls",
                           this.test_save__concurrent_calls);
            this.add_test ("save__concurrent_calls_coalesced",
                           this.test_save__concurrent_calls_coalesced);

            this.add_test ("restore__empty_database", this.test_restore__empty_database);
            this.add_test ("restore__empty_session", this.test_restore__empty_session);
            this.add_test ("restore__in_progress_time_block", this.test_restore__in_progress_time_block);
            this.add_test ("restore__uncompleted_time_block", this.test_restore__uncompleted_time_block);
            this.add_test ("restore__completed_time_block", this.test_restore__completed_time_block);
            this.add_test ("restore__multiple_time_blocks", this.test_restore__multiple_time_blocks);
            this.add_test ("restore__multiple_gaps", this.test_restore__multiple_gaps);
            this.add_test ("restore__missing_ongoing_gap", this.test_restore__missing_ongoing_gap);
            this.add_test ("restore__out_of_range_gaps", this.test_restore__out_of_range_gaps);
            this.add_test ("restore__most_recent_session", this.test_restore__most_recent_session);
            this.add_test ("restore__completed_session", this.test_restore__completed_session);
            this.add_test ("restore__expired_session", this.test_restore__expired_session);
            this.add_test ("restore__confirm_advancement", this.test_restore__confirm_advancement);
        }

        public override void setup ()
        {
            Ft.Timestamp.freeze_to (2000000000 * Ft.Interval.SECOND);
            Ft.Timestamp.set_auto_advance (Ft.Interval.MICROSECOND);

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1500);
            settings.set_uint ("short-break-duration", 300);
            settings.set_uint ("long-break-duration", 900);
            settings.set_uint ("cycles", 4);
            settings.set_boolean ("confirm-starting-break", false);
            settings.set_boolean ("confirm-starting-pomodoro", false);

            Ft.Database.open ();

            try {
                this.new_york_timezone = new GLib.TimeZone.identifier ("America/New_York");
                this.london_timezone = new GLib.TimeZone.identifier ("Europe/London");
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.main_loop = new GLib.MainLoop ();

            this.timezone_history = new Ft.TimezoneHistory ();
            this.timezone_history.insert (Ft.Timestamp.peek (), this.new_york_timezone);

            this.timer = new Ft.Timer ();
            Ft.Timer.set_default (this.timer);

            this.session_manager = new Ft.SessionManager.with_timer (this.timer);
        }

        public override void teardown ()
        {
            var settings = Ft.get_settings ();
            settings.revert ();

            this.timer.reset ();
            Ft.Timer.set_default (null);

            this.session_manager = null;
            this.timer = null;
            this.timezone_history = null;
            this.main_loop = null;

            Ft.Database.close ();
        }

        private bool run_main_loop (uint timeout = 1000)
        {
            var success = true;

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.timeout_id = GLib.Timeout.add (timeout, () => {
                this.timeout_id = 0;
                this.main_loop.quit ();

                success = false;

                return GLib.Source.REMOVE;
            });

            this.main_loop.run ();

            return success;
        }

        private void quit_main_loop ()
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.main_loop.quit ();
        }

        private void run_save (Ft.SessionManager? session_manager = null)
        {
            if (session_manager == null) {
                session_manager = this.session_manager;
            }

            session_manager.save.begin (
                (obj, res) => {
                    assert_true (session_manager.save.end (res));

                    this.quit_main_loop ();
                });

            assert_true (this.run_main_loop ());
        }

        private void run_restore (Ft.SessionManager? session_manager = null,
                                  int64                    timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (session_manager == null) {
                session_manager = this.session_manager;
            }

            session_manager.restore.begin (
                timestamp,
                (obj, res) => {
                    assert_true (session_manager.restore.end (res));

                    this.quit_main_loop ();
                });

            assert_true (this.run_main_loop ());
        }

        /**
         * If session hasn't started yet, expect nothing to be saved.
         */
        public void test_save__empty_session ()
        {
            this.session_manager.ensure_session ();
            assert_true (this.session_manager.current_session.is_scheduled ());

            this.run_save ();

            var repository = Ft.Database.get_repository ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Test if `time_block.set_status()` call is propagated to an updated entry.
         */
        public void test_save__update_time_block_status ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_session = session;
            this.run_save ();

            Ft.SessionEntry? initial_session_entry = null;
            Ft.TimeBlockEntry? initial_time_block_entry = null;

            try {
                initial_session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_nonnull (initial_session_entry);

                initial_time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_nonnull (initial_time_block_entry);

                // Modify just the time-block status, expect its entry to be updated.
                time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.id),
                    new GLib.Variant.int64 (initial_session_entry.id)
                );

                var time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.id),
                    new GLib.Variant.int64 (initial_time_block_entry.id)
                );
                assert_cmpstr (time_block_entry.status,
                               GLib.CompareOperator.EQ,
                               "completed");
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Test if changing time-block range is propagated to an updated entry.
         */
        public void test_save__update_time_range ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_session = session;
            this.run_save ();

            Ft.SessionEntry? initial_session_entry = null;
            Ft.TimeBlockEntry? initial_time_block_entry = null;

            try {
                initial_session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_nonnull (initial_session_entry);

                initial_time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_nonnull (initial_time_block_entry);

                // Modify just the time-block range, expect its entry to be updated.
                time_block.move_by (Ft.Interval.MINUTE);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.id),
                    new GLib.Variant.int64 (initial_session_entry.id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.start_time),
                    new GLib.Variant.int64 (session.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.end_time),
                    new GLib.Variant.int64 (session.end_time)
                );

                var time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.id),
                    new GLib.Variant.int64 (initial_time_block_entry.id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.start_time),
                    new GLib.Variant.int64 (time_block.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.end_time),
                    new GLib.Variant.int64 (time_block.end_time)
                );
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Simulate a hypothetical scenario that time-block exists in database but not in
         * session. Expect it to be removed.
         *
         * At the time this test is written we do not save scheduled time-blocks and we
         * don't remove time-blocks from session once they have started.
         */
        public void test_save__delete_extra_time_blocks ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_session = session;
            this.run_save ();

            Ft.SessionEntry? session_entry = null;
            Ft.TimeBlockEntry? time_block_entry = null;

            try {
                session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_nonnull (session_entry);

                time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_nonnull (time_block_entry);

                var extra_time_block_entry = new Ft.TimeBlockEntry ();
                extra_time_block_entry.repository = repository;
                extra_time_block_entry.session_id = session_entry.id;
                extra_time_block_entry.start_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
                extra_time_block_entry.end_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
                extra_time_block_entry.state = "pomodoro";
                extra_time_block_entry.status = "uncompleted";
                extra_time_block_entry.intended_duration = 0;
                extra_time_block_entry.save_sync ();

                var results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.run_save ();

            try {
                var results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var remaining_time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (remaining_time_block_entry.id),
                    new GLib.Variant.int64 (time_block_entry.id)
                );
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__delete_extra_gaps ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var gap = new Ft.Gap ();
            gap.set_time_range (now + 1 * Ft.Interval.MINUTE,
                                now + 2 * Ft.Interval.MINUTE);

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 26 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_session = session;
            this.run_save ();

            Ft.SessionEntry? session_entry = null;
            Ft.TimeBlockEntry? time_block_entry = null;
            Ft.GapEntry? gap_entry = null;

            try {
                session_entry = (Ft.SessionEntry?) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_nonnull (session_entry);

                time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_nonnull (time_block_entry);

                gap_entry = (Ft.GapEntry?) repository.find_one_sync (
                        typeof (Ft.GapEntry), null);
                assert_nonnull (gap_entry);

                var extra_gap_entry = new Ft.GapEntry ();
                extra_gap_entry.repository = repository;
                extra_gap_entry.time_block_id = time_block_entry.id;
                extra_gap_entry.start_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
                extra_gap_entry.end_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
                extra_gap_entry.flags = Ft.GapFlags.DEFAULT.to_string ();
                extra_gap_entry.save_sync ();

                var results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Only changed time-block will be saved. Force it.
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            this.run_save ();

            try {

                var results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var remaining_gap_entry = (Ft.GapEntry?) repository.find_one_sync (
                        typeof (Ft.GapEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (remaining_gap_entry.id),
                    new GLib.Variant.int64 (gap_entry.id)
                );
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * If session is modified and becomes empty, expect database entry to be removed.
         *
         * It's a hypothetical scenario.
         */
        public void test_save__delete_empty_session ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_session = session;
            assert_false (this.timer.is_running ());

            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            time_block.set_status (Ft.TimeBlockStatus.SCHEDULED);
            assert_true (session.is_scheduled ());
            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);
            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__advance_session ()
        {
            var now = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.set_time_range (now, now + 5 * Ft.Interval.MINUTE);
            time_block_1.set_status (Ft.TimeBlockStatus.UNCOMPLETED);

            var time_block_2 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_2.set_time_range (now + 10 * Ft.Interval.MINUTE,
                                         now + 35 * Ft.Interval.MINUTE);
            time_block_2.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session_1 = new Ft.Session ();
            session_1.append (time_block_1);

            var session_2 = new Ft.Session ();
            session_2.append (time_block_2);

            this.session_manager.current_session = session_1;
            this.session_manager.current_session = session_2;
            this.run_save ();

            // Ensure that previous session has been saved as well as the current one.
            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__timer_start ()
        {
            this.session_manager.timer.start ();
            this.run_save ();

            // Expect one time-block that is in-progress to be saved.
            var repository = Ft.Database.get_repository ();
            var session    = this.session_manager.current_session;
            var time_block = this.session_manager.current_time_block;

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.SessionEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var session_entry = (Ft.SessionEntry) repository.find_one_sync (
                        typeof (Ft.SessionEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.start_time),
                    new GLib.Variant.int64 (session.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (session_entry.end_time),
                    new GLib.Variant.int64 (session.end_time)
                );

                var time_block_entry = (Ft.TimeBlockEntry) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.start_time),
                    new GLib.Variant.int64 (time_block.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.end_time),
                    new GLib.Variant.int64 (time_block.end_time)
                );
                assert_cmpstr (time_block_entry.status,
                               GLib.CompareOperator.EQ,
                               "in-progress");
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__timer_pause ()
        {
            var repository = Ft.Database.get_repository ();

            this.timer.start ();
            this.run_save ();

            // Pause timer
            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            this.timer.pause ();
            this.run_save ();

            var session = this.session_manager.current_session;
            assert_false (Ft.Timestamp.is_undefined (session.end_time));

            var time_block = this.session_manager.current_time_block;
            assert_false (Ft.Timestamp.is_undefined (time_block.end_time));

            var gap = time_block.get_last_gap ();
            assert_true (Ft.Timestamp.is_undefined (gap.end_time));

            var expected_time_block_id = (int64) 0;
            var expected_gap_id = (int64) 0;

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var time_block_entry = (Ft.TimeBlockEntry) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.end_time),
                    new GLib.Variant.int64 (time_block.end_time)
                );

                var gap_entry = (Ft.GapEntry) repository.find_one_sync (
                        typeof (Ft.GapEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.time_block_id),
                    new GLib.Variant.int64 (time_block_entry.id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.start_time),
                    new GLib.Variant.int64 (gap.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.end_time),
                    new GLib.Variant.int64 (gap.end_time)
                );

                expected_time_block_id = time_block_entry.id;
                expected_gap_id = gap_entry.id;
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Resume timer
            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            this.timer.resume ();
            assert_true (Ft.Timestamp.is_defined (gap.end_time));

            this.run_save ();

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var time_block_entry = (Ft.TimeBlockEntry) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.id),
                    new GLib.Variant.int64 (expected_time_block_id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.end_time),
                    new GLib.Variant.int64 (time_block.end_time)
                );

                var gap_entry = (Ft.GapEntry) repository.find_one_sync (
                        typeof (Ft.GapEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.id),
                    new GLib.Variant.int64 (expected_gap_id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.time_block_id),
                    new GLib.Variant.int64 (time_block_entry.id)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.start_time),
                    new GLib.Variant.int64 (gap.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.end_time),
                    new GLib.Variant.int64 (gap.end_time)
                );
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Gaps may be normalized after using rewind. Expect unnecessary gaps to be removed.
         */
        public void test_save__timer_rewind ()
        {
            var repository = Ft.Database.get_repository ();

            var start_time = Ft.Timestamp.peek ();
            this.timer.start (start_time);
            this.run_save ();

            var pause_time = start_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (pause_time);
            this.timer.pause (pause_time);
            this.run_save ();

            var resume_time = pause_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (resume_time);
            this.timer.resume (resume_time);
            this.run_save ();

            var rewind_time = resume_time + Ft.Interval.MINUTE;
            Ft.Timestamp.freeze_to (rewind_time);
            this.timer.rewind (3 * Ft.Interval.MINUTE, rewind_time);
            this.run_save ();

            var time_block = this.session_manager.current_time_block;
            var gap = time_block.get_last_gap ();
            assert_cmpvariant (
                new GLib.Variant.int64 (gap.duration),
                new GLib.Variant.int64 (3 * Ft.Interval.MINUTE)
            );

            try {
                Gom.ResourceGroup results;

                results = repository.find_sync (typeof (Ft.TimeBlockEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var time_block_entry = (Ft.TimeBlockEntry) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.start_time),
                    new GLib.Variant.int64 (time_block.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (time_block_entry.end_time),
                    new GLib.Variant.int64 (time_block.end_time)
                );

                var gap_entry = (Ft.GapEntry) repository.find_one_sync (
                        typeof (Ft.GapEntry), null);
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.start_time),
                    new GLib.Variant.int64 (gap.start_time)
                );
                assert_cmpvariant (
                    new GLib.Variant.int64 (gap_entry.end_time),
                    new GLib.Variant.int64 (gap.end_time)
                );
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * All concurrent save() calls should complete successfully.
         */
        public void test_save__concurrent_calls ()
        {
            this.session_manager.timer.start ();

            var n = 3;
            var completed = 0;
            var all_succeeded = true;

            for (var i = 0; i < n; i++)
            {
                this.session_manager.save.begin (
                    (obj, res) => {
                        if (!this.session_manager.save.end (res)) {
                            all_succeeded = false;
                        }
                        completed++;
                        if (completed == n) {
                            this.quit_main_loop ();
                        }
                    });
            }

            assert_true (this.run_main_loop ());
            assert_true (all_succeeded);
        }

        /**
         * State changed after the first save's snapshot but before it completes should
         * be captured by the coalesced save, proving the coalesced save actually ran.
         *
         * save_A takes its snapshot synchronously (before yielding to the DB), so
         * pausing the timer afterwards creates a gap that only the coalesced save sees.
         * If coalescing were broken and waiters were silently dropped, no GapEntry would
         * be written and the assertion would fail.
         */
        public void test_save__concurrent_calls_coalesced ()
        {
            var repository = Ft.Database.get_repository ();

            this.session_manager.timer.start ();

            var completed = 0;
            var all_succeeded = true;

            // First save: starts in-flight; its snapshot is taken before it yields to the DB.
            this.session_manager.save.begin ((obj, res) => {
                if (!this.session_manager.save.end (res)) {
                    all_succeeded = false;
                }
                completed++;
                if (completed == 2) {
                    this.quit_main_loop ();
                }
            });

            // Modify state after save_A's snapshot: pause creates a gap that only the
            // coalesced save will capture.
            Ft.Timestamp.advance (Ft.Interval.MINUTE);
            this.session_manager.timer.pause ();

            // Second save: no changes, wait for final result.
            this.session_manager.save.begin ((obj, res) => {
                if (!this.session_manager.save.end (res)) {
                    all_succeeded = false;
                }
                completed++;
                if (completed == 2) {
                    this.quit_main_loop ();
                }
            });

            assert_true (this.run_main_loop ());
            assert_true (all_succeeded);

            try {
                var results = repository.find_sync (typeof (Ft.GapEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Restoring from an empty database should not crash or set any session.
         */
        public void test_restore__empty_database ()
        {
            this.run_restore ();

            assert_null (this.session_manager.current_session);
            assert_null (this.session_manager.current_time_block);
        }

        /**
         * We delete sessions that are empty from database. However, expect an empty session
         * not to break things.
         */
        public void test_restore__empty_session ()
        {
            var session_entry = new Ft.SessionEntry ();
            session_entry.repository = Ft.Database.get_repository ();
            session_entry.start_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            session_entry.end_time = Ft.Timestamp.advance (25 * Ft.Interval.MINUTE);

            try {
                session_entry.save_sync ();
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.run_restore ();

            assert_null (this.session_manager.current_session);
            assert_null (this.session_manager.current_time_block);
        }

        /**
         * Restore a session with a single in-progress time block.
         */
        public void test_restore__in_progress_time_block ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp,
                                       timestamp + 25 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);
            time_block.notify["start-time"].connect (
                () => {
                    assert_not_reached ();
                });

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (time_block.start_time + Ft.Interval.MINUTE,
                                  time_block.start_time + 3 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_1);
            time_block.end_time += gap_1.duration;

            var gap_2 = new Ft.Gap.with_start_time (
                    time_block.start_time + 4 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);

            var session = new Ft.Session ();
            session.append (time_block);

            Ft.Timestamp.freeze_to (gap_2.start_time);
            this.session_manager.current_time_block = time_block;
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);

            var save_time = gap_2.start_time + 5 * Ft.Interval.MINUTE;
            var restore_time = save_time + 30 * Ft.Interval.MINUTE;

            // Save
            Ft.Timestamp.freeze_to (save_time);
            this.run_save ();

            // Restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.freeze_to (restore_time);
            this.run_restore (new_session_manager, restore_time);

            var restored_session = new_session_manager.current_session;
            var restored_time_block = new_session_manager.current_time_block;
            var restored_gap = new_session_manager.current_gap;
            assert_nonnull (restored_session);
            assert_nonnull (restored_time_block);
            assert_nonnull (restored_gap);

            assert_cmpvariant (
                new GLib.Variant.int64 (restored_session.start_time),
                new GLib.Variant.int64 (session.start_time)
            );
            assert_cmpuint (
                restored_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                session.count_visible_cycles ()
            );

            assert_true (restored_time_block.state == Ft.State.POMODORO);
            assert_true (restored_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block.start_time),
                new GLib.Variant.int64 (time_block.start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block.get_intended_duration ()),
                new GLib.Variant.int64 (time_block.get_intended_duration ())
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block.calculate_elapsed (restore_time)),
                new GLib.Variant.int64 (time_block.calculate_elapsed (save_time))
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block.calculate_remaining (restore_time)),
                new GLib.Variant.int64 (time_block.calculate_remaining (save_time))
            );

            assert_true (restored_gap.flags == gap_2.flags);
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_gap.start_time),
                new GLib.Variant.int64 (gap_2.start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_gap.end_time),
                new GLib.Variant.int64 (gap_2.end_time)
            );

            var expected_elapsed = time_block.calculate_elapsed ();
            var expected_timer_state = Ft.TimerState () {
                duration = time_block.get_intended_duration (),
                offset = gap_2.start_time - time_block.start_time - expected_elapsed,
                started_time = time_block.start_time,
                paused_time = gap_2.start_time,
                finished_time = Ft.Timestamp.UNDEFINED,
                user_data = restored_time_block
            };
            assert_cmpvariant (
                timer.state.to_variant (),
                expected_timer_state.to_variant ()
            );
        }

        /**
         * Restore a session with an uncompleted time block.
         */
        public void test_restore__uncompleted_time_block ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 25 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (25 * Ft.Interval.MINUTE);

            var session = new Ft.Session ();
            session.append (time_block);

            this.session_manager.current_time_block = time_block;

            timestamp = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            Ft.Timestamp.freeze_to (timestamp);
            this.session_manager.current_time_block = null;
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            timestamp = Ft.Timestamp.advance (5 * Ft.Interval.MINUTE);
            this.run_restore (new_session_manager, timestamp);

            var restored_session = new_session_manager.current_session;
            var restored_time_block = new_session_manager.current_time_block;
            assert_nonnull (restored_session);
            assert_null (restored_time_block);

            assert_cmpvariant (
                new GLib.Variant.int64 (restored_session.start_time),
                new GLib.Variant.int64 (session.start_time)
            );
            assert_cmpuint (
                restored_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                session.count_visible_cycles ()
            );

            restored_time_block = restored_session.get_first_time_block ();
            assert_true (restored_time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED);

            new_timer.start ();
            assert_true (new_session_manager.current_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_true (restored_session.get_previous_time_block (new_session_manager.current_time_block) == restored_time_block);
        }

        /**
         * Restore a session with in-progress time-block when the timer reached finish and we
         * await advancement confirmation.
         */
        public void test_restore__completed_time_block ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-break", true);

            var timestamp = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 25 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            Ft.Timestamp.freeze_to (time_block.end_time);
            this.session_manager.current_time_block = time_block;
            assert_true (time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (timestamp)
            );
            assert_true (this.timer.is_finished ());

            Ft.Timestamp.freeze_to (time_block.end_time + 10 * Ft.Interval.MINUTE);
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.freeze_to (time_block.end_time + 20 * Ft.Interval.MINUTE);
            this.run_restore (new_session_manager);

            var restored_session = new_session_manager.current_session;
            var restored_time_block = new_session_manager.current_time_block;
            var restored_gap = new_session_manager.current_gap;
            assert_nonnull (restored_session);
            assert_nonnull (restored_time_block);
            assert_null (restored_gap);
            assert_true (restored_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_true (this.timer.is_finished ());

            assert_cmpuint (
                restored_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                session.count_visible_cycles ()
            );
        }

        /**
         * Restore a session with multiple time blocks (only in-progress ones are restored).
         */
        public void test_restore__multiple_time_blocks ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.set_time_range (timestamp, timestamp + 25 * Ft.Interval.MINUTE);
            time_block_1.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var time_block_2 = new Ft.TimeBlock (Ft.State.SHORT_BREAK);
            time_block_2.set_time_range (timestamp + 25 * Ft.Interval.MINUTE,
                                         timestamp + 30 * Ft.Interval.MINUTE);
            time_block_2.set_intended_duration (5 * Ft.Interval.MINUTE);
            time_block_2.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap = new Ft.Gap.with_start_time (timestamp + 26 * Ft.Interval.MINUTE);
            time_block_2.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block_1);
            session.append (time_block_2);

            Ft.Timestamp.freeze_to (gap.start_time);
            this.session_manager.current_time_block = time_block_2;
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            this.run_restore (new_session_manager);
            assert_nonnull (new_session_manager.current_session);
            assert_nonnull (new_session_manager.current_time_block);
            assert_nonnull (new_session_manager.current_gap);
            assert_true (new_session_manager.current_state == Ft.State.SHORT_BREAK);
            assert_true (new_timer.is_paused ());

            var restored_session = new_session_manager.current_session;
            var restored_time_block_1 = restored_session.get_nth_time_block (0);
            var restored_time_block_2 = restored_session.get_nth_time_block (1);

            assert_nonnull (restored_time_block_1);
            assert_true (restored_time_block_1.state == Ft.State.POMODORO);
            assert_true (restored_time_block_1.get_status () == Ft.TimeBlockStatus.COMPLETED);
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_1.start_time),
                new GLib.Variant.int64 (time_block_1.start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_1.end_time),
                new GLib.Variant.int64 (time_block_1.end_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_1.get_intended_duration ()),
                new GLib.Variant.int64 (time_block_1.get_intended_duration ())
            );
            assert_cmpfloat (
                restored_time_block_1.get_weight (),
                GLib.CompareOperator.EQ,
                time_block_1.get_weight ()
            );

            assert_nonnull (restored_time_block_2);
            assert_true (restored_time_block_2.state == Ft.State.SHORT_BREAK);
            assert_true (restored_time_block_2.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_2.start_time),
                new GLib.Variant.int64 (time_block_2.start_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_2.end_time),
                new GLib.Variant.int64 (time_block_2.end_time)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block_2.get_intended_duration ()),
                new GLib.Variant.int64 (time_block_2.get_intended_duration ())
            );
            assert_cmpfloat (
                restored_time_block_2.get_weight (),
                GLib.CompareOperator.EQ,
                time_block_2.get_weight ()
            );

            assert_cmpuint (
                restored_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                session.count_visible_cycles ()
            );
        }

        /**
         * Restore a session with gaps in time blocks.
         */
        public void test_restore__multiple_gaps ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.set_time_range (timestamp,
                                         timestamp + 50 * Ft.Interval.MINUTE);
            time_block_1.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var gap_1 = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap_1.set_time_range (timestamp + 5 * Ft.Interval.MINUTE,
                                  timestamp + 30 * Ft.Interval.MINUTE);
            time_block_1.add_gap (gap_1);

            var time_block_2 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_2.set_time_range (timestamp + 60 * Ft.Interval.MINUTE,
                                         timestamp + 87 * Ft.Interval.MINUTE);
            time_block_2.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block_2.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap_2 = new Ft.Gap (Ft.GapFlags.SLEEP);
            gap_2.set_time_range (timestamp + 65 * Ft.Interval.MINUTE,
                                  timestamp + 67 * Ft.Interval.MINUTE);
            time_block_2.add_gap (gap_2);

            var gap_3 = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap_3.start_time = timestamp + 70 * Ft.Interval.MINUTE;
            time_block_2.add_gap (gap_3);

            var session = new Ft.Session ();
            session.append (time_block_1);
            session.append (time_block_2);

            Ft.Timestamp.freeze_to (gap_3.start_time);
            this.session_manager.current_time_block = time_block_2;
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.advance (5 * Ft.Interval.MINUTE);
            this.run_restore (new_session_manager);
            assert_nonnull (new_session_manager.current_session);
            assert_nonnull (new_session_manager.current_time_block);
            assert_nonnull (new_session_manager.current_gap);
            assert_true (new_session_manager.current_state == Ft.State.POMODORO);
            assert_true (new_timer.is_paused ());

            var restored_session      = new_session_manager.current_session;
            var restored_time_block_1 = restored_session.get_nth_time_block (0);
            var restored_time_block_2 = restored_session.get_nth_time_block (1);
            var restored_gap_1        = restored_time_block_1.get_nth_gap (0);
            var restored_gap_2        = restored_time_block_2.get_nth_gap (0);
            var restored_gap_3        = restored_time_block_2.get_nth_gap (1);

            assert_nonnull (restored_gap_1);
            assert_true (restored_gap_1.flags == Ft.GapFlags.INTERRUPTION);
            assert_cmpvariant (
                restored_gap_1.start_time,
                gap_1.start_time
            );
            assert_cmpvariant (
                restored_gap_1.end_time,
                gap_1.end_time
            );

            assert_nonnull (restored_gap_2);
            assert_true (restored_gap_2.flags == Ft.GapFlags.SLEEP);
            assert_cmpvariant (
                restored_gap_2.start_time,
                gap_2.start_time
            );
            assert_cmpvariant (
                restored_gap_2.end_time,
                gap_2.end_time
            );

            assert_nonnull (restored_gap_3);
            assert_true (restored_gap_3.flags == Ft.GapFlags.INTERRUPTION);
            assert_cmpvariant (
                restored_gap_3.start_time,
                gap_3.start_time
            );
            assert_cmpvariant (
                restored_gap_3.end_time,
                Ft.Timestamp.UNDEFINED
            );

            assert_cmpfloat (
                restored_time_block_1.get_weight (),
                GLib.CompareOperator.EQ,
                time_block_1.get_weight ()
            );
            assert_cmpuint (
                restored_session.count_visible_cycles (),
                GLib.CompareOperator.EQ,
                session.count_visible_cycles ()
            );
        }

        /**
         * Expect session to be paused when shutting down the app.
         * When the app hasn't closed properly, expect it to rewind to the last known
         * position. It's better to under-report spent time.
         */
        public void test_restore__missing_ongoing_gap ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 27 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (timestamp + 5 * Ft.Interval.MINUTE,
                                timestamp + 7 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block);

            Ft.Timestamp.freeze_to (gap.end_time + Ft.Interval.MINUTE);
            this.session_manager.current_time_block = time_block;
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.freeze_to (gap.end_time + 5 * Ft.Interval.MINUTE);
            this.run_restore (new_session_manager);

            var restored_session = new_session_manager.current_session;
            assert_nonnull (restored_session);

            var restored_time_block = new_session_manager.current_time_block;
            assert_nonnull (restored_time_block);

            var restored_gap = restored_time_block.get_last_gap ();
            assert_nonnull (restored_gap);
            assert_cmpvariant (
                restored_gap.start_time,
                gap.start_time
            );
            assert_cmpvariant (
                restored_gap.end_time,
                Ft.Timestamp.UNDEFINED
            );
        }

        public void test_restore__out_of_range_gaps ()
        {
            var timestamp = Ft.Timestamp.peek ();
            var repository = Ft.Database.get_repository ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 25 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var session = new Ft.Session ();
            session.append (time_block);

            Ft.Timestamp.freeze_to (time_block.end_time);
            this.session_manager.current_time_block = time_block;
            this.run_save ();

            // Inject a gap entry that starts after the time block's end time,
            // simulating corrupt/out-of-range data in the database
            try {
                var time_block_entry = (Ft.TimeBlockEntry?) repository.find_one_sync (
                        typeof (Ft.TimeBlockEntry), null);
                assert_nonnull (time_block_entry);

                var out_of_range_gap = new Ft.GapEntry ();
                out_of_range_gap.repository = repository;
                out_of_range_gap.time_block_id = time_block_entry.id;
                out_of_range_gap.start_time = timestamp + 30 * Ft.Interval.MINUTE;
                out_of_range_gap.end_time = timestamp + 32 * Ft.Interval.MINUTE;
                out_of_range_gap.flags = Ft.GapFlags.DEFAULT.to_string ();
                out_of_range_gap.save_sync ();
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.freeze_to (time_block.end_time + Ft.Interval.MINUTE);
            this.run_restore (new_session_manager);

            var restored_session = new_session_manager.current_session;
            assert_nonnull (restored_session);

            var restored_time_block = restored_session.get_nth_time_block (0);
            assert_nonnull (restored_time_block);

            // Expect out-of-range gap to be skipped during restore
            assert_null (restored_time_block.get_last_gap ());
        }

        /**
         * When multiple sessions exist, restore should load the most recent one.
         */
        public void test_restore__most_recent_session ()
        {
            // Create and save first session (older)
            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.start_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            time_block_1.end_time = Ft.Timestamp.advance (25 * Ft.Interval.MINUTE);
            time_block_1.set_intended_duration (25 * Ft.Interval.MINUTE);
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session_1 = new Ft.Session ();
            session_1.append (time_block_1);

            this.session_manager.current_session = session_1;
            this.run_save ();

            // Create and save second session (more recent)
            Ft.Timestamp.advance (1 * Ft.Interval.HOUR);

            var time_block_2 = new Ft.TimeBlock (Ft.State.SHORT_BREAK);
            time_block_2.start_time = Ft.Timestamp.advance (Ft.Interval.MINUTE);
            time_block_2.end_time = Ft.Timestamp.advance (5 * Ft.Interval.MINUTE);
            time_block_2.set_intended_duration (5 * Ft.Interval.MINUTE);
            time_block_2.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap = new Ft.Gap ();
            gap.start_time = time_block_2.start_time + 1 * Ft.Interval.MINUTE;
            time_block_2.add_gap (gap);

            var session_2 = new Ft.Session ();
            session_2.append (time_block_2);

            this.session_manager.current_session = session_2;
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            this.run_restore (new_session_manager);

            var restored_session = new_session_manager.current_session;
            assert_nonnull (restored_session);
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_session.start_time),
                new GLib.Variant.int64 (session_2.start_time)
            );

            var restored_time_block = new_session_manager.current_time_block;
            assert_nonnull (new_session_manager.current_time_block);
            assert_true (restored_time_block.state == Ft.State.SHORT_BREAK);
            assert_true (restored_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
        }

        public void test_restore__completed_session ()
        {
            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.start_time = Ft.Timestamp.peek ();
            time_block_1.end_time = Ft.Timestamp.advance (25 * Ft.Interval.MINUTE);
            time_block_1.set_intended_duration (time_block_1.duration);
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var time_block_2 = new Ft.TimeBlock (Ft.State.LONG_BREAK);
            time_block_2.start_time = Ft.Timestamp.peek ();
            time_block_2.end_time = Ft.Timestamp.advance (15 * Ft.Interval.MINUTE);
            time_block_2.set_intended_duration (time_block_2.duration);
            time_block_2.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block_1);
            session.append (time_block_2);
            assert_true (session.is_completed ());

            this.session_manager.current_session = session;
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            this.run_restore (new_session_manager);
            assert_null (new_session_manager.current_session);
            assert_null (new_session_manager.current_time_block);
        }

        public void test_restore__expired_session ()
        {
            var timestamp = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 25 * Ft.Interval.MINUTE);
            time_block.set_intended_duration (time_block.duration);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.start_time = timestamp + 5 * Ft.Interval.MINUTE;
            time_block.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block);
            assert_false (session.is_completed ());

            Ft.Timestamp.freeze_to (timestamp);
            this.session_manager.current_time_block = time_block;
            assert_true (Ft.Timestamp.is_defined (session.expiry_time));
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            Ft.Timestamp.freeze_to (session.expiry_time);
            this.run_restore (new_session_manager);
            assert_null (new_session_manager.current_session);
            assert_null (new_session_manager.current_time_block);
        }

        public void test_restore__confirm_advancement ()
        {
            var settings = Ft.get_settings ();
            settings.set_boolean ("confirm-starting-pomodoro", true);

            this.session_manager.ensure_session ();

            var session = this.session_manager.current_session;

            var time_block_1 = session.get_nth_time_block (0U);  // Pomodoro
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var time_block_2 = session.get_nth_time_block (1U);  // Short break
            time_block_2.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            Ft.Timestamp.freeze_to (time_block_2.start_time);
            this.session_manager.current_time_block = time_block_2;

            Ft.Timestamp.freeze_to (time_block_2.end_time);
            this.timer.finish (time_block_2.end_time);

            Ft.Timestamp.freeze_to (time_block_2.end_time + Ft.Interval.MINUTE);
            this.run_save ();

            // Create a new session manager to test restore
            var new_timer = new Ft.Timer ();
            var new_session_manager = new Ft.SessionManager.with_timer (new_timer);

            var confirm_advancement_call_count = 0U;
            new_session_manager.confirm_advancement.connect (
                () => {
                    confirm_advancement_call_count++;
                });

            Ft.Timestamp.freeze_to (time_block_2.end_time + 10 * Ft.Interval.MINUTE);
            this.run_restore (new_session_manager);

            var restored_session = new_session_manager.current_session;
            var restored_time_block = new_session_manager.current_time_block;
            var restored_gap = new_session_manager.current_gap;
            assert_nonnull (restored_session);
            assert_nonnull (restored_time_block);
            assert_null (restored_gap);
            assert_true (restored_time_block.state == time_block_2.state);
            assert_true (restored_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS);
            assert_null (restored_time_block.get_last_gap ());
            assert_cmpvariant (
                new GLib.Variant.int64 (restored_time_block.end_time),
                new GLib.Variant.int64 (time_block_2.end_time)
            );
            assert_true (this.timer.is_finished ());
            assert_cmpuint (confirm_advancement_call_count, GLib.CompareOperator.EQ, 1U);

            var restored_next_time_block = new_session_manager.get_next_time_block ();
            assert_nonnull (restored_next_time_block);
            assert_true (restored_next_time_block.state == Ft.State.POMODORO);
            assert_true (restored_next_time_block.duration ==
                         settings.get_uint ("pomodoro-duration") * Ft.Interval.SECOND);
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.SessionManagerTest (),
        new Tests.SessionManagerTimerTest (),
        new Tests.SessionManagerDatabaseTest ()
    );
}
