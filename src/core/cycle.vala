/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    /**
     * A convenience class describing a cycle.
     *
     * Cycle consists of a single pomodoro and breaks following it. In case pomodoro comes right after another pomodoro
     * we treat it as new cycle to make session indicator more readable, although it's not true to a definition of
     * a cycle. Uncompleted time-blocks are included, therefore some cycles may be considered as invalid.
     *
     * Cycle does not serve as a container for time-blocks, its more like an annotation.
     */
    public class Cycle : GLib.Object
    {
        public unowned Ft.Session session {
            get {
                unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

                return link != null ? link.data.session : null;
            }
        }

        public int64 start_time {
            get {
                return this._start_time;
            }
        }

        public int64 end_time {
            get {
                return this._end_time;
            }
        }

        public int64 duration {
            get {
                return Ft.Timestamp.subtract (this._end_time, this._start_time);
            }
        }

        private GLib.List<Ft.TimeBlock> time_blocks;
        private int64                   _start_time = Ft.Timestamp.UNDEFINED;
        private int64                   _end_time = Ft.Timestamp.UNDEFINED;
        private int                     changed_freeze_count = 0;
        private bool                    changed_is_pending = false;
        private double                  progress_value = double.NAN;
        private int64                   progress_reference_start_time = Ft.Timestamp.UNDEFINED;
        private int64                   progress_reference_end_time = Ft.Timestamp.UNDEFINED;

        // Metadata
        private double                  weight = double.NAN;
        private int64                   completion_time = Ft.Timestamp.UNDEFINED;

        construct
        {
            this.time_blocks = new GLib.List<Ft.TimeBlock> ();
        }

        private void on_time_block_changed ()
        {
            this.emit_changed ();
        }

        private void emit_added (Ft.TimeBlock time_block)
        {
            time_block.changed.connect (this.on_time_block_changed);

            this.added (time_block);
        }

        private void emit_removed (Ft.TimeBlock time_block)
        {
            time_block.changed.disconnect (this.on_time_block_changed);

            this.removed (time_block);
        }

        private void emit_changed ()
        {
            if (this.changed_freeze_count > 0) {
                this.changed_is_pending = true;
            }
            else {
                this.changed_is_pending = false;
                this.changed ();
            }
        }

        public void freeze_changed ()
        {
            this.changed_freeze_count++;
        }

        public void thaw_changed ()
        {
            this.changed_freeze_count--;

            if (this.changed_freeze_count == 0 && this.changed_is_pending) {
                this.emit_changed ();
            }
        }

        private void update_time_range ()
        {
            unowned Ft.TimeBlock first_time_block = this.get_first_time_block ();
            unowned Ft.TimeBlock last_time_block = this.get_last_time_block ();

            var old_duration = this._end_time - this._start_time;

            var start_time = first_time_block != null
                    ? first_time_block.start_time
                    : Ft.Timestamp.UNDEFINED;

            var end_time = last_time_block != null
                    ? last_time_block.end_time
                    : Ft.Timestamp.UNDEFINED;

            if (this._start_time != start_time) {
                this._start_time = start_time;
                this.notify_property ("start-time");
            }

            if (this._end_time != end_time) {
                this._end_time = end_time;
                this.notify_property ("end-time");
            }

            if (this._end_time - this._start_time != old_duration) {
                this.notify_property ("duration");
            }
        }

        private void remove_link (GLib.List<Ft.TimeBlock>? link)
        {
            if (link == null) {
                return;
            }

            var time_block = link.data;
            link.data = null;
            this.time_blocks.delete_link (link);

            this.emit_removed (time_block);
        }

        public void remove (Ft.TimeBlock time_block)
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.find (time_block);

            if (link != null) {
                this.remove_link (link);
            }
            else {
                GLib.warning ("Ignoring `Cycle.remove()`. Time-block does not belong to the cycle.");
            }
        }

        public void append (Ft.TimeBlock time_block)
        {
            this.time_blocks.append (time_block);

            this.emit_added (time_block);
        }

        public unowned Ft.TimeBlock? get_first_time_block ()
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            return link != null ? link.data : null;
        }

        public unowned Ft.TimeBlock? get_last_time_block ()
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.last ();

            return link != null ? link.data : null;
        }

        public bool contains (Ft.TimeBlock time_block)
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            while (link != null)
            {
                if (link.data == time_block) {
                    return true;
                }

                link = link.next;
            }

            return false;
        }

        public void @foreach (GLib.Func<unowned Ft.TimeBlock> func)
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            while (link != null)
            {
                func (link.data);

                link = link.next;
            }
        }

        /*
         * Functions for metadata
         */

        public double get_weight ()
        {
            if (this.weight.is_nan ())
            {
                unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();
                var weight = 0.0;

                while (link != null)
                {
                    if (link.data.get_status () != Ft.TimeBlockStatus.UNCOMPLETED)
                    {
                        var time_block_weight = link.data.get_weight ();
                        weight = !time_block_weight.is_nan ()
                            ? weight + double.max (time_block_weight, 0.0)
                            : double.NAN;
                    }

                    link = link.next;
                }

                this.weight = weight;
            }

            return this.weight;
        }

        public int64 get_completion_time ()
        {
            if (Ft.Timestamp.is_undefined (this.completion_time))
            {
                unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();
                var completion_time = Ft.Timestamp.UNDEFINED;
                var time_block_completion_time = Ft.Timestamp.UNDEFINED;

                while (link != null)
                {
                    if (link.data.get_status () != Ft.TimeBlockStatus.UNCOMPLETED &&
                        link.data.get_weight () > 0.0)
                    {
                        time_block_completion_time = link.data.get_completion_time ();
                        completion_time = Ft.Timestamp.is_defined (time_block_completion_time)
                            ? time_block_completion_time
                            : link.data.end_time;
                    }

                    link = link.next;
                }

                this.completion_time = completion_time;
            }

            return this.completion_time;
        }

        public bool is_scheduled ()
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            var first_status = link != null
                    ? link.data.get_status ()
                    : Ft.TimeBlockStatus.SCHEDULED;

            return first_status == Ft.TimeBlockStatus.SCHEDULED;
        }

        public Ft.TimeBlockStatus get_status ()
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            if (link == null || link.data.get_status () == Ft.TimeBlockStatus.SCHEDULED) {
                return Ft.TimeBlockStatus.SCHEDULED;
            }

            while (link != null)
            {
                if (link.data.get_status () == Ft.TimeBlockStatus.IN_PROGRESS ||
                    link.data.get_status () == Ft.TimeBlockStatus.SCHEDULED)
                {
                    return Ft.TimeBlockStatus.IN_PROGRESS;
                }

                link = link.next;
            }

            return this.is_visible ()
                    ? Ft.TimeBlockStatus.COMPLETED
                    : Ft.TimeBlockStatus.UNCOMPLETED;
        }

        /**
         * Hide cycles that were uncompleted.
         */
        public bool is_visible ()
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();

            while (link != null)
            {
                if (link.data.get_status () != Ft.TimeBlockStatus.UNCOMPLETED &&
                    link.data.get_weight () > 0.0)
                {
                    return true;
                }

                link = link.next;
            }

            return false;
        }

        public void prepare_progress (int64 timestamp)
        {
            unowned GLib.List<Ft.TimeBlock> link = this.time_blocks.first ();
            var progress = 0.0;
            var total_weight = 0.0;
            var in_progress = false;

            while (link != null)
            {
                var time_block_weight = link.data.get_weight ();
                var last_gap = link.data.get_last_gap ();

                if (link.data.get_status () != Ft.TimeBlockStatus.UNCOMPLETED) {
                    total_weight += time_block_weight;
                }

                if (link.data.get_status () == Ft.TimeBlockStatus.IN_PROGRESS) {
                    in_progress = true;
                }

                if (last_gap != null && Ft.Timestamp.is_undefined (last_gap.end_time)) {
                    in_progress = false;
                }

                progress += time_block_weight * link.data.calculate_progress (timestamp);

                link = link.next;
            }

            if (total_weight != 0.0) {
                progress /= total_weight;
            }

            if (!in_progress || progress >= 1.0)
            {
                this.progress_value = progress.clamp (0.0, 1.0);
                this.progress_reference_start_time = Ft.Timestamp.UNDEFINED;
                this.progress_reference_end_time = Ft.Timestamp.UNDEFINED;
            }
            else {
                var completion_time = this.get_completion_time ();

                this.progress_value = double.NAN;
                this.progress_reference_start_time = (int64)(
                        ((double) timestamp - progress * (double) completion_time) /
                        (1.0 - progress));
                this.progress_reference_end_time = completion_time;

                if (this.progress_reference_start_time >= this.progress_reference_end_time)
                {
                    this.progress_value = progress.clamp (0.0, 1.0);
                    this.progress_reference_start_time = Ft.Timestamp.UNDEFINED;
                    this.progress_reference_end_time = Ft.Timestamp.UNDEFINED;
                }
            }
        }

        /**
         * Calculate cycle progress.
         *
         * Uses cache to make following calls cheaper to estimate.
         */
        public double calculate_progress (int64 timestamp)
        {
            if (Ft.Timestamp.is_undefined (this._end_time) ||
                Ft.Timestamp.is_undefined (this._start_time))
            {
                return 0.0;
            }

            Ft.ensure_timestamp (ref timestamp);

            if (Ft.Timestamp.is_undefined (this.progress_reference_start_time) &&
                this.progress_value.is_nan ())
            {
                this.prepare_progress (timestamp);
            }

            if (!this.progress_value.is_nan ()) {
                return this.progress_value;
            }

            if (this.progress_reference_start_time >= timestamp) {
                return 0.0;
            }

            if (this.progress_reference_end_time <= timestamp) {
                return 1.0;
            }

            return (
                (double)(timestamp - this.progress_reference_start_time) /
                (double)(this.progress_reference_end_time - this.progress_reference_start_time)
            ).clamp (0.0, 1.0);
        }

        public int64 calculate_progress_duration (int64 timestamp)  // XXX: bad name
        {
            if (Ft.Timestamp.is_undefined (this.progress_reference_start_time))
            {
                Ft.ensure_timestamp (ref timestamp);
                this.prepare_progress (timestamp);
            }

            return Ft.Timestamp.subtract (this.progress_reference_end_time,
                                                this.progress_reference_start_time);
        }

        /**
         * Invalidate cache. Cache helps avoiding re-iterating time-blocks for certain operations.
         *
         * You should call it on every time-block change or change of metadata.
         */
        private void invalidate_cache ()
        {
            this.weight = double.NAN;
            this.completion_time = Ft.Timestamp.UNDEFINED;
            this.progress_value = double.NAN;
            this.progress_reference_start_time = Ft.Timestamp.UNDEFINED;
            this.progress_reference_end_time = Ft.Timestamp.UNDEFINED;
        }

        public override void dispose ()
        {
            unowned GLib.List<Ft.TimeBlock> link;

            while ((link = this.time_blocks.first ()) != null)
            {
                link.data.changed.disconnect (this.on_time_block_changed);
                link.data = null;

                this.time_blocks.delete_link (link);
            }

            base.dispose ();
        }


        /*
         * Signals
         */


        [Signal (run = "last")]
        public signal void added (Ft.TimeBlock time_block)
        {
            this.emit_changed ();
        }

        [Signal (run = "last")]
        public signal void removed (Ft.TimeBlock time_block)
        {
            this.emit_changed ();
        }

        [Signal (run = "first")]
        public signal void changed ()
        {
            this.invalidate_cache ();
            this.update_time_range ();
        }
    }
}
