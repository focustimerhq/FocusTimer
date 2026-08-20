/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Wayland
{
    public class IdleMonitorProvider : Ft.Provider, Ft.IdleMonitorProvider
    {
        private const int64 TIMEOUT_TOLERANCE = 100 * Ft.Interval.MILLISECOND;

        [Compact]
        class Watch
        {
            public uint32 id = 0;
            public int64  absolute_timeout = 0;
            public int64  relative_timeout = 0;
            public int64  reference_time = Ft.Timestamp.UNDEFINED;
            public bool   ignore_inhibitors = false;
            public bool   has_active_watch = false;
            public bool   invalid = false;
        }

        public bool can_ignore_inhibitors {
            get {
                return this.supports_input_idle;
            }
        }

        private bool                          supports_input_idle = false;
        private FtWayland.IdleMonitor?        idle_monitor = null;
        private GLib.HashTable<int64?, Watch> watches = null;
        private uint32                        active_watch_id = 0;
        private uint                          active_watch_use_count = 0;

        construct
        {
            this.watches = new GLib.HashTable<int64?, Watch> (int64_hash, int64_equal);
        }

        private inline uint64 to_milliseconds (int64 interval)
        {
            return (uint64) int64.max (interval, 0) / Ft.Interval.MILLISECOND;
        }

        private void remove_active_watch_internal () throws GLib.Error
        {
            if (this.active_watch_id != 0 && this.idle_monitor != null)
            {
                var watch_id = this.active_watch_id;

                this.active_watch_id = 0;
                this.active_watch_use_count = 0;

                this.idle_monitor.remove_notification (watch_id);
            }
        }

        private void on_became_active ()
        {
            if (!this.enabled) {
                return;
            }

            try {
                this.remove_active_watch_internal ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while removing active-watch: %s", error.message);
            }

            this.became_active ();
        }

        private void on_became_idle (Watch watch)
        {
            if (!this.enabled) {
                return;
            }

            var monotonic_time = GLib.get_monotonic_time ();
            var min_elapsed = int64.max (watch.relative_timeout - TIMEOUT_TOLERANCE,
                                         watch.relative_timeout / 2);

            if (monotonic_time - watch.reference_time >= min_elapsed) {
                this.became_idle (watch.id);
            }
        }

        [CCode (has_target = false)]
        private static void on_notification_idled (uint32 id,
                                                   void*  user_data)
        {
            var provider = user_data as IdleMonitorProvider;

            if (provider == null || provider.idle_monitor == null) {
                return;
            }

            provider.handle_notification_idled (id);
        }

        [CCode (has_target = false)]
        private static void on_notification_resumed (uint32 id,
                                                     void*  user_data)
        {
            var provider = user_data as IdleMonitorProvider;

            if (provider == null || provider.idle_monitor == null) {
                return;
            }

            provider.handle_notification_resumed (id);
        }

        private void handle_notification_idled (uint32 id)
        {
            if (id == 0 || id == this.active_watch_id) {
                return;
            }

            unowned var watch = this.watches.lookup (id);

            if (watch != null && !watch.invalid) {
                this.on_became_idle (watch);
            }
        }

        private void handle_notification_resumed (uint32 id)
        {
            if (id != 0 && id == this.active_watch_id) {
                this.on_became_active ();
            }
        }

        private void update_available ()
        {
            var display = Gdk.Display.get_default () as Gdk.Wayland.Display;
            if (display == null) {
                this.available = false;
            }

            var seat = display.get_default_seat () as Gdk.Wayland.Seat;
            if (seat == null) {
                this.available = false;
                return;
            }

            if (this.idle_monitor == null) {
                this.idle_monitor = new FtWayland.IdleMonitor (display.get_wl_display (),
                                                               seat.get_wl_seat ());
            }

            if (this.idle_monitor.is_ready ()) {
                this.supports_input_idle = this.idle_monitor.supports_input_idle ();
                this.available = true;
            }
            else {
                this.available = false;
            }
        }

        public uint32 add_idle_watch (int64 timeout,
                                      bool  ignore_inhibitors,
                                      int64 monotonic_time) throws GLib.Error
                                      requires (this.idle_monitor != null)
        {
            int64 relative_timeout = timeout;
            int64 absolute_timeout = timeout;
            uint32 watch_id;

            if (Ft.Timestamp.is_undefined (monotonic_time)) {
                monotonic_time = GLib.get_monotonic_time () - relative_timeout;
            }
            else {
                absolute_timeout = Ft.IdleMonitorProvider.calculate_absolute_timeout (
                        relative_timeout,
                        0,
                        monotonic_time);

                if ((absolute_timeout - relative_timeout).abs () < TIMEOUT_TOLERANCE) {
                    absolute_timeout = relative_timeout;
                }
            }

            if (ignore_inhibitors && !this.can_ignore_inhibitors) {
                ignore_inhibitors = false;
            }

            if (ignore_inhibitors) {
                watch_id = this.idle_monitor.add_input_notification (
                        (uint32) this.to_milliseconds (timeout),
                        on_notification_idled,
                        null,
                        this);
            }
            else {
                watch_id = this.idle_monitor.add_notification (
                        (uint32) this.to_milliseconds (timeout),
                        on_notification_idled,
                        null,
                        this);
            }

            if (watch_id == 0) {
                throw new GLib.IOError.FAILED ("Failed to add Wayland idle notification");
            }

            var watch = new Watch ();
            watch.id = watch_id;
            watch.relative_timeout = relative_timeout;
            watch.absolute_timeout = absolute_timeout;
            watch.reference_time = monotonic_time;
            watch.ignore_inhibitors = ignore_inhibitors;

            unowned var _watch = watch;

            this.watches.insert (watch_id, (owned) watch);

            if (!_watch.has_active_watch && _watch.absolute_timeout != _watch.relative_timeout)
            {
                try {
                    this.add_active_watch ();
                    _watch.has_active_watch = true;
                }
                catch (GLib.Error error) {
                    GLib.debug ("Unable to add active watch: %s", error.message);

                    this.remove_idle_watch (watch_id);

                    throw error;
                }
            }

            return watch_id;
        }

        public void remove_idle_watch (uint32 id)
                                       requires (this.idle_monitor != null)
        {
            unowned var watch = this.watches.lookup (id);

            if (watch == null) {
                return;
            }

            watch.invalid = true;

            if (watch.has_active_watch)
            {
                try {
                    this.remove_active_watch ();
                    watch.has_active_watch = false;
                }
                catch (GLib.Error error) {
                    GLib.warning ("Unable to remove active watch: %s", error.message);
                }
            }

            this.idle_monitor.remove_notification (watch.id);

            if (!watch.has_active_watch) {
                this.watches.remove (id);
            }
        }

        public uint32 reset_idle_watch (uint32 id,
                                        int64  monotonic_time) throws GLib.Error
                                        requires (this.idle_monitor != null)
        {
            unowned var watch = this.watches.lookup (id);

            if (watch == null || watch.absolute_timeout == watch.relative_timeout) {
                return id;
            }

            var new_id = this.add_idle_watch (watch.relative_timeout,
                                              watch.ignore_inhibitors,
                                              monotonic_time);

            this.idle_monitor.remove_notification (watch.id);
            this.watches.remove (id);

            return new_id;
        }

        public void add_active_watch () throws GLib.Error
                                      requires (this.idle_monitor != null)
        {
            if (this.active_watch_id == 0)
            {
                var ignore_inhibitors = this.can_ignore_inhibitors;

                if (ignore_inhibitors) {
                    this.active_watch_id = this.idle_monitor.add_input_notification (
                            0,
                            null,
                            on_notification_resumed,
                            this);
                }
                else {
                    this.active_watch_id = this.idle_monitor.add_notification (
                            0,
                            null,
                            on_notification_resumed,
                            this);
                }

                if (this.active_watch_id == 0) {
                    throw new GLib.IOError.FAILED ("Failed to add Wayland active-watch notification");
                }

                var active_watch = new Watch ();
                active_watch.id = this.active_watch_id;
                active_watch.ignore_inhibitors = ignore_inhibitors;
                this.watches.insert (this.active_watch_id, (owned) active_watch);
            }

            this.active_watch_use_count++;
        }

        public void remove_active_watch () throws GLib.Error
                                         requires (this.active_watch_use_count > 0)
        {
            if (this.active_watch_use_count > 1) {
                this.active_watch_use_count--;
            }
            else if (this.active_watch_use_count == 1) {
                var watch_id = this.active_watch_id;

                this.remove_active_watch_internal ();

                if (watch_id != 0) {
                    this.watches.remove (watch_id);
                }
            }
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            var display = Gdk.Display.get_default ();

            if (display == null) {
                GLib.debug ("Wayland idle monitor: no default Gdk display");
                return;
            }

            this.update_available ();
        }

        public override async void uninitialize () throws GLib.Error
        {
            this.available = false;
            this.idle_monitor = null;
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            assert (this.idle_monitor != null);
        }

        public override async void disable () throws GLib.Error
        {
            if (this.idle_monitor == null) {
                return;
            }

            uint32[] ids = {};

            this.watches.@foreach (
                (id, watch) => {
                    ids += watch.id;
                });

            for (var index = 0; index < ids.length; index++) {
                this.remove_idle_watch (ids[index]);
            }

            this.remove_active_watch_internal ();
        }

        public override void dispose ()
        {
            this.watches = null;
            this.idle_monitor = null;

            base.dispose ();
        }
    }
}
