/*
 * Copyright (c) 2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    public class StatsEntry : Gom.Resource
    {
        public int64 id { get; set; }
        public int64 time { get; set; }
        public string date { get; set; }
        public int64 offset { get; set; }
        public int64 duration { get; set; }
        public string category { get; set; }
        public int64 source_id { get; set; default = 0; }
        public string task { get; set; default = ""; }

        static construct
        {
            set_table ("stats");
            set_primary_key ("id");
            set_notnull ("time");
            set_notnull ("date");
            set_notnull ("offset");
            set_notnull ("category");

            // `source-id` may reference `timeblocks` and `gaps` tables.
            // Therefore, we treat it like an integer.
        }

        public Ft.StatsEntry copy ()
        {
            return (Ft.StatsEntry) GLib.Object.@new (
                    typeof (Ft.StatsEntry),
                    id: this.id,
                    time: this.time,
                    date: this.date,
                    offset: this.offset,
                    duration: this.duration,
                    category: this.category,
                    source_id: this.source_id,
                    task: this.task);
        }
    }


    /**
     * Model for aggregated daily stats
     */
    public class AggregatedStatsEntry : Gom.Resource
    {
        public int64 id { get; set; }
        public string date { get; set; }
        public string category { get; set; }
        public int64 duration { get; set; }
        public int64 count { get; set; }

        static construct
        {
            set_table ("aggregatedstats");
            set_primary_key ("id");
            set_notnull ("date");
            set_notnull ("category");
        }
    }
}
