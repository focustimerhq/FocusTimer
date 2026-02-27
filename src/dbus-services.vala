/*
 * Copyright (c) 2012-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    [DBus (name = "io.github.focustimerhq.FocusTimer")]
    public class ApplicationDBusService : GLib.Object
    {
        public string version {
            get { return Config.PACKAGE_VERSION; }
        }

        private Ft.Application? application;

        public ApplicationDBusService (Ft.Application application)
        {
            this.application = application;
        }

        public void show_window (string view) throws GLib.DBusError, GLib.IOError
        {
            this.application.show_window (Ft.WindowView.from_string (view));
        }

        public void show_preferences (string view) throws GLib.DBusError, GLib.IOError
        {
            this.application.show_preferences (view);
        }

        public void quit () throws GLib.DBusError, GLib.IOError
        {
            this.application.quit ();
        }

        public override void dispose ()
        {
            this.application = null;

            base.dispose ();
        }
    }


    /**
     * Timer service provides equivalent functionality of the timer view in the app.
     */
    [DBus (name = "io.github.focustimerhq.FocusTimer.Timer")]
    public class TimerDBusService : GLib.Object
    {
        private const string DBUS_INTERFACE_NAME = "io.github.focustimerhq.FocusTimer.Timer";

        public string state
        {
            owned get {
                return this._state.to_string ();
            }
            set {
                var state = Ft.State.from_string (value);

                this.session_manager.advance_to_state (state);
            }
        }

        public int64 duration
        {
            get {
                return this.timer_state.duration;
            }
            set {
                if (this.timer.user_data != null) {
                    this.timer.duration = value;
                }
            }
        }

        public int64 offset
        {
            get {
                return this.timer_state.offset;
            }
        }

        public int64 started_time
        {
            get {
                return this.timer_state.started_time;
            }
        }

        public int64 paused_time
        {
            get {
                return this.timer_state.paused_time;
            }
        }

        public int64 finished_time
        {
            get {
                return this.timer_state.finished_time;
            }
        }

        public int64 last_changed_time
        {
            get {
                return this.last_state_changed_time;
            }
        }

        private Ft.Timer?                   timer;
        private Ft.SessionManager?          session_manager;
        private weak GLib.DBusConnection?   connection;
        private string                      object_path;
        private Ft.State                    _state;
        private Ft.TimerState               timer_state;
        private int64                       last_state_changed_time = Ft.Timestamp.UNDEFINED;

        public TimerDBusService (GLib.DBusConnection connection,
                                 string              object_path,
                                 Ft.Timer            timer,
                                 Ft.SessionManager   session_manager)
        {
            this.connection      = connection;
            this.object_path     = object_path;
            this.timer           = timer;
            this.session_manager = session_manager;

            this.timer.state_changed.connect (this.on_timer_state_changed);
            this.timer.tick.connect (this.on_timer_tick);
            this.timer.finished.connect (this.on_timer_finished);
            this.session_manager.notify["state"].connect (this.on_session_manager_notify_state);
        }

        private void update_properties ()
        {
            if (this.connection == null) {
                return;
            }

            var changed_properties = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
            var invalidated_properties = new GLib.VariantBuilder (new GLib.VariantType ("as"));
            var timer_state = this.timer.state.copy ();
            var last_state_changed_time = this.timer.get_last_state_changed_time ();
            var state = this.session_manager.current_state;

            if (state != this._state) {
                changed_properties.add ("{sv}",
                                        "State",
                                        new GLib.Variant.string (state.to_string ()));
            }

            if (timer_state.duration != this.timer_state.duration) {
                changed_properties.add ("{sv}",
                                        "Duration",
                                        new GLib.Variant.int64 (timer_state.duration));
            }

            if (timer_state.offset != this.timer_state.offset) {
                changed_properties.add ("{sv}",
                                        "Offset",
                                        new GLib.Variant.int64 (timer_state.offset));
            }

            if (timer_state.started_time != this.timer_state.started_time) {
                changed_properties.add ("{sv}",
                                        "StartedTime",
                                        new GLib.Variant.int64 (timer_state.started_time));
            }

            if (timer_state.paused_time != this.timer_state.paused_time) {
                changed_properties.add ("{sv}",
                                        "PausedTime",
                                        new GLib.Variant.int64 (timer_state.paused_time));
            }

            if (timer_state.finished_time != this.timer_state.finished_time) {
                changed_properties.add ("{sv}",
                                        "FinishedTime",
                                        new GLib.Variant.int64 (timer_state.finished_time));
            }

            if (last_state_changed_time != this.last_state_changed_time) {
                changed_properties.add ("{sv}",
                                        "LastChangedTime",
                                        new GLib.Variant.int64 (last_state_changed_time));
            }

            this._state = state;
            this.timer_state = timer_state;
            this.last_state_changed_time = last_state_changed_time;

            try {
                this.connection.emit_signal (
                    null,
                    this.object_path,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    new GLib.Variant (
                        "(sa{sv}as)",
                        DBUS_INTERFACE_NAME,
                        changed_properties,
                        invalidated_properties
                    )
                );
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to emit PropertiesChanged signal: %s", error.message);
            }
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            this.update_properties ();
            this.changed ();
        }

        private void on_timer_tick (int64 timestamp)
        {
            this.tick (timestamp);
        }

        private void on_timer_finished ()
        {
            this.finished ();
        }

        private void on_session_manager_notify_state (GLib.Object    object,
                                                      GLib.ParamSpec pspec)
        {
            this.update_properties ();
        }

        public bool is_started () throws GLib.DBusError, GLib.IOError
        {
            return this.timer.is_started ();
        }

        public bool is_running () throws GLib.DBusError, GLib.IOError
        {
            return this.timer.is_running ();
        }

        public bool is_paused () throws GLib.DBusError, GLib.IOError
        {
            return this.timer.is_paused ();
        }

        public bool is_finished () throws GLib.DBusError, GLib.IOError
        {
            return this.timer.is_finished ();
        }

        public int64 get_elapsed (int64 timestamp = Ft.Timestamp.UNDEFINED)
                                  throws GLib.DBusError, GLib.IOError
        {
            return this.timer.calculate_elapsed (timestamp);
        }

        public int64 get_remaining (int64 timestamp = Ft.Timestamp.UNDEFINED)
                                    throws GLib.DBusError, GLib.IOError
        {
            return this.timer.calculate_remaining (timestamp);
        }

        public double get_progress (int64 timestamp = Ft.Timestamp.UNDEFINED)
                                    throws GLib.DBusError, GLib.IOError
        {
            return this.timer.calculate_progress (timestamp);
        }

        public void start () throws GLib.DBusError, GLib.IOError
        {
            this.timer.start ();
        }

        public void stop () throws GLib.DBusError, GLib.IOError
        {
            this.timer.reset ();
        }

        public void pause () throws GLib.DBusError, GLib.IOError
        {
            this.timer.pause ();
        }

        public void resume () throws GLib.DBusError, GLib.IOError
        {
            this.timer.resume ();
        }

        public void rewind (int64 interval) throws GLib.DBusError, GLib.IOError
        {
            this.timer.rewind (interval);
        }

        public void extend (int64 interval) throws GLib.DBusError, GLib.IOError
        {
            this.timer.extend (interval);
        }

        public void skip () throws GLib.DBusError, GLib.IOError
        {
            this.session_manager.advance ();
        }

        public void reset () throws GLib.DBusError, GLib.IOError
        {
            this.session_manager.reset ();
        }

        public signal void changed ();

        public signal void tick (int64 timestamp);

        public signal void finished ();

        public override void dispose ()
        {
            this.timer.state_changed.disconnect (this.on_timer_state_changed);
            this.timer.tick.disconnect (this.on_timer_tick);
            this.timer.finished.disconnect (this.on_timer_finished);
            this.session_manager.notify["state"].disconnect (this.on_session_manager_notify_state);

            this.timer = null;
            this.session_manager = null;
            this.connection = null;

            base.dispose ();
        }
    }


    /**
     * Session service represents mostly `SessionManager.current_session`, but
     * also includes relevant methods/properties from `SessionManager` and scheduler.
     */
    [DBus (name = "io.github.focustimerhq.FocusTimer.Session")]
    public class SessionDBusService : GLib.Object
    {
        private const string DBUS_INTERFACE_NAME = "io.github.focustimerhq.FocusTimer.Session";

        public string current_state
        {
            owned get {
                return this._current_state.to_string ();
            }
        }

        public int64 start_time
        {
            get {
                return this._start_time;
            }
        }

        public int64 end_time
        {
            get {
                return this._end_time;
            }
        }

        public bool has_uniform_breaks
        {
            get {
                return this._has_uniform_breaks;
            }
        }

        public bool can_reset
        {
            get {
                return this._can_reset;
            }
        }

        private Ft.SessionManager?          session_manager;
        private weak GLib.DBusConnection?   connection;
        private string                      object_path;
        private Ft.State                    _current_state = Ft.State.STOPPED;
        private int64                       _start_time = Ft.Timestamp.UNDEFINED;
        private int64                       _end_time = Ft.Timestamp.UNDEFINED;
        private bool                        _has_uniform_breaks = false;
        private bool                        _can_reset = false;

        public SessionDBusService (GLib.DBusConnection connection,
                                   string              object_path,
                                   Ft.SessionManager session_manager)
        {
            this.connection      = connection;
            this.object_path     = object_path;
            this.session_manager = session_manager;

            this.session_manager.notify["current-session"].connect (
                    this.on_notify_current_session);
            this.session_manager.notify["has-uniform-breaks"].connect (
                    this.on_notify_has_uniform_breaks);
            this.session_manager.enter_session.connect (this.on_enter_session);
            this.session_manager.leave_session.connect (this.on_leave_session);
            this.session_manager.enter_time_block.connect (this.on_enter_time_block);
            this.session_manager.leave_time_block.connect (this.on_leave_time_block);
            this.session_manager.advanced.connect (this.on_advanced);
            this.session_manager.confirm_advancement.connect (this.on_confirm_advancement);

            if (session_manager.current_session != null) {
                this.on_enter_session (session_manager.current_session);
            }
        }

        private void update_properties ()
        {
            if (this.connection == null) {
                return;
            }

            var changed_properties = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
            var invalidated_properties = new GLib.VariantBuilder (new GLib.VariantType ("as"));
            var current_session = this.session_manager.current_session;
            var current_state = this.session_manager.current_state;

            var start_time = current_session != null
                    ? current_session.start_time
                    : Ft.Timestamp.UNDEFINED;
            var end_time = current_session != null
                    ? current_session.end_time
                    : Ft.Timestamp.UNDEFINED;
            var has_uniform_breaks = this.session_manager.has_uniform_breaks;
            var can_reset = this.session_manager.can_reset ();
            var changed = false;

            if (this._current_state != current_state) {
                this._current_state = current_state;
                changed_properties.add ("{sv}",
                                        "CurrentState",
                                        new GLib.Variant.string (current_state.to_string ()));
                changed = true;
            }

            if (this._start_time != start_time) {
                this._start_time = start_time;
                changed_properties.add ("{sv}",
                                        "StartTime",
                                        new GLib.Variant.int64 (start_time));
                changed = true;
            }

            if (this._end_time != end_time) {
                this._end_time = end_time;
                changed_properties.add ("{sv}",
                                        "EndTime",
                                        new GLib.Variant.int64 (end_time));
                changed = true;
            }

            if (this._has_uniform_breaks != has_uniform_breaks) {
                this._has_uniform_breaks = has_uniform_breaks;
                changed_properties.add ("{sv}",
                                        "HasUniformBreaks",
                                        new GLib.Variant.boolean (has_uniform_breaks));
                changed = true;
            }

            if (this._can_reset != can_reset) {
                this._can_reset = can_reset;
                changed_properties.add ("{sv}",
                                        "CanReset",
                                        new GLib.Variant.boolean (can_reset));
                changed = true;
            }

            if (changed)
            {
                try {
                    this.connection.emit_signal (
                        null,
                        this.object_path,
                        "org.freedesktop.DBus.Properties",
                        "PropertiesChanged",
                        new GLib.Variant (
                            "(sa{sv}as)",
                            DBUS_INTERFACE_NAME,
                            changed_properties,
                            invalidated_properties
                        )
                    );
                }
                catch (GLib.Error error) {
                    GLib.warning ("Failed to emit PropertiesChanged signal: %s", error.message);
                }
            }
        }

        private GLib.Variant serialize_gap (Ft.Gap? gap)
        {
            var builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

            if (gap != null) {
                builder.add ("{sv}", "start_time", new GLib.Variant.int64 (gap.start_time));
                builder.add ("{sv}", "end_time", new GLib.Variant.int64 (gap.end_time));
            }

            return builder.end ();
        }

        private GLib.Variant serialize_time_block (Ft.TimeBlock? time_block)
        {
            var builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

            if (time_block != null)
            {
                var gaps = new GLib.Variant[0];
                time_block.foreach_gap (
                    (gap) => {
                        gaps += this.serialize_gap (gap);
                    });

                builder.add ("{sv}",
                             "state",
                             new GLib.Variant.string (time_block.state.to_string ()));
                builder.add ("{sv}",
                             "status",
                             new GLib.Variant.string (time_block.get_status ().to_string ()));
                builder.add ("{sv}",
                             "start_time",
                             new GLib.Variant.int64 (time_block.start_time));
                builder.add ("{sv}",
                             "end_time",
                             new GLib.Variant.int64 (time_block.end_time));
                builder.add ("{sv}",
                             "gaps",
                             new GLib.Variant.array (GLib.VariantType.VARDICT, gaps));
            }

            return builder.end ();
        }

        private GLib.Variant serialize_cycle (Ft.Cycle? cycle)
        {
            var builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

            if (cycle != null)
            {
                builder.add ("{sv}",
                             "start_time",
                             new GLib.Variant.int64 (cycle.start_time));
                builder.add ("{sv}",
                             "end_time",
                             new GLib.Variant.int64 (cycle.end_time));
                builder.add ("{sv}",
                             "completion_time",
                             new GLib.Variant.int64 (cycle.get_completion_time ()));
                builder.add ("{sv}",
                             "weight",
                             new GLib.Variant.double (cycle.get_weight ()));
                builder.add ("{sv}",
                             "status",
                             new GLib.Variant.string (cycle.get_status ().to_string ()));
            }

            return builder.end ();
        }

        private void on_notify_current_session (GLib.Object    object,
                                                GLib.ParamSpec pspec)
        {
            this.update_properties ();
            this.changed ();
        }

        private void on_notify_has_uniform_breaks (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            this.update_properties ();
        }

        private void on_enter_session (Ft.Session session)
        {
            session.changed.connect (this.on_current_session_changed);
        }

        private void on_leave_session (Ft.Session session)
        {
            session.changed.disconnect (this.on_current_session_changed);
        }

        private void on_enter_time_block (Ft.TimeBlock time_block)
        {
            this.enter_time_block (this.serialize_time_block (time_block));
        }

        private void on_leave_time_block (Ft.TimeBlock time_block)
        {
            this.leave_time_block (this.serialize_time_block (time_block));
        }

        private void on_advanced (Ft.Session?   current_session,
                                  Ft.TimeBlock? current_time_block,
                                  Ft.Session?   previous_session,
                                  Ft.TimeBlock? previous_time_block)
        {
            if (current_session == null && previous_session != null) {
                this.changed ();
            }
        }

        private void on_confirm_advancement (Ft.TimeBlock current_time_block,
                                             Ft.TimeBlock next_time_block)
        {
            this.confirm_advancement (this.serialize_time_block (current_time_block),
                                      this.serialize_time_block (next_time_block));
        }

        private void on_current_session_changed (Ft.Session session)
        {
            this.update_properties ();
            this.changed ();
        }

        public void advance () throws GLib.DBusError, GLib.IOError
        {
            this.session_manager.advance ();
        }

        public void advance_to_state (string state) throws GLib.DBusError, GLib.IOError
        {
            this.session_manager.advance_to_state (Ft.State.from_string (state));
        }

        public void reset () throws GLib.DBusError, GLib.IOError
        {
            this.session_manager.reset ();
        }

        [DBus (signature = "a{sv}")]
        public GLib.Variant get_current_time_block () throws GLib.DBusError, GLib.IOError
        {
            return this.serialize_time_block (this.session_manager.current_time_block);
        }

        [DBus (signature = "a{sv}")]
        public GLib.Variant get_current_gap () throws GLib.DBusError, GLib.IOError
        {
            return this.serialize_gap (this.session_manager.current_gap);
        }

        [DBus (signature = "a{sv}")]
        public GLib.Variant GetNextTimeBlock () throws GLib.DBusError, GLib.IOError
        {
            return this.serialize_time_block (this.session_manager.get_next_time_block ());
        }

        [DBus (signature = "aa{sv}")]
        public GLib.Variant list_time_blocks () throws GLib.DBusError, GLib.IOError
        {
            var items = new GLib.Variant[0];

            this.session_manager.current_session?.@foreach (
                (time_block) => {
                    items += this.serialize_time_block (time_block);
                });

            return new GLib.Variant.array (GLib.VariantType.VARDICT, items);
        }

        [DBus (signature = "aa{sv}")]
        public GLib.Variant list_cycles () throws GLib.DBusError, GLib.IOError
        {
            var items = new GLib.Variant[0];

            this.session_manager.current_session?.get_cycles ().@foreach (
                (cycle) => {
                    items += this.serialize_cycle (cycle);
                });

            return new GLib.Variant.array (GLib.VariantType.VARDICT, items);
        }

        public signal void enter_time_block (GLib.Variant time_block);

        public signal void leave_time_block (GLib.Variant time_block);

        public signal void confirm_advancement (GLib.Variant current_time_block,
                                                GLib.Variant next_time_block);

        public signal void changed ();

        public override void dispose ()
        {
            this.session_manager.notify["current-session"].disconnect (
                    this.on_notify_has_uniform_breaks);
            this.session_manager.notify["has-uniform-breaks"].disconnect (
                    this.on_notify_has_uniform_breaks);
            this.session_manager.enter_session.disconnect (this.on_enter_session);
            this.session_manager.leave_session.disconnect (this.on_leave_session);
            this.session_manager.advanced.disconnect (this.on_advanced);
            this.session_manager.confirm_advancement.disconnect (this.on_confirm_advancement);

            this.session_manager = null;
            this.connection = null;

            base.dispose ();
        }
    }
}
