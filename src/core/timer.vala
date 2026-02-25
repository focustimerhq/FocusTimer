/*
 * Copyright (c) 2022-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    /**
     * Helper structure for changing several fields at once. Together they can be regarded as a timer state.
     *
     * `user_data` in our use refers to a time block, but don't over use it.
     */
    [Immutable]
    public struct TimerState
    {
        public int64 duration;
        public int64 offset;
        public int64 started_time;
        public int64 paused_time;
        public int64 finished_time;
        public void* user_data;

        public TimerState ()
        {
            this.duration = 0;
            this.offset = 0;
            this.started_time = Ft.Timestamp.UNDEFINED;
            this.paused_time = Ft.Timestamp.UNDEFINED;
            this.finished_time = Ft.Timestamp.UNDEFINED;
            this.user_data = null;
        }

        /**
         * Make state copy
         *
         * This function is unnecessary. Structs in vala are copied by default. It's kept
         * to bring more clarity to our code.
         */
        public Ft.TimerState copy ()
        {
            return this;
        }

        public bool equals (Ft.TimerState other)
        {
            return this.duration == other.duration &&
                   this.offset == other.offset &&
                   this.started_time == other.started_time &&
                   this.paused_time == other.paused_time &&
                   this.finished_time == other.finished_time &&
                   this.user_data == other.user_data;
        }

        public bool is_valid ()
        {
            // Negative duration.
            if (this.duration < 0) {
                return false;
            }

            // Finished, but not started.
            if (Ft.Timestamp.is_defined (this.finished_time) &&
                Ft.Timestamp.is_undefined (this.started_time))
            {
                return false;
            }

            // Finished and still paused.
            if (Ft.Timestamp.is_defined (this.finished_time) &&
                Ft.Timestamp.is_defined (this.paused_time))
            {
                return false;
            }

            // Paused before started.
            if (Ft.Timestamp.is_defined (this.paused_time) && this.paused_time < this.started_time) {
                return false;
            }

            // Finished before started.
            if (Ft.Timestamp.is_defined (this.finished_time) && this.finished_time < this.started_time) {
                return false;
            }

            return true;
        }

        public inline bool is_started ()
        {
            return Ft.Timestamp.is_defined (this.started_time);
        }

        public inline bool is_running ()
        {
            return Ft.Timestamp.is_defined (this.started_time) &&
                   Ft.Timestamp.is_undefined (this.paused_time) &&
                   Ft.Timestamp.is_undefined (this.finished_time);
        }

        public inline bool is_paused ()
        {
            return Ft.Timestamp.is_defined (this.paused_time) &&
                   Ft.Timestamp.is_defined (this.started_time) &&
                   Ft.Timestamp.is_undefined (this.finished_time);
        }

        public inline bool is_finished ()
        {
            return Ft.Timestamp.is_defined (this.finished_time);
        }

        /**
         * Calculate elapsed time.
         *
         * It's only accurate when passing a current time. If you pass a historic time
         * the result will be just an estimate.
         */
        public int64 calculate_elapsed (int64 timestamp)
        {
            if (Ft.Timestamp.is_undefined (this.started_time)) {
                return 0;
            }

            if (Ft.Timestamp.is_defined (this.paused_time)) {
                timestamp = int64.min (this.paused_time, timestamp);
            }

            if (Ft.Timestamp.is_defined (this.finished_time)) {
                timestamp = int64.min (this.finished_time, timestamp);
            }

            return (
                timestamp - this.started_time - this.offset
            ).clamp (0, this.duration);
        }

        /**
         * Calculate remaining time.
         *
         * It's only accurate when passing a current time. If you pass a historic time
         * the result will be just an estimate.
         */
        public int64 calculate_remaining (int64 timestamp)
        {
            return this.duration - this.calculate_elapsed (timestamp);
        }

        /**
         * Convert structure to Variant.
         *
         * Used in tests.
         */
        public GLib.Variant to_variant ()
        {
            var builder = new GLib.VariantBuilder (new GLib.VariantType ("a{s*}"));
            builder.add ("{sv}", "duration", new GLib.Variant.int64 (this.duration));
            builder.add ("{sv}", "offset", new GLib.Variant.int64 (this.offset));
            builder.add ("{sv}", "started_time", new GLib.Variant.int64 (this.started_time));
            builder.add ("{sv}", "paused_time", new GLib.Variant.int64 (this.paused_time));
            builder.add ("{sv}", "finished_time", new GLib.Variant.int64 (this.finished_time));
            // builder.add ("{smh}", "user_data", this.user_data);

            return builder.end ();
        }

        /**
         * Represent state as string.
         *
         * Used in tests.
         */
        public string to_representation ()
        {
            var representation = new GLib.StringBuilder ("TimerState (\n");
            representation.append (@"    duration = $duration,\n");
            representation.append (@"    offset = $offset,\n");
            representation.append (@"    started_time = $started_time,\n");
            representation.append (@"    paused_time = $paused_time,\n");
            representation.append (@"    finished_time = $finished_time,\n");
            representation.append (this.user_data == null
                ? "    user_data = null\n"
                : "    user_data = not null\n");
            representation.append (")");

            return representation.str;
        }
    }


    /**
     * Timer class mimics a physical countdown timer.
     *
     * It trigger events on state changes. To trigger ticking event at regular intervals use TimerTicker.
     */
    public class Timer : GLib.Object
    {
        /**
         * Interval of the ticking signal.
         */
        private const int64 TICKING_INTERVAL = Ft.Interval.SECOND;

        /**
         * Time that is within tolerance not to schedule a timeout.
         */
        private const int64 TICKING_TOLERANCE = 20 * Ft.Interval.MILLISECOND;

        /**
         * Constraint for shorten/extend action to have some time remaining.
         */
        private const int64 MIN_REMAINING_TIME_TO_SHORTEN = 10 * Ft.Interval.SECOND;

        private static Ft.Timer? instance = null;

        /**
         * Timer internal state.
         *
         * You should not change its fields directly.
         */
        [CCode (notify = false)]
        public Ft.TimerState state {
            get {
                return this._state;
            }
            set {
                this.set_state_full (value);
            }
        }

        /**
         * The intended duration of the state, not counting gaps/interruptions.
         */
        [CCode (notify = false)]
        public int64 duration {
            get {
                return this._state.duration;
            }
            set {
                this.set_duration_full (value);
            }
        }

        /**
         * Time when timer has been initialized/started.
         */
        [CCode (notify = false)]
        public int64 started_time {
            get {
                return this._state.started_time;
            }
        }

        /**
         * Time lost during previous pauses. If pause is ongoing its not counted here yet.
         */
        [CCode (notify = false)]
        public int64 offset {
            get {
                return this._state.offset;
            }
        }

        /**
         * Extra data associated with current state
         */
        [CCode (notify = false)]
        public void* user_data {
            get {
                return this._state.user_data;
            }
            set {
                if (value == this._state.user_data) {
                    return;
                }

                if (this.is_finished ()) {
                    GLib.debug ("Trying to set timer user-data after it finished");
                }

                var new_state = this._state.copy ();
                new_state.user_data = value;

                this.state = new_state;
            }
        }

        private Ft.TimerState   _state = Ft.TimerState ();
        private uint            timeout_id = 0;
        private int64           last_state_changed_time = Ft.Timestamp.UNDEFINED;
        private int64           last_tick_time = Ft.Timestamp.UNDEFINED;
        private int64           suspend_time = Ft.Timestamp.UNDEFINED;
        private bool            resolving_state = false;
        private int             changing_state = 0;
        private Ft.TimerState?  state_to_resolve = null;
        private int64           monotonic_time_offset = 0;
        private Ft.SleepMonitor sleep_monitor;
        private ulong           prepare_for_sleep_id = 0;
        private ulong           woke_up_id = 0;

        construct
        {
            this.sleep_monitor = new Ft.SleepMonitor ();
            this.prepare_for_sleep_id = this.sleep_monitor.prepare_for_sleep.connect (
                () => {
                    this.suspend_time = this.get_current_time ();
                    this.stop_timeout (this.suspend_time);

                    this.suspending (this.suspend_time);
                }
            );
            this.woke_up_id = this.sleep_monitor.woke_up.connect (
                () => {
                    var timestamp = Ft.Timestamp.from_now ();

                    if (this.is_running ()) {
                        this.synchronize (Ft.Timestamp.UNDEFINED, timestamp);
                    }

                    this.suspended (this.suspend_time, timestamp);

                    this.suspend_time = Ft.Timestamp.UNDEFINED;
                }
            );
        }

        public Timer (int64 duration = 0,
                      void* user_data = null)
                      requires (duration >= 0)
        {
            this._state = Ft.TimerState () {
                duration = duration,
                offset = 0,
                started_time = Ft.Timestamp.UNDEFINED,
                paused_time = Ft.Timestamp.UNDEFINED,
                finished_time = Ft.Timestamp.UNDEFINED,
                user_data = user_data
            };
        }

        public Timer.with_state (Ft.TimerState state)
        {
            this._state = state;

            if (Ft.Timestamp.is_defined (this._state.started_time)) {
                this.last_state_changed_time = Ft.Timestamp.from_now ();
                this.start_timeout (this.last_state_changed_time);
            }
        }

        ~Timer ()
        {
            if (Ft.Timer.instance == null) {
                Ft.Timer.instance = null;
            }
        }

        /**
         * Try to change state and update fields related to state change
         */
        public void set_state_full (Ft.TimerState state,
                                    int64         timestamp = Ft.Timestamp.UNDEFINED)
        {
            this.ensure_timestamp (ref timestamp);

            var previous_state = this._state;

            this.resolve_state_internal (ref state, timestamp);

            if (!state.is_valid ()) {
                GLib.error ("Trying to set timer an invalid state: %s", state.to_representation ());
            }

            if (this._state.equals (state)) {
                return;
            }

            this.last_state_changed_time = timestamp;
            this._state = state;
            this.changing_state++;

            // Reset internal ticking interval, so that it aligns to seconds after skipping or rewinding.
            if (state.started_time != previous_state.started_time ||
                state.offset != previous_state.offset)
            {
                this.stop_timeout (timestamp);
            }

            this.notify_property ("state");

            if (state.duration != previous_state.duration) {
                this.notify_property ("duration");
            }

            if (state.started_time != previous_state.started_time) {
                this.notify_property ("started-time");
            }

            if (state.offset != previous_state.offset) {
                this.notify_property ("offset");
            }

            if (state.user_data != previous_state.user_data) {
                this.notify_property ("user-data");
            }

            this.state_changed (this._state, previous_state);

            this.changing_state--;
        }

        public void set_duration_full (int64 duration,
                                       int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (duration < 0) {
                GLib.debug ("Trying to set a negative timer duration (%.1fs).",
                            Ft.Timestamp.to_seconds (duration));
                duration = 0;
            }

            if (duration == this._state.duration) {
                return;
            }

            var new_state = this._state.copy ();
            new_state.duration = duration;

            if (new_state.duration > this._state.duration) {
                new_state.finished_time = Ft.Timestamp.UNDEFINED;
            }

            this.set_state_full (new_state, timestamp);
        }

        /**
         * Resolve timer state.
         *
         * It's a wrapper for `this.resolve_state`, handling a possible recursion.
         */
        private void resolve_state_internal (ref Ft.TimerState state,
                                             int64             timestamp)
        {
            var recursion_count = 0;

            if (this.resolving_state) {
                this.state_to_resolve = state;
                return;
            }

            if (this._state.equals (state)) {
                return;
            }

            this.resolving_state = true;

            while (true)
            {
                this.resolve_state (ref state, timestamp);

                if (this.state_to_resolve == null) {
                    break;
                }

                if (recursion_count > 1) {
                    GLib.error ("Reached recursion limit while resolving timer state");
                }

                state = this.state_to_resolve;
                this.state_to_resolve = null;

                recursion_count++;
            }

            this.resolving_state = false;
        }


        /**
         * Sets a default `Timer`.
         *
         * The old default timer is unreffed and the new timer referenced.
         *
         * A value of null for this will cause the current default timer to be released and a new default timer
         * to be created on demand.
         */
        public static void set_default (Ft.Timer? timer)
        {
            Ft.Timer.instance = timer;
        }

        /**
         * Return a default timer.
         *
         * A new default timer will be created on demand.
         */
        public static unowned Ft.Timer get_default ()
        {
            if (Ft.Timer.instance == null) {
                Ft.Timer.set_default (new Ft.Timer ());
            }

            return Ft.Timer.instance;
        }

        public bool is_default ()
        {
            return Ft.Timer.instance == this;
        }


        /**
         * Return whether timer is ticking -- whether timer has started, is not paused and hasn't finished.
         */
        public bool is_running ()
        {
            return this._state.is_running ();
        }

        /**
         * Return whether timer has been started.
         */
        public bool is_started ()
        {
            return this._state.is_started ();
        }

        /**
         * Return whether timer is paused.
         */
        public bool is_paused ()
        {
            return this._state.is_paused ();
        }

        /**
         * Return whether timer has finished.
         *
         * It does not need to reach full time for timer to be marked as finished.
         */
        public bool is_finished ()
        {
            return this._state.is_finished ();
        }

        /**
         * Reset timer to initial state.
         */
        public void reset (int64 duration = 0,
                           void* user_data = null,
                           int64 timestamp = Ft.Timestamp.UNDEFINED)
                           requires (duration >= 0)
        {
            this.set_state_full (
                Ft.TimerState () {
                    duration = duration,
                    offset = 0,
                    started_time = Ft.Timestamp.UNDEFINED,
                    paused_time = Ft.Timestamp.UNDEFINED,
                    finished_time = Ft.Timestamp.UNDEFINED,
                    user_data = user_data
                },
                timestamp
            );
        }

        /**
         * Start the timer or continue where it left off.
         */
        public void start (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this.is_started () || this.is_finished ()) {
                return;
            }

            this.ensure_timestamp (ref timestamp);

            var new_state = this._state.copy ();
            new_state.started_time = timestamp;
            new_state.paused_time = Ft.Timestamp.UNDEFINED;

            this.set_state_full (new_state, timestamp);
        }

        /**
         * Stop the timer if it's running.
         */
        public void pause (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this.is_paused () || !this.is_started () || this.is_finished ()) {
                return;
            }

            this.ensure_timestamp (ref timestamp);

            var new_state = this._state.copy ();
            new_state.paused_time = this.round_seconds (timestamp);

            this.set_state_full (new_state, timestamp);
        }

        /**
         * Resume timer if paused.
         */
        public void resume (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (!this.is_started () || this.is_finished () || !this.is_paused ()) {
                return;
            }

            this.ensure_timestamp (ref timestamp);

            var new_state = this._state.copy ();
            new_state.offset += timestamp - new_state.paused_time;
            new_state.paused_time = Ft.Timestamp.UNDEFINED;

            this.set_state_full (new_state, timestamp);
        }

        /**
         * Rewind
         */
        public void rewind (int64 interval,
                            int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (!this.is_started ()) {
                return;
            }

            if (interval == 0) {
                return;
            }

            if (interval < 0) {
                GLib.debug ("Rewinding timer with negative value (%.1fs).",
                            Ft.Timestamp.to_seconds (interval));
            }

            this.ensure_timestamp (ref timestamp);

            var elapsed = this.calculate_elapsed (timestamp);
            var new_elapsed = Ft.Timestamp.round (int64.max (elapsed - interval, 0), TICKING_INTERVAL);
            var new_state = this._state.copy ();

            new_state.finished_time = Ft.Timestamp.UNDEFINED;

            if (Ft.Timestamp.is_defined (new_state.paused_time)) {
                new_state.offset = new_state.paused_time - new_state.started_time - new_elapsed;
            }
            else {
                new_state.offset = timestamp - new_state.started_time - new_elapsed;
            }

            this.set_state_full (new_state, timestamp);
        }

        /**
         * Extend
         */
        public void extend (int64 interval,
                            int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this.duration <= 0) {
                return;
            }

            if (interval == 0) {
                return;
            }

            this.ensure_timestamp (ref timestamp);

            var elapsed = this.calculate_elapsed (timestamp);
            var remaining = this._state.duration - elapsed;

            remaining = remaining + interval >= MIN_REMAINING_TIME_TO_SHORTEN
                    ? remaining + interval
                    : MIN_REMAINING_TIME_TO_SHORTEN;

            this.set_duration_full (elapsed + remaining, timestamp);
        }

        /**
         * Mark state as "finished".
         *
         * Do not use it. It's public only for unit-tests.
         */
        public void finish (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (this.is_finished ()) {
                return;
            }

            this.ensure_timestamp (ref timestamp);

            this.stop_timeout (timestamp);

            var new_state = this._state.copy ();
            new_state.finished_time = timestamp;

            if (Ft.Timestamp.is_defined (new_state.paused_time)) {
                new_state.offset += timestamp - new_state.paused_time;
                new_state.paused_time = Ft.Timestamp.UNDEFINED;
            }

            this.set_state_full (new_state, timestamp);
        }

        public void synchronize (int64 monotonic_time = Ft.Timestamp.UNDEFINED,
                                 int64 real_time = Ft.Timestamp.UNDEFINED)
        {
            if (Ft.Timestamp.is_undefined (real_time)) {
                real_time = Ft.Timestamp.from_now ();
            }

            if (Ft.Timestamp.is_undefined (monotonic_time)) {
                monotonic_time = GLib.get_monotonic_time ();
            }

            this.monotonic_time_offset = real_time - monotonic_time;

            this.synchronized ();
        }

        /**
         * Return approximate real time.
         */
        public int64 get_current_time (int64 monotonic_time = Ft.Timestamp.UNDEFINED)
        {
            if (this.changing_state > 0 && Ft.Timestamp.is_undefined (monotonic_time)) {
                return this.last_state_changed_time;
            }

            if (this.monotonic_time_offset == 0 || Ft.Timestamp.is_frozen ()) {
                return Ft.Timestamp.from_now ();
            }

            if (Ft.Timestamp.is_undefined (monotonic_time)) {
                monotonic_time = GLib.get_monotonic_time ();
            }

            return monotonic_time + this.monotonic_time_offset;
        }

        private int64 round_seconds (int64 timestamp)
        {
            if (this.last_tick_time > 0 &&
                (timestamp - this.last_tick_time).abs () < 2 * TICKING_INTERVAL)
            {
                return this.last_tick_time;
            }

            if (Ft.Timestamp.is_defined (this._state.started_time))
            {
                var elapsed = this.calculate_elapsed (timestamp);
                var elapsed_rounded = Ft.Timestamp.round (elapsed, TICKING_INTERVAL);

                return this._state.started_time + this._state.offset + elapsed_rounded;
            }

            return timestamp;
        }

        private inline void ensure_timestamp (ref int64 timestamp)
        {
            if (Ft.Timestamp.is_undefined (timestamp)) {
                timestamp = this.get_current_time ();
            }
        }

        private int64 calculate_tick_time (int64 timestamp)
        {
            var elapsed = this.calculate_elapsed (timestamp);
            var elapsed_rounded = Ft.Timestamp.round (elapsed, TICKING_INTERVAL);

            return Ft.Timestamp.is_defined (this._state.started_time)
                ? this._state.started_time + this._state.offset + elapsed_rounded
                : Ft.Timestamp.UNDEFINED;
        }

        /**
         * Ticking timeout.
         *
         * Unfortunately it can deviate from full seconds.
         */
        private bool on_timeout ()
                                 requires (this.timeout_id != 0)
        {
            var timestamp         = this.get_current_time (GLib.MainContext.current_source ().get_time ());
            var timestamp_rounded = this.calculate_tick_time (timestamp);
            var remaining         = this.calculate_remaining (timestamp);

            if (remaining > 0 && this.last_tick_time != timestamp_rounded) {
                this.last_tick_time = timestamp_rounded;
                this.tick (timestamp_rounded);
            }

            // Check if already finished.
            if (remaining < TICKING_TOLERANCE) {
                this.timeout_id = 0;
                this.finish (timestamp);

                return GLib.Source.REMOVE;
            }

            // Check whether to switch to a more precise timeout.
            if (remaining < TICKING_INTERVAL + TICKING_TOLERANCE)
            {
                this.timeout_id = GLib.Timeout.add (Ft.Timestamp.to_milliseconds_uint (remaining),
                                                    this.on_timeout_once);
                GLib.Source.set_name_by_id (this.timeout_id, "Ft.Timer.on_timeout_once");

                return GLib.Source.REMOVE;
            }

            return GLib.Source.CONTINUE;
        }

        /**
         * Precise timeout.
         *
         * It's meant to set up idle timeout that is aligned to full seconds.
         */
        private bool on_timeout_once ()
                                      requires (this.timeout_id != 0)
        {
            var timestamp         = this.get_current_time (GLib.MainContext.current_source ().get_time ());
            var timestamp_rounded = this.calculate_tick_time (timestamp);
            var remaining         = this.calculate_remaining (timestamp);

            this.timeout_id = 0;

            if (remaining > 0 && this.last_tick_time != timestamp_rounded) {
                this.last_tick_time = timestamp_rounded;
                this.tick (timestamp_rounded);
            }

            // Check if already finished.
            if (remaining < TICKING_TOLERANCE) {
                this.finish (timestamp);

                return GLib.Source.REMOVE;
            }

            // Close to finish. Schedule one more timeout instead of interval.
            if (remaining < TICKING_INTERVAL + TICKING_TOLERANCE) {
                this.timeout_id = GLib.Timeout.add (Ft.Timestamp.to_milliseconds_uint (remaining),
                                                    this.on_timeout_once);
                GLib.Source.set_name_by_id (this.timeout_id, "Ft.Timer.on_timeout_once");

                return GLib.Source.REMOVE;
            }

            // Schedule ticking at regular interval.
            this.timeout_id = GLib.Timeout.add (Ft.Timestamp.to_milliseconds_uint (TICKING_INTERVAL),
                                                this.on_timeout);
            GLib.Source.set_name_by_id (this.timeout_id, "Ft.Timer.on_timeout");

            return GLib.Source.REMOVE;
        }

        /**
         * Start ticking. First tick will be emitted after the `interval`.
         *
         * `aligned` will align ticks to elapsed time. It's meant for displaying elapsed/remaining time to sync label
         * updates with the timer.
         */
        private void start_timeout_internal (int64 timestamp)
                                             requires (Ft.Timestamp.is_defined (timestamp))
                                             requires (this.timeout_id == 0)
        {
            var timestamp_rounded = this.calculate_tick_time (timestamp);
            var remaining         = this.calculate_remaining (timestamp);

            this.last_tick_time = timestamp_rounded;

            if (remaining > TICKING_TOLERANCE)
            {
                var deviation = timestamp - timestamp_rounded;

                if (remaining > TICKING_INTERVAL &&
                    deviation.abs () < TICKING_TOLERANCE)
                {
                    this.timeout_id = GLib.Timeout.add (
                            Ft.Timestamp.to_milliseconds_uint (TICKING_INTERVAL),
                            this.on_timeout);
                    GLib.Source.set_name_by_id (this.timeout_id, "Ft.Timer.on_timeout");
                }
                else {
                    this.timeout_id = GLib.Timeout.add (
                            Ft.Timestamp.to_milliseconds_uint (TICKING_INTERVAL - deviation),
                            this.on_timeout_once);
                    GLib.Source.set_name_by_id (this.timeout_id, "Ft.Timer.on_timeout_once");
                }
            }
            else {
                this.finish (timestamp);
            }
        }

        private void start_timeout (int64 timestamp)
        {
            if (this.timeout_id != 0 ) {
                return;  // already running
            }

            if (Ft.Timestamp.is_frozen ()) {
                return;  // don't run timeout in unittests
            }

            this.synchronize (Ft.Timestamp.UNDEFINED, timestamp);

            this.start_timeout_internal (timestamp);
        }

        private void stop_timeout (int64 timestamp)
        {
            // State may change right before a timeout callback gets called.
            // Ensure that tick gets emitted if it's delayed.
            var timestamp_rounded = this.calculate_tick_time (timestamp);

            if (this.last_tick_time != timestamp_rounded && timestamp_rounded >= this.last_state_changed_time) {
                this.last_tick_time = timestamp_rounded;
                this.tick (timestamp_rounded);
            }

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.monotonic_time_offset = 0;
            this.last_tick_time = Ft.Timestamp.UNDEFINED;
        }

        /**
         * Return time of a last state change.
         *
         * It's deliberate that "last_state_changed_time" is not a property, as we don't want emitting
         * notify events for that.
         */
        public int64 get_last_state_changed_time ()
        {
            return this.last_state_changed_time;
        }

        public int64 get_last_tick_time ()
        {
            return this.last_tick_time;
        }

        /**
         * Calculate elapsed time.
         *
         * It's only accurate when passing a current time. If you pass a historic time
         * the result will be just an estimate.
         */
        public int64 calculate_elapsed (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (Ft.Timestamp.is_undefined (this._state.started_time)) {
                return 0;
            }

            this.ensure_timestamp (ref timestamp);

            return this._state.calculate_elapsed (timestamp);
        }

        /**
         * Calculate remaining time.
         *
         * It's only accurate when passing a current time. If you pass a historic time
         * the result will be just an estimate.
         */
        public int64 calculate_remaining (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            return this._state.duration - this.calculate_elapsed (timestamp);
        }

        /**
         * Calculate progress.
         *
         * It's only accurate when passing a current time. If you pass a historic time
         * the result will be just an estimate.
         */
        public double calculate_progress (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            var elapsed = (double) this.calculate_elapsed (timestamp);
            var duration = (double) this._state.duration;

            return duration > 0.0 ? elapsed / duration : 0.0;
        }

        /**
         * Calculate finish time.
         *
         * When paused it returns `Timestamp.UNDEFINED`.
         */
        public int64 calculate_finish_time ()
        {
            if (!this.is_running ()) {
                return Ft.Timestamp.UNDEFINED;
            }

            if (this.is_finished ()) {
                return this._state.finished_time;
            }

            return this._state.started_time + this._state.offset + this._state.duration;
        }

        /**
         * Wait until timer finishes
         *
         * It will only have an effect after Timer.start() or after setting up timer state.
         *
         * Intended for unit tests.
         */
        public void run (GLib.Cancellable? cancellable = null)
        {
            var main_context = GLib.MainContext.@default ();

            while (this.is_running () && (cancellable == null || !cancellable.is_cancelled ()))
            {
                main_context.iteration (true);
            }
        }

        /**
         * Manually perform a tick or check whether timer has finished.
         *
         * Intended for unit tests.
         */
        public void iterate ()
        {
            var timestamp         = Ft.Timestamp.peek ();
            var timestamp_rounded = this.calculate_tick_time (timestamp);
            var remaining         = this.calculate_remaining (timestamp);

            if (remaining > 0 && this.last_tick_time != timestamp_rounded) {
                this.tick (timestamp_rounded);
            }

            if (remaining < TICKING_TOLERANCE) {
                this.finish (timestamp);
            }
        }

        /**
         * Emitted before setting a new state.
         *
         * It allows for fine-tuning the state before emitting state-changed signal.
         * Default handler ensures that state is valid.
         */
        public signal void resolve_state (ref Ft.TimerState state,
                                          int64             timestamp)
        {
            if (Ft.Timestamp.is_undefined (state.started_time)) {
                state.paused_time = Ft.Timestamp.UNDEFINED;
                state.finished_time = Ft.Timestamp.UNDEFINED;
            }

            if (Ft.Timestamp.is_defined (state.paused_time) && state.paused_time < state.started_time) {
                state.paused_time = state.started_time;
            }

            if (Ft.Timestamp.is_defined (state.finished_time) && state.finished_time < state.started_time) {
                state.finished_time = state.started_time;
            }
        }

        /**
         * Emitted on any state related changes. Default handler acknowledges the change.
         */
        public signal void state_changed (Ft.TimerState current_state,
                                          Ft.TimerState previous_state)
        {
            if (current_state.is_running ()) {
                this.start_timeout (this.last_state_changed_time);
            }
            else {
                this.stop_timeout (this.last_state_changed_time);
            }

            if (current_state.is_finished () &&
                previous_state.is_started () &&
                !previous_state.is_finished ())
            {
                this.finished (current_state);
            }
        }

        /**
         * Emitted every second when timer is running.
         *
         * Ticks are aligned to full seconds of elapsed time.
         */
        [Signal (run = "first")]
        public signal void tick (int64 timestamp)
        {
            this.last_tick_time = timestamp;
        }

        /**
         * Emitted when countdown is close to zero or passed it.
         */
        public signal void finished (Ft.TimerState state);

        /**
         * Emitted after synchronizing timer against monotonic time.
         */
        public signal void synchronized ();

        /**
         * Emitted before system has suspended.
         *
         * It's emitted even when timer is not running.
         */
        public signal void suspending (int64 start_time);

        /**
         * Emitted right after system wakes up and the timer has been synchronised.
         *
         * It's emitted even when the timer is not running.
         */
        public signal void suspended (int64 start_time,
                                      int64 end_time)
        {
            if (this.last_state_changed_time > start_time) {
                // Signal handler pushed a new state.
                return;
            }

            if (this.is_running ())
            {
                var new_state = this._state.copy ();
                new_state.offset += end_time - start_time;

                this.set_state_full (new_state, end_time);
            }
        }

        public override void dispose ()
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            if (this.prepare_for_sleep_id != 0) {
                this.sleep_monitor.disconnect (this.prepare_for_sleep_id);
                this.prepare_for_sleep_id = 0;
            }

            if (this.woke_up_id != 0) {
                this.sleep_monitor.disconnect (this.woke_up_id);
                this.woke_up_id = 0;
            }

            this.sleep_monitor = null;

            base.dispose ();
        }
    }
}
