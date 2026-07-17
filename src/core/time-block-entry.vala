/*
 * Copyright (c) 2021-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    public class TimeBlockEntry : Gom.Resource
    {
        public int64 id { get; set; }
        public int64 session_id { get; set; }
        public int64 start_time { get; set; }
        public int64 end_time { get; set; }
        public string state { get; set; }
        public string status { get; set; }
        public int64 intended_duration { get; set; }
        public string task { get; set; default = ""; }

        internal ulong version = 0;

        static construct
        {
            set_table ("timeblocks");
            set_primary_key ("id");
            set_notnull ("session-id");
            set_notnull ("start-time");
            set_notnull ("end-time");
            set_notnull ("state");
            set_notnull ("status");
            set_notnull ("intended-duration");
            set_unique ("start-time");
            set_reference ("session-id", "sessions", "id");
        }
    }
}
