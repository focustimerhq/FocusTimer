/*
 * Copyright (c) 2021-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    /**
     * Ft.TimeBlockStatus enum.
     *
     * A time-block status is managed at a session-level by `SessionManager`.
     */
    public enum TimeBlockStatus
    {
        SCHEDULED = 0,
        IN_PROGRESS = 1,
        COMPLETED = 2,
        UNCOMPLETED = 3;

        public string to_string ()
        {
            switch (this)
            {
                case SCHEDULED:
                    return "scheduled";

                case IN_PROGRESS:
                    return "in-progress";

                case COMPLETED:
                    return "completed";

                case UNCOMPLETED:
                    return "uncompleted";

                default:
                    assert_not_reached ();
            }
        }

        public static Ft.TimeBlockStatus from_string (string? status)
        {
            switch (status)
            {
                case "in-progress":
                    return IN_PROGRESS;

                case "completed":
                    return COMPLETED;

                case "uncompleted":
                    return UNCOMPLETED;

                default:
                    return SCHEDULED;
            }
        }
    }


    /**
     * Ft.TimeBlockMeta struct.
     *
     * Some properties of the `TimeBlock` are purely external and should not trigger
     * `TimeBlock.changed` signal. `TimeBlockMeta` is a convenience structure for read-only.
     */
    public struct TimeBlockMeta
    {
        public Ft.TimeBlockStatus status;
        public int64                    intended_duration;
        public double                   weight;
        public int64                    completion_time;
    }


    public interface Schedulable : GLib.Object
    {
        public abstract int64 start_time { get; set; }
        public abstract int64 end_time { get; set; }
        public abstract int64 duration { get; set; }

        public bool has_started (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            var start_time = this.start_time;

            if (Ft.Timestamp.is_undefined (start_time)) {
                return true;
            }

            Ft.ensure_timestamp (ref timestamp);

            return timestamp >= start_time;
        }

        public bool has_ended (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            var end_time = this.end_time;

            if (Ft.Timestamp.is_undefined (end_time)) {
                return false;
            }

            Ft.ensure_timestamp (ref timestamp);

            return timestamp > end_time;
        }

        public static int compare (Ft.Schedulable a,
                                   Ft.Schedulable b)
        {
            return (int) (a.start_time > b.start_time) - (int) (a.start_time < b.start_time);
        }

        public abstract void set_time_range (int64 start_time,
                                             int64 end_time);

        public abstract void move_by (int64 offset);

        public abstract void move_to (int64 start_time);
    }


    public class TimeBlock : GLib.InitiallyUnowned, Ft.Schedulable
    {
        public Ft.State state {
            get {
                return this._state;
            }
            construct {
                this._state = value;
            }
        }
        public weak Ft.Session session { get; set; }

        [CCode (notify = false)]
        public int64 start_time {
            get {
                return this._start_time;
            }
            set {
                if (this._start_time == value) {
                    return;
                }

                if (Ft.Timestamp.is_undefined (value) ||
                    Ft.Timestamp.is_undefined (this._end_time) ||
                    value <= this._end_time)
                {
                    this.set_time_range (value, this._end_time);
                }
                else {
                    this.set_time_range (value, value);
                }
            }
        }

        [CCode (notify = false)]
        public int64 end_time {
            get {
                return this._end_time;
            }
            set {
                if (this._end_time == value) {
                    return;
                }

                if (Ft.Timestamp.is_undefined (value) ||
                    Ft.Timestamp.is_undefined (this._start_time) ||
                    value >= this._start_time)
                {
                    this.set_time_range (this._start_time, value);
                }
                else {
                    this.set_time_range (value, value);
                }
            }
        }

        /**
         * `duration` of a time block, including gaps
         */
        [CCode (notify = false)]
        public int64 duration {
            get {
                return Ft.Timestamp.subtract (this._end_time, this._start_time);
            }
            set {
                if (Ft.Timestamp.is_defined (this._start_time)) {
                    this.set_time_range (this._start_time,
                                         Ft.Timestamp.add_interval (this._start_time, value));
                }
                else {
                    GLib.warning ("Can't change time-block duration without a defined start-time.");
                }
            }
        }

        internal ulong              version = 0;
        internal Ft.TimeBlockEntry? entry = null;

        private GLib.List<Ft.Gap>   gaps = null;
        private int64               _start_time = Ft.Timestamp.UNDEFINED;
        private int64               _end_time = Ft.Timestamp.UNDEFINED;
        private Ft.State            _state = Ft.State.STOPPED;
        private int                 changed_freeze_count = 0;
        private bool                changed_is_pending = false;
        private Ft.TimeBlockMeta    meta;
        private string              task = "";

        construct
        {
            this.meta = Ft.TimeBlockMeta() {
                status = Ft.TimeBlockStatus.SCHEDULED,
                intended_duration = 0,
                weight = double.NAN,
                completion_time = Ft.Timestamp.UNDEFINED
            };
        }

        public TimeBlock (Ft.State state = Ft.State.STOPPED)
        {
            GLib.Object (
                state: state
            );
        }

        public TimeBlock.with_start_time (int64          start_time,
                                          Ft.State state = Ft.State.STOPPED)
        {
            GLib.Object (
                state: state
            );

            this.set_time_range (
                start_time,
                Ft.Timestamp.add_interval (start_time, state.get_default_duration ())
            );
        }

        private void emit_changed ()
        {
            this.version++;

            if (this.changed_freeze_count > 0) {
                this.changed_is_pending = true;
            }
            else {
                this.changed_is_pending = false;
                this.changed ();
            }
        }

        /**
         * Increases the freeze count on this.
         */
        public void freeze_changed ()
        {
            this.changed_freeze_count++;
        }

        /**
         * Decrease the freeze count on this.
         */
        public void thaw_changed ()
        {
            this.changed_freeze_count--;

            if (this.changed_freeze_count == 0) {
                this.emit_changed ();
            }
        }

        public void set_time_range (int64 start_time,
                                    int64 end_time)
        {
            var old_start_time = this._start_time;
            var old_end_time = this._end_time;
            var old_duration = this._end_time - this._start_time;
            var changed = false;

            this._start_time = start_time;
            this._end_time = end_time;

            if (this._start_time != old_start_time) {
                this.notify_property ("start-time");
                changed = true;
            }

            if (this._end_time != old_end_time) {
                this.notify_property ("end-time");
                changed = true;
            }

            if (this._end_time - this._start_time != old_duration) {
                this.notify_property ("duration");
            }

            if (changed) {
                this.emit_changed ();
            }
        }

        public void move_by (int64 offset)
        {
            if (offset == 0) {
                return;
            }

            var start_time = Ft.Timestamp.is_defined (this._start_time)
                    ? Ft.Timestamp.add_interval (this._start_time, offset)
                    : Ft.Timestamp.UNDEFINED;
            var end_time = Ft.Timestamp.is_defined (this._end_time)
                    ? Ft.Timestamp.add_interval (this._end_time, offset)
                    : Ft.Timestamp.UNDEFINED;

            this.freeze_changed ();
            this.gaps.@foreach ((gap) => gap.move_by (offset));
            this.set_time_range (start_time, end_time);
            this.thaw_changed ();
        }

        public void move_to (int64 start_time)
        {
            if (Ft.Timestamp.is_undefined (this._start_time) &&
                Ft.Timestamp.is_undefined (this._end_time))
            {
                if (!this.gaps.is_empty ()) {
                    GLib.warning ("Unable to move time-block gaps. Time-block start-time is undefined.");
                }

                this.set_time_range (start_time, this._end_time);
                return;
            }

            if (Ft.Timestamp.is_undefined (this._start_time)) {
                GLib.warning ("Unable to move time-block. Time-block start-time is undefined.");
                return;
            }

            this.move_by (Ft.Timestamp.subtract (start_time, this._start_time));
        }

        /**
         * Calculate elapsed time excluding gaps/interruptions.
         */
        public int64 calculate_elapsed (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            if (Ft.Timestamp.is_undefined (this._start_time)) {
                return 0;  // Result won't make sense if block has no `start`.
            }

            if (this._start_time >= timestamp || this._start_time >= this._end_time) {
                return 0;
            }

            var range_start = this._start_time;
            var range_end   = Ft.Timestamp.is_defined (this._end_time)
                    ? int64.min (this._end_time, timestamp)
                    : timestamp;
            var elapsed     = Ft.Timestamp.subtract (range_end, range_start);

            this.gaps.@foreach (
                (gap) => {
                    var gap_start_time = gap.start_time.clamp (range_start, range_end);
                    var gap_end_time = gap.end_time;

                    if (Ft.Timestamp.is_undefined (gap_end_time)) {
                        gap_end_time = range_end;
                    }
                    else if (gap_end_time > gap_start_time) {
                        gap_end_time = gap_end_time.clamp (range_start, range_end);
                    }
                    else {
                        return;
                    }

                    elapsed = Ft.Interval.subtract (
                            elapsed,
                            Ft.Timestamp.subtract (gap_end_time, gap_start_time));
                    range_start = gap_end_time;
                });

            return elapsed;
        }

        /**
         * Calculate remaining time excluding gaps/interruptions.
         */
        public int64 calculate_remaining (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            Ft.ensure_timestamp (ref timestamp);

            if (Ft.Timestamp.is_undefined (this._end_time)) {
                return 0;  // Result won't make sense if block has no `end`.
            }

            var last_gap = this.get_last_gap ();

            if (last_gap != null && Ft.Timestamp.is_undefined (last_gap.end_time)) {
                timestamp = int64.min (last_gap.start_time, timestamp);
            }

            var range_start = int64.max (this._start_time, timestamp);
            var range_end   = this._end_time;
            var remaining   = Ft.Timestamp.subtract (range_end, range_start);

            this.gaps.@foreach (
                (gap) => {
                    var gap_start_time = gap.start_time.clamp (range_start, range_end);
                    var gap_end_time = gap.end_time;

                    if (Ft.Timestamp.is_undefined (gap_end_time) ||
                        gap_start_time >= gap_end_time)
                    {
                        return;
                    }

                    gap_end_time = gap_end_time.clamp (range_start, range_end);

                    remaining = Ft.Interval.subtract (
                            remaining,
                            Ft.Timestamp.subtract (gap_end_time, gap_start_time));
                    range_start = gap_end_time.clamp (range_start, range_end);
                });

            return int64.max (remaining, 0);
        }

        /**
         * Calculate progress - elapsed time compared to completion-time.
         */
        public double calculate_progress (int64 timestamp)
        {
            Ft.ensure_timestamp (ref timestamp);

            if (this.meta.status == Ft.TimeBlockStatus.SCHEDULED ||
                this.meta.status == Ft.TimeBlockStatus.UNCOMPLETED)
            {
                return 0.0;
            }

            if (this.meta.status == Ft.TimeBlockStatus.COMPLETED) {
                return 1.0;
            }

            if (Ft.Timestamp.is_undefined (this._start_time) ||
                Ft.Timestamp.is_undefined (this._end_time))
            {
                return 0.0;  // Result won't make sense if block has no `start`.
            }

            if (this._start_time >= timestamp || this._start_time >= this._end_time) {
                return 0.0;
            }

            var range_start = this._start_time;
            var range_end   = Ft.Timestamp.is_defined (this.meta.completion_time)
                ? this.meta.completion_time
                : this._end_time;
            var duration = Ft.Timestamp.subtract (range_end, range_start);
            var elapsed  = Ft.Timestamp.subtract (timestamp, range_start);

            this.gaps.@foreach (
                (gap) => {
                    if (Ft.Timestamp.is_undefined (gap.end_time)) {
                        elapsed = Ft.Interval.subtract (
                            elapsed,
                            Ft.Timestamp.subtract (
                                timestamp,
                                gap.start_time.clamp (range_start, timestamp)
                            )
                        );
                        range_start = range_end;
                        return;
                    }

                    if (gap.end_time <= gap.start_time) {
                        return;
                    }

                    duration = Ft.Interval.subtract (
                        duration,
                        Ft.Timestamp.subtract (
                            gap.end_time.clamp (range_start, range_end),
                            gap.start_time.clamp (range_start, range_end)
                        )
                    );
                    elapsed = Ft.Interval.subtract (
                        elapsed,
                        Ft.Timestamp.subtract (
                            gap.end_time.clamp (range_start, timestamp),
                            gap.start_time.clamp (range_start, timestamp)
                        )
                    );
                    range_start = gap.end_time.clamp (range_start, range_end);
                }
            );

            return duration > 0 ? (double) elapsed / (double) duration : 0.0;
        }

        private void on_gap_changed (Ft.Gap gap)
        {
            this.emit_changed ();
        }

        public void add_gap (Ft.Gap gap)
        {
            if (gap.time_block == this) {
                return;
            }

            if (gap.time_block != null) {
                gap.time_block.remove_gap (gap);
            }

            gap.time_block = this;
            gap.changed.connect (this.on_gap_changed);

            this.gaps.insert_sorted (gap, Ft.Schedulable.compare);

            this.emit_changed ();
        }

        public void remove_gap (Ft.Gap gap)
        {
            if (gap.time_block != this) {
                return;
            }

            gap.changed.disconnect (this.on_gap_changed);
            gap.time_block = null;

            this.gaps.remove (gap);

            this.emit_changed ();
        }

        public unowned Ft.Gap? get_last_gap ()
        {
            unowned GLib.List<Ft.Gap> link = this.gaps.last ();

            return link != null ? link.data : null;
        }

        public unowned Ft.Gap? get_nth_gap (uint index)
        {
            return this.gaps.nth_data (index);
        }

        public void foreach_gap (GLib.Func<unowned Ft.Gap> func)
        {
            this.gaps.@foreach (func);
        }

        private void remove_link (GLib.List<Ft.Gap>? link)
        {
            if (link == null) {
                return;
            }

            link.data = null;
            this.gaps.delete_link (link);
        }

        /**
         * Cleanup gaps.
         *
         * Handling of overlapped gaps is tailored for the rewind action.
         */
        public void normalize_gaps ()
        {
            unowned GLib.List<Ft.Gap> link = this.gaps.last ();
            unowned GLib.List<Ft.Gap> tmp;
            var changed = false;

            this.freeze_changed ();

            // assume that gaps are sorted

            while (link != null)
            {
                // Remove invalid gaps.
                if (Ft.Timestamp.is_defined (link.data.end_time) && link.data.end_time < link.data.start_time ||
                    Ft.Timestamp.is_undefined (link.data.start_time))
                {
                    GLib.debug ("normalize_gaps: removing invalid gap");
                    tmp = link.prev;
                    this.remove_link (link);
                    link = tmp;
                    changed = true;
                    continue;
                }

                // Handle overlapping gaps.
                if (link.next != null && link.data.end_time > link.next.data.start_time)
                {
                    var overlap = link.data.end_time - link.next.data.start_time;

                    if (Ft.Timestamp.is_undefined (link.next.data.end_time)) {
                        link.data.move_by (-overlap);
                        link = link.prev;
                        changed = overlap > 0 ? true : changed;
                    }
                    else {
                        tmp = link.prev;
                        link.next.data.start_time = Ft.Timestamp.subtract_interval (link.data.start_time, overlap);
                        this.remove_link (link);
                        link = tmp;
                        changed = true;
                    }

                    continue;
                }

                link = link.prev;
            }

            if (changed) {
                this.emit_changed ();
            }

            this.thaw_changed ();
        }

        /**
         * We don't allow changing of `TimeBlock.state` after the time-block changes status to in-progress.
         * However, it's allowed to change state of a scheduled time-block.
         */
        internal void set_state_internal (Ft.State state)
        {
            if (this._state == state) {
                return;
            }

            this._state = state;
            this.notify_property ("state");

            this.emit_changed ();
        }


        /*
         * Metadata
         */

        public Ft.TimeBlockMeta get_meta ()
        {
            return this.meta;
        }

        public void set_meta (Ft.TimeBlockMeta meta)
        {
            this.meta = meta;
            this.version++;
            // this.emit_changed ();  // TODO
        }

        /**
         * Convenience alias for `Session.get_time_block_status(...)`
         */
        public Ft.TimeBlockStatus get_status ()
        {
            return this.meta.status;
        }

        /**
         * Convenience alias for `Session.set_time_block_status(...)`
         */
        public void set_status (Ft.TimeBlockStatus status)
        {
            if (this.meta.status != status) {
                this.meta.status = status;
                this.version++;
                // this.emit_changed ();  // TODO
            }
        }

        public int64 get_intended_duration ()
        {
            return this.meta.intended_duration;
        }

        public void set_intended_duration (int64 intended_duration)
        {
            if (this.meta.intended_duration != intended_duration) {
                this.meta.intended_duration = intended_duration;
                this.emit_changed ();
            }
        }

        public double get_weight ()
        {
            return this.meta.weight;
        }

        public void set_weight (double weight)
        {
            if (this.meta.weight != weight) {
                this.meta.weight = weight;
                this.emit_changed ();
            }
        }

        public int64 get_completion_time ()
        {
            return this.meta.completion_time;
        }

        public void set_completion_time (int64 completion_time)
        {
            if (this.meta.completion_time != completion_time) {
                this.meta.completion_time = completion_time;
                this.emit_changed ();
            }
        }

        public string get_task ()
        {
            return this.task;
        }

        /**
         * A task does not affect scheduling, so it does not emit `changed`.
         */
        public void set_task (string task)
        {
            if (this.task != task) {
                this.task = task;
                this.version++;
            }
        }


        /*
         * Database
         */

        internal bool should_create_entry ()
        {
            // XXX: we may want to save SCHEDULED time-blocks in future, e.g. when setting up
            //      a custom session / warm-up.
            return this.meta.status != Ft.TimeBlockStatus.SCHEDULED &&
                   this.state != Ft.State.STOPPED &&
                   Ft.Timestamp.is_defined (this.start_time);
        }

        internal bool should_update_entry ()
        {
            if (this.entry == null || this.entry.id == 0) {
                return true;
            }

            return this.entry.version != this.version ||
                   this.entry.status != this.meta.status.to_string ();
        }

        internal unowned Ft.TimeBlockEntry create_or_update_entry ()
                                                 requires (this.session != null)
        {
            if (this.entry == null)
            {
                this.entry = new Ft.TimeBlockEntry ();
                this.entry.repository = Ft.Database.get_repository ();

                this.session.entry.bind_property ("id",
                                                  this.entry,
                                                  "session-id",
                                                  GLib.BindingFlags.SYNC_CREATE);
            }

            this.entry.start_time = this._start_time;
            this.entry.end_time = this._end_time;
            this.entry.state = this._state.to_string ();
            this.entry.status = this.meta.status.to_string ();
            this.entry.intended_duration = this.meta.intended_duration;
            this.entry.task = this.task;
            this.entry.version = this.version;

            return this.entry;
        }

        internal void unset_entry ()
        {
            unowned GLib.List<Ft.Gap> link = this.gaps.first ();

            while (link != null)
            {
                link.data.unset_entry ();
                link = link.next;
            }

            this.entry = null;
        }


        /*
         * Signals
         */

        public signal void changed ();

        public override void dispose ()
        {
            this.entry = null;
            this.gaps = null;

            base.dispose ();
        }
    }
}
