/*
 * This file is part of focus-timer
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Tests
{
    public class BaseStatsManagerTest : Tests.MainLoopTestSuite
    {
        protected Ft.Timer?             timer;
        protected Ft.SessionManager?    session_manager;
        protected Ft.StatsManager?      stats_manager;
        protected Ft.TimezoneHistory?   timezone_history;
        protected Gom.Repository?       repository;

        public override void setup ()
        {
            base.setup ();

            Ft.Database.open ();

            var settings = Ft.get_settings ();
            settings.set_uint ("pomodoro-duration", 1500);
            settings.set_uint ("short-break-duration", 300);
            settings.set_uint ("long-break-duration", 900);
            settings.set_uint ("cycles", 4);
            settings.set_boolean ("confirm-starting-break", false);
            settings.set_boolean ("confirm-starting-pomodoro", false);

            this.repository = Ft.Database.get_repository ();
            this.timezone_history = new Ft.TimezoneHistory ();

            this.timer = new Ft.Timer ();
            Ft.Timer.set_default (this.timer);

            this.session_manager = new Ft.SessionManager.with_timer (this.timer);
            Ft.SessionManager.set_default (this.session_manager);

            this.stats_manager = new Ft.StatsManager ();
            assert (!this.stats_manager.get_data<bool> ("teardown"));
        }

        public override void teardown ()
        {
            this.timezone_history.clear_cache ();
            this.stats_manager.set_data<bool> ("teardown", true);

            this.stats_manager = null;
            this.session_manager = null;
            this.timer = null;
            this.timezone_history = null;
            this.repository = null;

            Ft.SessionManager.set_default (null);
            Ft.Timer.set_default (null);

            var settings = Ft.get_settings ();
            settings.revert ();

            Ft.Database.close ();

            base.teardown ();
        }

        protected Gom.ResourceGroup fetch (string date,
                                           string category) throws GLib.Error
        {
            var date_value = GLib.Value (typeof (string));
            date_value.set_string (date);

            var category_value = GLib.Value (typeof (string));
            category_value.set_string (category);

            var date_filter = new Gom.Filter.eq (
                    typeof (Ft.StatsEntry),
                    "date",
                    date_value);
            var category_filter = new Gom.Filter.eq (
                    typeof (Ft.StatsEntry),
                    "category",
                    category_value);
            var filter = new Gom.Filter.and (date_filter, category_filter);

            return this.repository.find_sync (typeof (Ft.StatsEntry), filter);
        }

        protected Ft.AggregatedStatsEntry? fetch_aggregated (string date,
                                                             string category) throws GLib.Error
        {
            var date_value = GLib.Value (typeof (string));
            date_value.set_string (date);

            var category_value = GLib.Value (typeof (string));
            category_value.set_string (category);

            var date_filter = new Gom.Filter.eq (
                    typeof (Ft.AggregatedStatsEntry),
                    "date",
                    date_value);
            var category_filter = new Gom.Filter.eq (
                    typeof (Ft.AggregatedStatsEntry),
                    "category",
                    category_value);
            var filter = new Gom.Filter.and (date_filter, category_filter);

            return (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                    typeof (Ft.AggregatedStatsEntry), filter);
        }

        protected uint count (string date,
                              string category) throws GLib.Error
        {
            try {
                var results = this.fetch (date, category);

                return results.count;
            }
            catch (GLib.Error error) {
                throw error;
            }
        }

        protected uint count_aggregated (string date,
                                         string category) throws GLib.Error
        {
            try {
                var aggregated_entry = this.fetch_aggregated (date, category);

                if (aggregated_entry == null) {
                    return 0U;
                }

                assert_true (aggregated_entry.count >= 0);

                return (uint) aggregated_entry.count;
            }
            catch (GLib.Error error) {
                throw error;
            }
        }

        protected int64 sum (string date,
                             string category) throws GLib.Error
        {
            try {
                var results = this.fetch (date, category);
                var duration = (int64) 0;

                results.fetch_sync (0U, results.count);

                for (var index = 0U; index < results.count; index++)
                {
                    var entry = (Ft.StatsEntry?) results.get_index (index);

                    duration += entry.duration;
                }

                return duration;
            }
            catch (GLib.Error error) {
                throw error;
            }
        }

        protected int64 sum_aggregated (string date,
                                        string category) throws GLib.Error
        {
            try {
                var aggregated_entry = this.fetch_aggregated (date, category);

                return aggregated_entry.duration;
            }
            catch (GLib.Error error) {
                throw error;
            }
        }
    }


    public class StatsManagerTest : BaseStatsManagerTest
    {
        private GLib.TimeZone? new_york_timezone;
        private GLib.TimeZone? london_timezone;
        private GLib.TimeZone? los_angeles_timezone;

        public StatsManagerTest ()
        {
            this.add_test ("track", this.test_track);
            this.add_test ("track__update", this.test_track__update);
            this.add_test ("track__many", this.test_track__many);
            this.add_test ("track__duplicate_1", this.test_track__duplicate_1);
            this.add_test ("track__duplicate_2", this.test_track__duplicate_2);

            this.add_test ("track_time_block__pomodoro_1",
                           this.test_track_time_block__pomodoro_1);
            this.add_test ("track_time_block__pomodoro_2",
                           this.test_track_time_block__pomodoro_2);
            this.add_test ("track_time_block__break",
                           this.test_track_time_block__break);
            this.add_test ("track_time_block__skip_unfinished",
                           this.test_track_time_block__skip_unfinished);
            this.add_test ("track_time_block__update",
                           this.test_track_time_block__update);

            this.add_test ("track_gap",
                           this.test_track_gap);
            this.add_test ("track_gap__skip_unfinished",
                           this.test_track_gap__skip_unfinished);
            this.add_test ("track_gap__skip_non_interruption",
                           this.test_track_gap__skip_non_interruption);
            this.add_test ("gap__update",
                           this.test_gap__update);

            this.add_test ("midnight_split__before_true_midnight",
                           this.test_midnight_split__before_true_midnight);
            this.add_test ("midnight_split__after_true_midnight",
                           this.test_midnight_split__after_true_midnight);
            this.add_test ("midnight_split__multiple_days",
                           this.test_midnight_split__multiple_days);
            this.add_test ("timezone_change__forward",
                           this.test_timezone_change__forward);
            this.add_test ("timezone_change__backward",
                           this.test_timezone_change__backward);
            this.add_test ("dst_change__forward",
                           this.test_dst_change__forward);
            this.add_test ("dst_change__backward",
                           this.test_dst_change__backward);
        }

        public override void setup ()
        {
            base.setup ();

            // Sat January 01 2000 08:00:00 UTC
            Ft.Timestamp.freeze_to (Ft.Timestamp.from_seconds_uint (946713600));

            try {
                this.new_york_timezone = new GLib.TimeZone.identifier ("America/New_York");  // 3 AM
                this.london_timezone = new GLib.TimeZone.identifier ("Europe/London");  // 8 AM
                this.los_angeles_timezone = new GLib.TimeZone.identifier ("America/Los_Angeles");  // 0 AM
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.timezone_history.insert (Ft.Timestamp.peek (), this.new_york_timezone);
        }

        private void run_flush ()
        {
            this.stats_manager.flush.begin (
                (obj, res) => {
                    this.stats_manager.flush.end (res);

                    this.quit_main_loop ();
                });

            assert_true (this.run_main_loop ());
        }

        public void test_track ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));
            var source_id = (int64) 12345;

            this.stats_manager.track ("test", timestamp, Ft.Interval.MINUTE, source_id);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), null);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                // Expect aggregated entries to be up to date
                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        aggregated_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.count),
                        new GLib.Variant.int64 (1));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track__many ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));
            timestamp += Ft.Interval.HOUR;

            this.stats_manager.track ("other",
                                      timestamp,
                                      2 * Ft.Interval.HOUR,
                                      (int64) 1);  // extra entry
            this.stats_manager.track ("test",
                                      timestamp,
                                      Ft.Interval.MINUTE,
                                      (int64) 2);

            timestamp += Ft.Interval.MINUTE;
            this.stats_manager.track ("test",
                                      timestamp,
                                      2 * Ft.Interval.MINUTE,
                                      (int64) 3);

            timestamp += Ft.Interval.MINUTE;
            this.stats_manager.track ("test",
                                      timestamp,
                                      Ft.Interval.HOUR,
                                      (int64) 4);

            timestamp += 24 * Ft.Interval.HOUR;
            this.stats_manager.track ("test",
                                      timestamp,
                                      2 * Ft.Interval.HOUR,
                                      (int64) 5);  // extra entry

            this.run_flush ();

            try {
                assert_cmpvariant (
                        new GLib.Variant.int64 (this.sum ("2000-01-01", "test")),
                        new GLib.Variant.int64 (Ft.Interval.HOUR + 3 * Ft.Interval.MINUTE));
                assert_cmpuint (
                        this.count ("2000-01-01", "test"),
                        GLib.CompareOperator.EQ,
                        3U);

                assert_cmpvariant (
                        new GLib.Variant.int64 (this.sum_aggregated ("2000-01-01", "test")),
                        new GLib.Variant.int64 (Ft.Interval.HOUR + 3 * Ft.Interval.MINUTE));
                assert_cmpuint (
                        this.count_aggregated ("2000-01-01", "test"),
                        GLib.CompareOperator.EQ,
                        3U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track__update ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            this.stats_manager.track (  // entry to keep
                    "test",
                    timestamp - 1,
                    Ft.Interval.MINUTE);
            this.stats_manager.track (
                    "test",
                    timestamp,
                    5 * Ft.Interval.MINUTE);
            this.run_flush ();

            this.stats_manager.track (
                    "test",
                    timestamp,
                    6 * Ft.Interval.MINUTE);
            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2);

                var time_value = GLib.Value (typeof (int64));
                time_value.set_int64 (timestamp);

                var time_filter = new Gom.Filter.eq (
                        typeof (Ft.StatsEntry),
                        "time",
                        time_value);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), time_filter);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (6 * Ft.Interval.MINUTE));

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 ((1 + 6) * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track__duplicate_1 ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));
            var source_id = 2;

            this.stats_manager.track (
                    "test",
                    timestamp,
                    Ft.Interval.MINUTE,
                    source_id);
            this.stats_manager.track (
                    "test",
                    timestamp,
                    Ft.Interval.MINUTE,
                    source_id);
            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track__duplicate_2 ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));
            var source_id = 2;

            this.stats_manager.track (
                    "test",
                    timestamp,
                    Ft.Interval.MINUTE,
                    source_id);
            this.run_flush ();

            this.stats_manager.track (
                    "test",
                    timestamp,
                    Ft.Interval.MINUTE,
                    source_id);
            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track_time_block__pomodoro_1 ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 5 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (timestamp + 1 * Ft.Interval.MINUTE,
                                timestamp + 3 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block);

            this.stats_manager.track_time_block (time_block);

            this.run_flush ();

            // Expect two entries for each continuous segment of pomodoro separated by a gap
            try {
                Gom.ResourceGroup results;

                var sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
                sorting.add (typeof (Ft.StatsEntry), "time", Gom.SortingMode.ASCENDING);

                results = this.repository.find_sorted_sync (typeof (Ft.StatsEntry),
                                                            null,
                                                            sorting);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.time),
                        new GLib.Variant.int64 (time_block.start_time));
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (1 * Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.time),
                        new GLib.Variant.int64 (gap.end_time));
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR +
                                                3 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (2 * Ft.Interval.MINUTE));

                // Expect aggregated entries to be up to date
                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpstr (
                        aggregated_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (3 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.count),
                        new GLib.Variant.int64 (1));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track_time_block__pomodoro_2 ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block_1 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_1.set_time_range (timestamp, timestamp + 5 * Ft.Interval.MINUTE);
            time_block_1.set_status (Ft.TimeBlockStatus.COMPLETED);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (timestamp + 1 * Ft.Interval.MINUTE,
                                  timestamp + 3 * Ft.Interval.MINUTE);
            time_block_1.add_gap (gap);

            // Second pomodoro later the same day
            var timestamp_2 = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 9, 0, 0));
            var time_block_2 = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block_2.set_time_range (timestamp_2, timestamp_2 + 10 * Ft.Interval.MINUTE);
            time_block_2.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block_1);
            session.append (time_block_2);

            this.stats_manager.track_time_block (time_block_1);
            this.stats_manager.track_time_block (time_block_2);

            this.run_flush ();

            try {
                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpstr (
                        aggregated_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (13 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.count),
                        new GLib.Variant.int64 (2));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Expect various brake types to be treated as just "break".
         */
        public void test_track_time_block__break ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.SHORT_BREAK);
            time_block.set_time_range (timestamp, timestamp + 5 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (timestamp + 1 * Ft.Interval.MINUTE,
                                timestamp + 3 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            var session = new Ft.Session ();
            session.append (time_block);

            this.stats_manager.track_time_block (time_block);

            this.run_flush ();

            // Expect two entries for each continuous segment of break separated by a gap
            try {
                Gom.ResourceGroup results;

                var sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
                sorting.add (typeof (Ft.StatsEntry), "time", Gom.SortingMode.ASCENDING);

                results = this.repository.find_sorted_sync (typeof (Ft.StatsEntry),
                                                            null,
                                                            sorting);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "break");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.time),
                        new GLib.Variant.int64 (time_block.start_time));
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (1 * Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "break");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.time),
                        new GLib.Variant.int64 (gap.end_time));
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR +
                                                3 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (2 * Ft.Interval.MINUTE));

                // Expect aggregated entries to be up to date
                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "break");
                assert_cmpstr (
                        aggregated_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (3 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Only track interruptions that have been finished.
         */
        public void test_track_time_block__skip_unfinished ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock.with_start_time (timestamp, Ft.State.POMODORO);
            time_block.end_time = Ft.Timestamp.UNDEFINED;

            var session = new Ft.Session ();
            session.append (time_block);

            this.stats_manager.track_time_block (time_block);

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track_time_block__update ()
        {
            Ft.StatsEntry? original_stats_entry = null;

            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 5 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block);

            this.stats_manager.track_time_block (time_block);
            this.run_flush ();

            try {
                original_stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), null);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Edit pomodoro
            time_block.set_time_range (timestamp, timestamp + 9 * Ft.Interval.MINUTE);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (timestamp + 4 * Ft.Interval.MINUTE,
                                timestamp + 6 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            this.stats_manager.track_time_block (time_block);
            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.source_id),
                        new GLib.Variant.int64 (original_stats_entry.source_id));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.id),
                        new GLib.Variant.int64 (original_stats_entry.id));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.time),
                        new GLib.Variant.int64 (time_block.start_time));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.source_id),
                        new GLib.Variant.int64 (original_stats_entry.source_id));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (3 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR +
                                                6 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.time),
                        new GLib.Variant.int64 (gap.end_time));

                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (7 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.count),
                        new GLib.Variant.int64 (1));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_track_gap ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block);

            var gap_1 = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap_1.set_time_range (time_block.start_time + 4 * Ft.Interval.MINUTE,
                                  time_block.start_time + 5 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_1);

            var gap_2 = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap_2.set_time_range (time_block.start_time + 6 * Ft.Interval.MINUTE,
                                  time_block.start_time + 10 * Ft.Interval.MINUTE);
            time_block.add_gap (gap_2);

            this.stats_manager.track_gap (gap_1);
            this.stats_manager.track_gap (gap_2);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR +
                                                4 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (7 * Ft.Interval.HOUR +
                                                6 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));

                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpstr (
                        aggregated_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (5 * Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.count),
                        new GLib.Variant.int64 (2));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Only track interruptions that have been finished.
         */
        public void test_track_gap__skip_unfinished ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block);

            var gap = new Ft.Gap.with_start_time (
                    time_block.start_time + 4 * Ft.Interval.MINUTE,
                    Ft.GapFlags.INTERRUPTION);
            time_block.add_gap (gap);

            this.stats_manager.track_gap (gap);

            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Only track interruptions.
         */
        public void test_track_gap__skip_non_interruption ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 7, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.BREAK);
            time_block.set_time_range (timestamp, timestamp + 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block);

            var gap = new Ft.Gap ();
            gap.set_time_range (time_block.start_time + 4 * Ft.Interval.MINUTE,
                                time_block.start_time + 5 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            this.stats_manager.track_gap (gap);

            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 0U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_gap__update ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            var time_block = new Ft.TimeBlock (Ft.State.POMODORO);
            time_block.set_time_range (timestamp, timestamp + 30 * Ft.Interval.MINUTE);
            time_block.set_status (Ft.TimeBlockStatus.COMPLETED);

            var session = new Ft.Session ();
            session.append (time_block);

            var gap = new Ft.Gap (Ft.GapFlags.INTERRUPTION);
            gap.set_time_range (time_block.start_time + 4 * Ft.Interval.MINUTE,
                                time_block.start_time + 5 * Ft.Interval.MINUTE);
            time_block.add_gap (gap);

            this.stats_manager.track_gap (gap);
            this.run_flush ();

            gap.set_time_range (time_block.start_time + 4 * Ft.Interval.MINUTE,
                                time_block.start_time + 6 * Ft.Interval.MINUTE);
            this.stats_manager.track_gap (gap);
            this.run_flush ();

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), null);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (2 * Ft.Interval.MINUTE));

                var aggregated_entry = (Ft.AggregatedStatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpstr (
                        aggregated_entry.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpvariant (
                        new GLib.Variant.int64 (aggregated_entry.duration),
                        new GLib.Variant.int64 (2 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Scenario for 23:00 - 04:30
         * Expect that time before 4 AM will be attributed to the previous day.
         */
        public void test_midnight_split__before_true_midnight ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 23, 0, 0));

            this.stats_manager.track (
                    "test",
                    timestamp,
                    5 * Ft.Interval.HOUR + 30 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (23 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (5 * Ft.Interval.HOUR));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-02");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (Ft.StatsManager.MIDNIGHT_OFFSET));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (30 * Ft.Interval.MINUTE));

                // Expect an aggregated entry for each day
                results = this.repository.find_sync (
                        typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var agg_stats_entry_1 = (Ft.AggregatedStatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        agg_stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        agg_stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (agg_stats_entry_1.duration),
                        new GLib.Variant.int64 (5 * Ft.Interval.HOUR));

                var agg_stats_entry_2 = (Ft.AggregatedStatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        agg_stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        agg_stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-02");
                assert_cmpvariant (
                        new GLib.Variant.int64 (agg_stats_entry_2.duration),
                        new GLib.Variant.int64 (30 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Scenario for 03:00 - 04:30
         * Expect that time before 4 AM will be attributed to the previous day.
         */
        public void test_midnight_split__after_true_midnight ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 3, 0, 0));

            this.stats_manager.track (
                    "test",
                    timestamp,
                    90 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "1999-12-31");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 ((24 + 3) * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.HOUR));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (Ft.StatsManager.MIDNIGHT_OFFSET));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (30 * Ft.Interval.MINUTE));

                // Expect an aggregated entry for each day
                results = this.repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var agg_stats_entry_1 = (Ft.AggregatedStatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        agg_stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        agg_stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "1999-12-31");
                assert_cmpvariant (
                        new GLib.Variant.int64 (agg_stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.HOUR));

                var agg_stats_entry_2 = (Ft.AggregatedStatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        agg_stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        agg_stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (agg_stats_entry_2.duration),
                        new GLib.Variant.int64 (30 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Scenario for Monday 09:00 - Friday 17:00
         */
        public void test_midnight_split__multiple_days ()
        {
            var start_time = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 3, 9, 0, 0));
            var end_time = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 7, 17, 0, 0));

            this.stats_manager.track ("test", start_time, end_time - start_time);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 5U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-03");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (9 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 ((24 - 9) * Ft.Interval.HOUR + Ft.StatsManager.MIDNIGHT_OFFSET));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-04");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 (Ft.StatsManager.MIDNIGHT_OFFSET));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (24 * Ft.Interval.HOUR));

                var stats_entry_5 = (Ft.StatsEntry?) results.get_index (4U);
                assert_cmpstr (
                        stats_entry_5.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_5.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-07");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_5.offset),
                        new GLib.Variant.int64 (Ft.StatsManager.MIDNIGHT_OFFSET));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_5.duration),
                        new GLib.Variant.int64 (17 * Ft.Interval.HOUR - Ft.StatsManager.MIDNIGHT_OFFSET));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Jump from America/New_York 12:01 to Europe/London 17:01
         */
        public void test_timezone_change__forward ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            this.timezone_history.insert (timestamp + Ft.Interval.MINUTE,
                                          this.london_timezone);

            this.stats_manager.track (
                    "test",
                    timestamp,
                    5 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (12 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 ((12 + 5) * Ft.Interval.HOUR +
                                                Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Jump from America/New_York 12:01 to America/Los_Angeles 09:01
         */
        public void test_timezone_change__backward ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            this.timezone_history.insert (timestamp + Ft.Interval.MINUTE,
                                          this.los_angeles_timezone);

            this.stats_manager.track (
                    "test",
                    timestamp,
                    5 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 (12 * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 ((12 - 3) * Ft.Interval.HOUR +
                                                Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Detect DST switch from 2:00 AM EST to 3:00 AM EDT
         */
        public void test_dst_change__forward ()
        {
            var dst_switch_time = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 4, 2, 2, 0, 0));

            this.stats_manager.track (
                    "test",
                    dst_switch_time - Ft.Interval.MINUTE,
                    5 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2000-04-01");  // adjusted to virtual midnight
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 ((24 + 2) * Ft.Interval.HOUR - Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2000-04-01");  // adjusted to virtual midnight
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 ((24 + 3) * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        /**
         * Detect DST switch from 2:00 AM EDT to 1:00 AM EST
         */
        public void test_dst_change__backward ()
        {
            var dst_switch_time = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2001, 10, 28, 0, 59, 59)) +
                    Ft.Interval.HOUR + Ft.Interval.SECOND;

            var current_timezone = this.timezone_history.search (dst_switch_time);
            assert_cmpstr (current_timezone.get_identifier (),
                           GLib.CompareOperator.EQ,
                           "America/New_York");

            this.stats_manager.track (
                    "test",
                    dst_switch_time - Ft.Interval.MINUTE,
                    5 * Ft.Interval.MINUTE);

            this.run_flush ();

            try {
                Gom.ResourceGroup results;

                results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                var stats_entry_1 = (Ft.StatsEntry?) results.get_index (0U);
                assert_cmpstr (
                        stats_entry_1.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_1.date,
                        GLib.CompareOperator.EQ,
                        "2001-10-27");  // adjusted to virtual midnight
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.offset),
                        new GLib.Variant.int64 ((24 + 2) * Ft.Interval.HOUR - Ft.Interval.MINUTE));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_1.duration),
                        new GLib.Variant.int64 (Ft.Interval.MINUTE));

                var stats_entry_2 = (Ft.StatsEntry?) results.get_index (1U);
                assert_cmpstr (
                        stats_entry_2.category,
                        GLib.CompareOperator.EQ,
                        "test");
                assert_cmpstr (
                        stats_entry_2.date,
                        GLib.CompareOperator.EQ,
                        "2001-10-27");  // adjusted to virtual midnight
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.offset),
                        new GLib.Variant.int64 ((24 + 1) * Ft.Interval.HOUR));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry_2.duration),
                        new GLib.Variant.int64 (4 * Ft.Interval.MINUTE));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }
    }


    public class StatsManagerSessionManagerTest : BaseStatsManagerTest
    {
        private GLib.TimeZone? new_york_timezone;

        public StatsManagerSessionManagerTest ()
        {
            this.add_test ("save__pomodoro",
                           this.test_save__pomodoro);
            this.add_test ("save__break",
                           this.test_save__break);
            this.add_test ("save__interruption",
                           this.test_save__interruption);
            this.add_test ("save__pomodoro_with_interruptions",
                           this.test_save__pomodoro_with_interruptions);
        }

        public override void setup ()
        {
            base.setup ();

            // Sat Jan 01 2000 08:00:00 UTC+0000
            Ft.Timestamp.freeze_to (Ft.Timestamp.from_seconds_uint (946713600));
            Ft.Timestamp.set_auto_advance (Ft.Interval.MICROSECOND);

            try {
                this.new_york_timezone = new GLib.TimeZone.identifier ("America/New_York");  // 3 AM
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            this.timezone_history.insert (Ft.Timestamp.peek (), this.new_york_timezone);
        }

        private void run_save ()
        {
            this.session_manager.save.begin (
                (obj, res) => {
                    assert_true (this.session_manager.save.end (res));

                    this.quit_main_loop ();
                });
            assert_true (this.run_main_loop ());

            this.stats_manager.flush.begin (
                (obj, res) => {
                    this.stats_manager.flush.end (res);

                    this.quit_main_loop ();
                });
            assert_true (this.run_main_loop ());
        }

        public void test_save__pomodoro ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            Ft.Timestamp.freeze_to (timestamp);

            this.session_manager.advance_to_state (Ft.State.POMODORO);
            this.session_manager.advance (this.session_manager.current_time_block.end_time);

            var time_block = this.session_manager.current_session.get_first_time_block ();
            var time_block_saved_emitted = 0U;

            this.session_manager.time_block_saved.connect (
                () => {
                    time_block_saved_emitted++;
                });

            this.run_save ();
            assert_cmpuint (time_block_saved_emitted, GLib.CompareOperator.EQ, 2U);

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), null);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "pomodoro");
                assert_cmpstr (
                        stats_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (time_block.duration));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.offset),
                        new GLib.Variant.int64 (12 * Ft.Interval.HOUR));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__break ()
        {
            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            Ft.Timestamp.freeze_to (timestamp);

            this.session_manager.advance_to_state (Ft.State.SHORT_BREAK);
            this.session_manager.advance (this.session_manager.current_time_block.end_time);

            var time_block = this.session_manager.current_session.get_first_time_block ();
            var time_block_saved_emitted = 0U;

            this.session_manager.time_block_saved.connect (
                (time_block, time_block_entry) => {
                    time_block_saved_emitted++;
                });

            this.run_save ();
            assert_cmpuint (time_block_saved_emitted, GLib.CompareOperator.EQ, 2U);

            try {
                var results = this.repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), null);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "break");
                assert_cmpstr (
                        stats_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (time_block.duration));
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.offset),
                        new GLib.Variant.int64 (12 * Ft.Interval.HOUR));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__interruption ()
        {
            var timer_action_group = new Ft.TimerActionGroup.with_timer (this.timer);

            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            var time_block_saved_emitted = 0U;
            var gap_saved_emitted = 0U;

            this.session_manager.time_block_saved.connect (
                (time_block, time_block_entry) => {
                    time_block_saved_emitted++;
                });
            this.session_manager.gap_saved.connect (
                (gap, gap_entry) => {
                    gap_saved_emitted++;
                });

            Ft.Timestamp.freeze_to (timestamp);
            timer_action_group.activate_action ("start", null);

            Ft.Timestamp.freeze_to (timestamp + 5 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("pause", null);

            Ft.Timestamp.freeze_to (timestamp + 6 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("resume", null);

            this.run_save ();
            assert_cmpuint (time_block_saved_emitted, GLib.CompareOperator.EQ, 1U);
            assert_cmpuint (gap_saved_emitted, GLib.CompareOperator.EQ, 1U);

            var time_block = this.session_manager.current_time_block;
            var gap = time_block.get_last_gap ();

            try {
                var category_value = GLib.Value (typeof (string));
                category_value.set_string ("pomodoro");

                var category_filter = new Gom.Filter.neq (
                        typeof (Ft.StatsEntry),
                        "category",
                        category_value);

                var results = this.repository.find_sync (typeof (Ft.StatsEntry), category_filter);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 1U);

                var stats_entry = (Ft.StatsEntry?) this.repository.find_one_sync (
                        typeof (Ft.StatsEntry), category_filter);
                assert_cmpstr (
                        stats_entry.category,
                        GLib.CompareOperator.EQ,
                        "interruption");
                assert_cmpstr (
                        stats_entry.date,
                        GLib.CompareOperator.EQ,
                        "2000-01-01");
                assert_cmpvariant (
                        new GLib.Variant.int64 (stats_entry.duration),
                        new GLib.Variant.int64 (gap.duration));
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public void test_save__pomodoro_with_interruptions ()
        {
            var timer_action_group = new Ft.TimerActionGroup.with_timer (this.timer);

            var timestamp = Ft.Timestamp.from_datetime (
                    new GLib.DateTime (this.new_york_timezone, 2000, 1, 1, 12, 0, 0));

            Ft.Timestamp.freeze_to (timestamp);
            this.session_manager.advance_to_state (Ft.State.POMODORO);

            // First interruption: 12:02 - 12:03
            Ft.Timestamp.freeze_to (timestamp + 2 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("pause", null);

            Ft.Timestamp.freeze_to (timestamp + 3 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("resume", null);

            // Second interruption: 12:10 - 12:11
            Ft.Timestamp.freeze_to (timestamp + 10 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("pause", null);

            Ft.Timestamp.freeze_to (timestamp + 11 * Ft.Interval.MINUTE);
            timer_action_group.activate_action ("resume", null);

            // Mark the time-block end at its scheduled end time

            this.session_manager.advance (this.session_manager.current_time_block.end_time);

            this.run_save ();

            try {
                assert_cmpuint (this.count ("2000-01-01", "pomodoro"),
                                GLib.CompareOperator.EQ,
                                3U);
                assert_cmpuint (this.count ("2000-01-01", "interruption"),
                                GLib.CompareOperator.EQ,
                                2U);

                assert_cmpuint (this.count_aggregated ("2000-01-01", "pomodoro"),
                                GLib.CompareOperator.EQ,
                                1U);
                assert_cmpuint (this.count_aggregated ("2000-01-01", "interruption"),
                                GLib.CompareOperator.EQ,
                                2U);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.StatsManagerTest (),
        new Tests.StatsManagerSessionManagerTest ()
    );
}
