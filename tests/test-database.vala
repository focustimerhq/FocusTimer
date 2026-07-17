/*
 * This file is part of focus-timer
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Tests
{
    public class DatabaseMigrationTest : Tests.TestSuite
    {
        private Gom.Adapter?    adapter = null;
        private Gom.Repository? repository = null;
        private GLib.MainLoop?  main_loop = null;
        private uint            timeout_id = 0;

        public DatabaseMigrationTest ()
        {
            this.add_test ("migrate_to_v3", this.test_migrate_to_v3);
        }

        public override void setup ()
        {
            this.main_loop = new GLib.MainLoop ();
            this.adapter = new Gom.Adapter ();

            try {
                adapter.open_sync (":memory:");

                this.repository = new Gom.Repository (adapter);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }
        }

        public override void teardown ()
        {
            try {
                this.adapter.close_sync ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while closing database: %s", error.message);
            }

            this.main_loop = null;
            this.adapter = null;
            this.repository = null;
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

        private bool table_exists (string table_name)
        {
            var exists = true;

            this.adapter.queue_read (() => {
                try {
                    this.adapter.execute_sql ("SELECT 1 FROM '" + table_name + "' LIMIT 1;");
                    exists = true;
                }
                catch (GLib.Error error) {
                    exists = false;
                }

                GLib.Idle.add (() => { this.quit_main_loop (); return GLib.Source.REMOVE; });
            });

            assert_true (this.run_main_loop ());

            return exists;
        }

        public void test_migrate_to_v3 ()
        {
            // Apply v1 and v2 migrations
            try {
                this.repository.migrate_sync (2U, Ft.Database.migrate_repository);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Insert legacy data into entries (durations in seconds)
            this.adapter.queue_write (() => {
                try {
                    // 2000-01-01 03:00:00 (UTC and local), duration 120s, pomodoro
                    this.adapter.execute_sql (
                        "INSERT INTO \"entries\" (\"datetime-string\", \"datetime-local-string\", \"state-name\", \"state-duration\", \"elapsed\") " +
                        "VALUES ('2000-01-01 03:00:00', '2000-01-01 03:00:00', 'pomodoro', 120, 120);");

                    // 2000-01-01 12:34:56 (UTC and local), duration 300s, short-break -> break
                    this.adapter.execute_sql (
                        "INSERT INTO \"entries\" (\"datetime-string\", \"datetime-local-string\", \"state-name\", \"state-duration\", \"elapsed\") " +
                        "VALUES ('2000-01-01 12:34:56', '2000-01-01 12:34:56', 'short-break', 300, 300);");
                }
                catch (GLib.Error error) {
                    GLib.critical ("%s", error.message);
                }

                GLib.Idle.add (() => { this.quit_main_loop (); return GLib.Source.REMOVE; });
            });

            assert_true (this.run_main_loop ());

            // Apply v3 migration (populate stats and drop legacy tables)
            // and v4 migration (add task columns), so that the schema matches
            // the current Gom resources before querying.
            try {
                repository.migrate_sync (3U, Ft.Database.migrate_repository);
                repository.migrate_sync (4U, Ft.Database.migrate_repository);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Verify stats entries
            try {
                var results = repository.find_sync (typeof (Ft.StatsEntry), null);
                assert_cmpuint (results.count, GLib.CompareOperator.EQ, 2U);

                results.fetch_sync (0U, results.count);

                // Find pomodoro entry
                Ft.StatsEntry? pomodoro_entry = null;
                Ft.StatsEntry? break_entry = null;

                for (var index = 0; index < results.count; index++)
                {
                    var entry = (Ft.StatsEntry?) results.get_index (index);

                    if (entry.category == "pomodoro") {
                        pomodoro_entry = entry;
                    }
                    else if (entry.category == "break") {
                        break_entry = entry;
                    }
                }

                assert_nonnull (pomodoro_entry);
                assert_nonnull (break_entry);

                // time = epoch micros of UTC datetime-string
                assert_cmpstr (pomodoro_entry.date, GLib.CompareOperator.EQ, "1999-12-31");
                assert_cmpvariant (new GLib.Variant.int64 (pomodoro_entry.offset),
                                   new GLib.Variant.int64 ((24 + 3) * Ft.Interval.HOUR));
                assert_cmpvariant (new GLib.Variant.int64 (pomodoro_entry.duration),
                                   new GLib.Variant.int64 (120 * Ft.Interval.SECOND));

                assert_cmpstr (break_entry.date, GLib.CompareOperator.EQ, "2000-01-01");
                assert_cmpvariant (new GLib.Variant.int64 (break_entry.offset),
                                   new GLib.Variant.int64 (12 * Ft.Interval.HOUR +
                                                           34 * Ft.Interval.MINUTE +
                                                           56 * Ft.Interval.SECOND));
                assert_cmpvariant (new GLib.Variant.int64 (break_entry.duration),
                                   new GLib.Variant.int64 (300 * Ft.Interval.SECOND));

                // Aggregated stats should also be updated by triggers
                var agg_results = repository.find_sync (typeof (Ft.AggregatedStatsEntry), null);
                agg_results.fetch_sync (0U, agg_results.count);

                var found_pomodoro_agg = false;
                var found_break_agg = false;

                for (var index = 0; index < agg_results.count; index++)
                {
                    var aggregated_entry = (Ft.AggregatedStatsEntry?) agg_results.get_index (index);

                    if (aggregated_entry.category == "pomodoro") {
                        found_pomodoro_agg = true;
                        assert_cmpstr (aggregated_entry.date, GLib.CompareOperator.EQ, "1999-12-31");
                        assert_cmpvariant (new GLib.Variant.int64 (aggregated_entry.duration),
                                           new GLib.Variant.int64 (120 * Ft.Interval.SECOND));
                    }
                    else if (aggregated_entry.category == "break") {
                        found_break_agg = true;
                        assert_cmpstr (aggregated_entry.date, GLib.CompareOperator.EQ, "2000-01-01");
                        assert_cmpvariant (new GLib.Variant.int64 (aggregated_entry.duration),
                                           new GLib.Variant.int64 (300 * Ft.Interval.SECOND));
                    }
                }

                assert_true (found_pomodoro_agg);
                assert_true (found_break_agg);
            }
            catch (GLib.Error error) {
                assert_no_error (error);
            }

            // Verify legacy tables are dropped
            assert_false (this.table_exists ("entries"));
            assert_false (this.table_exists ("aggregated-entries"));
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.DatabaseMigrationTest ()
    );
}


