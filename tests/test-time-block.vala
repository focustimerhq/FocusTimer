/*
 * This file is part of focus-timer
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Tests
{
    public class TimeBlockTest : Tests.TestSuite
    {
        public TimeBlockTest ()
        {
            this.add_test ("new__undefined",
                           this.test_new__undefined);
            this.add_test ("new__pomodoro",
                           this.test_new__pomodoro);
            this.add_test ("new__short_break",
                           this.test_new__short_break);
            this.add_test ("new__long_break",
                           this.test_new__long_break);

            this.add_test ("set_session",
                           this.test_set_session);

            this.add_test ("move_by__without_gaps", this.test_move_by__without_gaps);
            this.add_test ("move_by__with_gaps", this.test_move_by__with_gaps);
            this.add_test ("move_to", this.test_move_to);
            this.add_test ("add_gap", this.test_add_gap);
            this.add_test ("remove_gap", this.test_remove_gap);
            this.add_test ("normalize_gaps__invalid", this.test_normalize_gaps__invalid);
            this.add_test ("normalize_gaps__overlap", this.test_normalize_gaps__overlap);
            this.add_test ("normalize_gaps__unfinished", this.test_normalize_gaps__unfinished);

            this.add_test ("calculate_elapsed__without_gaps",
                           this.test_calculate_elapsed__without_gaps);
            this.add_test ("calculate_elapsed__with_gaps",
                           this.test_calculate_elapsed__with_gaps);
            this.add_test ("calculate_elapsed__with_ongoing_gap",
                           this.test_calculate_elapsed__with_ongoing_gap);
            this.add_test ("calculate_elapsed__with_gaps_overlapping",
                           this.test_calculate_elapsed__with_gaps_overlapping);

            this.add_test ("calculate_remaining__without_gaps",
                           this.test_calculate_remaining__without_gaps);
            this.add_test ("calculate_remaining__with_gaps",
                           this.test_calculate_remaining__with_gaps);
            this.add_test ("calculate_remaining__with_ongoing_gap",
                           this.test_calculate_remaining__with_ongoing_gap);
            this.add_test ("calculate_remaining__with_gaps_overlapping",
                           this.test_calculate_remaining__with_gaps_overlapping);

            this.add_test ("calculate_progress__without_gaps",
                           this.test_calculate_progress__without_gaps);
            this.add_test ("calculate_progress__with_gaps",
                           this.test_calculate_progress__with_gaps);
            this.add_test ("calculate_progress__with_ongoing_gap",
                           this.test_calculate_progress__with_ongoing_gap);

            this.add_test ("has_reached_completion",
                           this.test_has_reached_completion);
            this.add_test ("has_reached_completion__with_ongoing_gap",
                           this.test_has_reached_completion__with_ongoing_gap);

            // this.add_test ("state", this.test_state);
            // this.add_test ("start_time", this.test_start_time);
            // this.add_test ("end_time", this.test_end_time);
            // this.add_test ("duration", this.test_duration);

            // this.add_test ("changed_signal", this.test_changed_signal);
        }

        public override void setup ()
        {
            Ft.Timestamp.freeze_to (2000000000 * Ft.Interval.SECOND);

            // var settings = Ft.get_settings ();
            // settings.set_uint ("pomodoro-duration", POMODORO_DURATION);
            // settings.set_uint ("short-break-duration", SHORT_BREAK_DURATION);
            // settings.set_uint ("long-break-duration", LONG_BREAK_DURATION);
            // settings.set_uint ("cycles", CYCLES);
        }

        public override void teardown ()
        {
            Ft.Timestamp.thaw ();

            // var settings = Ft.get_settings ();
            // settings.revert ();
        }


        /*
         * Tests for constructors
         */

        public void test_new__undefined ()
        {
            var state = Ft.State.STOPPED;
            var time_block = new Ft.TimeBlock (state);

            assert_true (time_block.state == state);
            assert_true (Ft.Timestamp.is_undefined (time_block.start_time));
            assert_true (Ft.Timestamp.is_undefined (time_block.end_time));
        }

        public void test_new__pomodoro ()
        {
            var state = Ft.State.POMODORO;
            var time_block = new Ft.TimeBlock (state);

            assert_true (time_block.state == state);
            assert_true (Ft.Timestamp.is_undefined (time_block.start_time));
            assert_true (Ft.Timestamp.is_undefined (time_block.end_time));
        }

        public void test_new__short_break ()
        {
            var state = Ft.State.SHORT_BREAK;
            var time_block = new Ft.TimeBlock (state);

            assert_true (time_block.state == state);
            assert_true (Ft.Timestamp.is_undefined (time_block.start_time));
            assert_true (Ft.Timestamp.is_undefined (time_block.end_time));
        }

        public void test_new__long_break ()
        {
            var state = Ft.State.LONG_BREAK;
            var time_block = new Ft.TimeBlock (state);

            assert_true (time_block.state == state);
            assert_true (Ft.Timestamp.is_undefined (time_block.start_time));
            assert_true (Ft.Timestamp.is_undefined (time_block.end_time));
        }


        /*
         * Tests for properties
         */

        public void test_set_session ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);

            var notify_session_emitted = 0;
            time_block.notify["session"].connect (() => {
                notify_session_emitted++;
            });

            var session_1 = new Ft.Session ();
            time_block.session = session_1;
            assert_true (time_block.session == session_1);
            assert_true (notify_session_emitted == 1);

            time_block.session = session_1;
            assert_true (time_block.session == session_1);
            assert_true (notify_session_emitted == 1);  // unchanged

            var session_2 = new Ft.Session ();
            time_block.session = session_2;
            assert_true (time_block.session == session_2);
            assert_true (notify_session_emitted == 2);
        }

        public void test_state ()
        {
            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            assert_true (time_block_1.state == Ft.State.POMODORO);

            var time_block_2 = new Ft.TimeBlock (Ft.State.BREAK);
            assert_true (time_block_2.state == Ft.State.BREAK);

            var time_block_3 = new Ft.TimeBlock (Ft.State.STOPPED);
            assert_true (time_block_3.state == Ft.State.STOPPED);
        }

        // public void test_start_time ()
        // {
        // }

        // public void test_end_time ()
        // {
        // }

        // public void test_duration ()
        // {
        // }

        // public void test_session ()
        // {
        // }


        /*
         * Tests for methods
         */

        public void test_move_by__without_gaps ()
        {
            var now = Ft.Timestamp.peek ();
            var time_block = new Ft.TimeBlock ();

            var changed_emitted = 0;
            time_block.changed.connect (() => {
                changed_emitted++;
            });

            time_block.set_time_range (Ft.Timestamp.UNDEFINED, now);
            time_block.move_by (Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 2);

            time_block.set_time_range (now, Ft.Timestamp.UNDEFINED);
            time_block.move_by (Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 4);

            time_block.set_time_range (now, now + Ft.Interval.MINUTE);
            time_block.move_by (Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now + 2 * Ft.Interval.MINUTE)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 6);

            time_block.move_by (0);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 6);
        }

        public void test_move_by__with_gaps ()
        {
            var now = Ft.Timestamp.peek ();
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (now, now + 5 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (now + 0 * Ft.Interval.SECOND,
                                  now + 5 * Ft.Interval.SECOND);
            time_block.add_gap (gap_1);

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (now + 10 * Ft.Interval.SECOND,
                                  now + 20 * Ft.Interval.SECOND);
            time_block.add_gap (gap_2);

            time_block.move_by (Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_1.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE + 0 * Ft.Interval.SECOND)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_1.end_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE + 5 * Ft.Interval.SECOND)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_2.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE + 10 * Ft.Interval.SECOND)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (gap_2.end_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE + 20 * Ft.Interval.SECOND)
            );
        }

        public void test_move_to ()
        {
            var now = Ft.Timestamp.advance (0);
            var time_block = new Ft.TimeBlock ();

            var changed_emitted = 0;
            time_block.changed.connect (() => {
                changed_emitted++;
            });

            // Move +1 minute, while range is not defined.
            time_block.set_time_range (Ft.Timestamp.UNDEFINED, now);
            time_block.move_to (now + Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 1);

            // Move +1 minute, while range is not defined.
            time_block.set_time_range (now, Ft.Timestamp.UNDEFINED);
            time_block.move_to (now + Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (Ft.Timestamp.UNDEFINED)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 3);

            // Move +1 minute.
            time_block.set_time_range (now, now + Ft.Interval.MINUTE);
            time_block.move_to (now + Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now + 2 * Ft.Interval.MINUTE)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 5);

            // Move -1 minute.
            time_block.set_time_range (now + Ft.Interval.MINUTE, now + 2 * Ft.Interval.MINUTE);
            time_block.move_to (now);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.start_time),
                new GLib.Variant.int64 (now)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.end_time),
                new GLib.Variant.int64 (now + Ft.Interval.MINUTE)
            );
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 6);

            // Move 0 minutes.
            time_block.move_to (time_block.start_time);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 6);
        }

        // public void test_has_started ()
        // {
        // }

        // public void test_has_ended ()
        // {
        // }

        public void test_add_gap ()
        {
            var now = Ft.Timestamp.peek ();
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (now + Ft.Interval.MINUTE,
                                       now + 30 * Ft.Interval.MINUTE);

            var changed_emitted = 0;
            time_block.changed.connect (() => {
                changed_emitted++;
            });

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (time_block.start_time + 5 * Ft.Interval.MINUTE,
                                  Ft.Timestamp.UNDEFINED);

            // Expect that `Gap.time_block` is set and that `changed` signal is emitted.
            time_block.add_gap (gap_1);
            assert_true (gap_1.time_block == time_block);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 1);

            time_block.add_gap (gap_1);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 1);  // no change

            gap_1.end_time = time_block.start_time + 10 * Ft.Interval.MINUTE;
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 2);

            // Expect add_gap to keep gaps in order.
            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (time_block.start_time,
                                  time_block.start_time + Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);
            assert_true (time_block.get_last_gap () == gap_1);

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (time_block.start_time + 20 * Ft.Interval.MINUTE,
                                  time_block.start_time + 25 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_3);
            assert_true (time_block.get_last_gap () == gap_3);
        }

        public void test_normalize_gaps__invalid ()
        {
            var time_block = new Ft.TimeBlock ();

            var gap_valid = new Ft.Gap ();
            gap_valid.set_time_range (10 * Ft.Interval.MINUTE,
                                      20 * Ft.Interval.MINUTE);

            var gap_invalid_undefined_start = new Ft.Gap ();
            gap_invalid_undefined_start.set_time_range (Ft.Timestamp.UNDEFINED,
                                                        12 * Ft.Interval.MINUTE);

            var gap_invalid_end_before_start = new Ft.Gap ();
            gap_invalid_end_before_start.set_time_range (25 * Ft.Interval.MINUTE,
                                                         24 * Ft.Interval.MINUTE);

            time_block.add_gap (gap_valid);
            time_block.add_gap (gap_invalid_undefined_start);
            time_block.add_gap (gap_invalid_end_before_start);

            time_block.normalize_gaps ();

            // Expect only the valid gap to remain and to be unchanged
            var gaps_count = 0;

            time_block.foreach_gap (
                (gap) => {
                    if (gaps_count == 0)
                    {
                        assert_true (gap == gap_valid);
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (10 * Ft.Interval.MINUTE)
                        );
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.end_time),
                            new GLib.Variant.int64 (20 * Ft.Interval.MINUTE)
                        );
                    }

                    gaps_count++;
                });

            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_normalize_gaps__overlap ()
        {
            int gaps_count;
            // unowned Ft.Gap? gap;

            // Case 1: Two finite gaps overlapping. Expect them to be merged into one
            //         by extending the later gap backwards - preserving total duration.
            var time_block_1 = new Ft.TimeBlock ();

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (10 * Ft.Interval.MINUTE,
                                  20 * Ft.Interval.MINUTE);

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (18 * Ft.Interval.MINUTE,
                                  25 * Ft.Interval.MINUTE);

            time_block_1.add_gap (gap_1);
            time_block_1.add_gap (gap_2);

            time_block_1.normalize_gaps ();

            // Expect one gap to remain with start moved to 8 and end 25
            gaps_count = 0;

            time_block_1.foreach_gap (
                (gap) => {
                    if (gaps_count == 0)
                    {
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (8 * Ft.Interval.MINUTE)
                        );
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.end_time),
                            new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
                        );
                    }

                    gaps_count++;
                });

            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 1);

            // Case 2: Overlap with an ongoing (unfinished) next gap. Expect previous gap
            //         to be shifted back.
            var time_block_2 = new Ft.TimeBlock ();

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (10 * Ft.Interval.MINUTE,
                                  20 * Ft.Interval.MINUTE);

            var gap_4 = new Ft.Gap ();
            gap_4.set_time_range (18 * Ft.Interval.MINUTE,
                                  Ft.Timestamp.UNDEFINED);

            time_block_2.add_gap (gap_3);
            time_block_2.add_gap (gap_4);

            time_block_2.normalize_gaps ();

            gaps_count = 0;

            time_block_2.foreach_gap (
                (gap) => {
                    if (gaps_count == 0)
                    {
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (8 * Ft.Interval.MINUTE)
                        );
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.end_time),
                            new GLib.Variant.int64 (18 * Ft.Interval.MINUTE)
                        );
                    }

                    if (gaps_count == 1)
                    {
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (18 * Ft.Interval.MINUTE)
                        );
                        assert_true (Ft.Timestamp.is_undefined (gap.end_time));
                    }

                    gaps_count++;
                });

            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 2);
        }

        public void test_normalize_gaps__unfinished ()
        {
            // Unfinished (ongoing) gap not overlapping should remain unchanged
            var time_block = new Ft.TimeBlock ();

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (10 * Ft.Interval.MINUTE,
                                  15 * Ft.Interval.MINUTE);

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (20 * Ft.Interval.MINUTE,
                                  Ft.Timestamp.UNDEFINED);

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);

            time_block.normalize_gaps ();

            // Expect both gaps unchanged
            var gaps_count = 0;

            time_block.foreach_gap (
                (gap) => {
                    if (gaps_count == 0)
                    {
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (10 * Ft.Interval.MINUTE)
                        );
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.end_time),
                            new GLib.Variant.int64 (15 * Ft.Interval.MINUTE)
                        );
                    }

                    if (gaps_count == 1)
                    {
                        assert_cmpvariant (
                            new GLib.Variant.int64 (gap.start_time),
                            new GLib.Variant.int64 (20 * Ft.Interval.MINUTE)
                        );
                        assert_true (Ft.Timestamp.is_undefined (gap.end_time));
                    }

                    gaps_count++;
                });

            assert_cmpuint (gaps_count, GLib.CompareOperator.EQ, 2);
        }

        public void test_remove_gap ()
        {
            var now = Ft.Timestamp.peek ();
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (now + Ft.Interval.MINUTE,
                                       now + 30 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (time_block.start_time + 1 * Ft.Interval.MINUTE,
                                  time_block.start_time + 2 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_1);

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (time_block.start_time + 3 * Ft.Interval.MINUTE,
                                  time_block.start_time + 4 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (time_block.start_time + 5 * Ft.Interval.MINUTE,
                                  time_block.start_time + 6 * Ft.Interval.MINUTE);

            var changed_emitted = 0;
            time_block.changed.connect (() => {
                changed_emitted++;
            });

            time_block.remove_gap (gap_1);
            assert_null (gap_1.time_block);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 1);

            time_block.remove_gap (gap_1);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 1);

            time_block.remove_gap (gap_2);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 2);

            time_block.remove_gap (gap_3);
            assert_cmpuint (changed_emitted, GLib.CompareOperator.EQ, 2);  // no change
        }

        public void test_calculate_elapsed__without_gaps ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (
                5 * Ft.Interval.MINUTE,
                30 * Ft.Interval.MINUTE);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.start_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.start_time - Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time + Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (10 * Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (5 * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_elapsed__with_gaps ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (5 * Ft.Interval.MINUTE, 9 * Ft.Interval.MINUTE);  // 4 minutes

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (15 * Ft.Interval.MINUTE, 17 * Ft.Interval.MINUTE);  // 2 minutes

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (29 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);  // 1 minute

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);
            time_block.add_gap (gap_3);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.start_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_1.end_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.start_time - Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_3.start_time)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time + Ft.Interval.MINUTE)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_2.end_time)),
                new GLib.Variant.int64 ((10 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_2.start_time)),
                new GLib.Variant.int64 ((10 - 4) * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_elapsed__with_ongoing_gap ()
        {
            var now = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (now + 10 * Ft.Interval.MINUTE,
                                  Ft.Timestamp.UNDEFINED);
            time_block.add_gap (gap_1);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.start_time +
                                                                      Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_1.start_time)),
                new GLib.Variant.int64 (10 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time)),
                new GLib.Variant.int64 (10 * Ft.Interval.MINUTE)
            );

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (now + Ft.Interval.SECOND,
                                  now + 10 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (time_block.end_time)),
                new GLib.Variant.int64 (Ft.Interval.SECOND)
            );
        }

        public void test_calculate_elapsed__with_gaps_overlapping ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (7 * Ft.Interval.MINUTE, 11 * Ft.Interval.MINUTE);  // 4 minutes

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (10 * Ft.Interval.MINUTE, 13 * Ft.Interval.MINUTE);  // 3 minutes, 1 minute ovrlapping

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_1.end_time)),
                new GLib.Variant.int64 ((6 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_elapsed (gap_2.end_time)),
                new GLib.Variant.int64 ((8 - 4 - 3 + 1) * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_remaining__without_gaps ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.start_time)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.start_time - Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.end_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.end_time + Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (10 * Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (20 * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_remaining__with_gaps ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.STOPPED);
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (2 * Ft.Interval.MINUTE, 9 * Ft.Interval.MINUTE);  // 4 minutes

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (15 * Ft.Interval.MINUTE, 17 * Ft.Interval.MINUTE);  // 2 minutes

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (29 * Ft.Interval.MINUTE, 35 * Ft.Interval.MINUTE);  // 1 minute

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);
            time_block.add_gap (gap_3);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.start_time)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_1.end_time)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.start_time - Ft.Interval.MINUTE)),
                new GLib.Variant.int64 ((25 - 1 - 2 - 4) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.end_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_3.start_time)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.end_time + Ft.Interval.MINUTE)),
                new GLib.Variant.int64 (0 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.end_time)),
                new GLib.Variant.int64 ((13 - 1) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.start_time)),
                new GLib.Variant.int64 ((13 - 1) * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_remaining__with_ongoing_gap ()
        {
            var now = Ft.Timestamp.peek ();

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (now, now + 25 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (now + 1 * Ft.Interval.MINUTE,
                                  now + 5 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_1);
            time_block.duration += gap_1.duration;

            var gap_2 = new Ft.Gap.with_start_time (now + 10 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (time_block.start_time)),
                new GLib.Variant.int64 (25 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_1.start_time)),
                new GLib.Variant.int64 (24 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_1.end_time)),
                new GLib.Variant.int64 (24 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.start_time)),
                new GLib.Variant.int64 (19 * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.start_time + Ft.Interval.HOUR)),
                new GLib.Variant.int64 (19 * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_remaining__with_gaps_overlapping ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (7 * Ft.Interval.MINUTE, 11 * Ft.Interval.MINUTE);  // 4 minutes

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (10 * Ft.Interval.MINUTE, 13 * Ft.Interval.MINUTE);  // 3 minutes, 1 minute ovrlapping

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);

            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_1.start_time)),
                new GLib.Variant.int64 ((25 - 2 - 4 - 3 + 1) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_1.end_time)),
                new GLib.Variant.int64 ((25 - 6 - 3 + 1) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.start_time)),
                new GLib.Variant.int64 ((25 - 5 - 3) * Ft.Interval.MINUTE)
            );
            assert_cmpvariant (
                new GLib.Variant.int64 (time_block.calculate_remaining (gap_2.end_time)),
                new GLib.Variant.int64 ((25 - 8) * Ft.Interval.MINUTE)
            );
        }

        public void test_calculate_progress__without_gaps ()
        {
            var time_block = new Ft.TimeBlock ();
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.start_time),
                                          0.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.start_time - Ft.Interval.MINUTE),
                                          0.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.end_time),
                                          1.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.end_time + Ft.Interval.MINUTE),
                                          1.04,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (10 * Ft.Interval.MINUTE),
                                          0.2,
                                          0.0001);
        }

        public void test_calculate_progress__with_gaps ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.STOPPED);
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap_1 = new Ft.Gap ();
            gap_1.set_time_range (2 * Ft.Interval.MINUTE, 9 * Ft.Interval.MINUTE);  // 4 minutes

            var gap_2 = new Ft.Gap ();
            gap_2.set_time_range (15 * Ft.Interval.MINUTE, 17 * Ft.Interval.MINUTE);  // 2 minutes

            var gap_3 = new Ft.Gap ();
            gap_3.set_time_range (29 * Ft.Interval.MINUTE, 35 * Ft.Interval.MINUTE);  // 1 minute

            time_block.add_gap (gap_1);
            time_block.add_gap (gap_2);
            time_block.add_gap (gap_3);

            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.start_time),
                                          0.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap_1.end_time),
                                          0.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.start_time - Ft.Interval.MINUTE),
                                          0.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.end_time),
                                          1.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap_3.start_time),
                                          1.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (time_block.end_time + Ft.Interval.MINUTE),
                                          1.0,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap_2.end_time),
                                          0.3333,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap_2.start_time),
                                          0.3333,
                                          0.0001);
        }

        public void test_calculate_progress__with_ongoing_gap ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.STOPPED);
            time_block.set_time_range (5 * Ft.Interval.MINUTE, 30 * Ft.Interval.MINUTE);
            time_block.set_completion_time (25 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.IN_PROGRESS);

            var gap = new Ft.Gap ();
            gap.set_time_range (10 * Ft.Interval.MINUTE, Ft.Timestamp.UNDEFINED);

            time_block.add_gap (gap);

            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap.start_time),
                                          0.25,
                                          0.0001);
            assert_cmpfloat_with_epsilon (time_block.calculate_progress (gap.start_time + Ft.Interval.MINUTE),
                                          0.25,
                                          0.0001);
        }

        public void test_has_reached_completion ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.SHORT_BREAK);
            var completion_time = 3 * Ft.Interval.MINUTE + 45 * Ft.Interval.SECOND;

            time_block.set_time_range (0, 5 * Ft.Interval.MINUTE);

            assert_false (time_block.has_reached_completion (0));
            assert_false (time_block.has_reached_completion (completion_time));

            time_block.set_completion_time (completion_time);

            assert_false (time_block.has_reached_completion (0));
            assert_false (time_block.has_reached_completion (completion_time - Ft.Interval.SECOND));
            assert_true (time_block.has_reached_completion (completion_time));
            assert_true (time_block.has_reached_completion (5 * Ft.Interval.MINUTE));
        }

        public void test_has_reached_completion__with_ongoing_gap ()
        {
            var time_block = new Ft.TimeBlock (Ft.State.SHORT_BREAK);
            var completion_time = 4 * Ft.Interval.MINUTE;

            time_block.set_time_range (0, 10 * Ft.Interval.MINUTE);
            time_block.set_completion_time (completion_time);

            var gap = new Ft.Gap ();
            gap.set_time_range (2 * Ft.Interval.MINUTE, Ft.Timestamp.UNDEFINED);
            time_block.add_gap (gap);

            // Pause freezes the countdown before completion_time.
            assert_false (time_block.has_reached_completion (gap.start_time));
            assert_false (time_block.has_reached_completion (completion_time));
            assert_false (time_block.has_reached_completion (9 * Ft.Interval.MINUTE));

            gap.end_time = 3 * Ft.Interval.MINUTE;
            gap = new Ft.Gap ();
            gap.set_time_range (completion_time + Ft.Interval.MINUTE, Ft.Timestamp.UNDEFINED);
            time_block.add_gap (gap);

            // Pause after the countdown has already reached completion_time.
            assert_true (time_block.has_reached_completion (gap.start_time));
            assert_true (time_block.has_reached_completion (9 * Ft.Interval.MINUTE));
        }

        // public void test_changed_signal ()
        // {
        // }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.TimeBlockTest ()
    );
}
