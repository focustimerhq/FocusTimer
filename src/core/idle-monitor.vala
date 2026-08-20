/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    public delegate void Callback ();


    public interface IdleMonitorProvider : Ft.Provider
    {
        public abstract bool can_ignore_inhibitors { get; }

        /**
         * Register an idle watch with the session idle monitor.
         *
         * Fires `became_idle` after `timeout` microseconds without user activity.
         *
         * When `monotonic_time` is defined, idle time is counted from from the given timestamp.
         *
         * When `ignore_inhibitors` is `true`, the watch reacts to real user input (not supported
         * by all providers).
         */
        public abstract uint32 add_idle_watch (int64 timeout, bool ignore_inhibitors, int64 monotonic_time) throws GLib.Error;

        /**
         * Reschedule an idle watch. It ensures that it'll not fire before `timeout` passes
         * counting from the current time.
         */
        public abstract uint32 reset_idle_watch (uint32 id, int64 monotonic_time) throws GLib.Error;

        public abstract void remove_idle_watch (uint32 id) throws GLib.Error;

        public abstract void add_active_watch () throws GLib.Error;
        public abstract void remove_active_watch () throws GLib.Error;

        public signal void became_idle (uint32 id);
        public signal void became_active ();

        /**
         * Convert an idle interval anchored at `reference_time` into one relative to the
         * user's last activity.
         */
        public static int64 calculate_absolute_timeout (int64 relative_timeout,
                                                        int64 idle_time,
                                                        int64 reference_time)
                                                        requires (Ft.Timestamp.is_defined (reference_time))
        {
            if (idle_time == 0) {
                return relative_timeout;
            }

            var last_active_time = GLib.get_monotonic_time () - idle_time;
            var absolute_timeout = relative_timeout + reference_time - last_active_time;

            return absolute_timeout > 0
                    ? absolute_timeout
                    : relative_timeout;
        }
    }


    // TODO: should be defined in tests
    public class DummyIdleMonitorProvider : Ft.Provider, Ft.IdleMonitorProvider
    {
        public bool can_ignore_inhibitors {
            get {
                return false;
            }
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.available = true;
            this.enabled = true;  // HACK: This is to skip the need for a main loop in tests
        }

        public override async void uninitialize () throws GLib.Error
        {
            this.available = false;
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
        }

        public override async void disable () throws GLib.Error
        {
        }

        public int64 get_idle_time () throws GLib.Error
        {
            return 0;
        }

        public uint32 add_idle_watch (int64 timeout,
                                      bool  ignore_inhibitors,
                                      int64 monotonic_time) throws GLib.Error
        {
            return 1;
        }

        public uint32 reset_idle_watch (uint32 id,
                                        int64 monotonic_time) throws GLib.Error
        {
            return 1;
        }

        public void add_active_watch () throws GLib.Error
        {
        }

        public void remove_idle_watch (uint32 id) throws GLib.Error
        {
        }

        public void remove_active_watch () throws GLib.Error
        {
        }
    }


    [SingleInstance]
    public class IdleMonitor : Ft.ProvidedObject<Ft.IdleMonitorProvider>
    {
        private static uint next_watch_id = 1U;

        [Compact]
        private class Watch
        {
            public uint                            id = 0U;
            public uint32                          external_id = 0U;
            public int64                           timeout = 0;
            public int64                           reference_time = Ft.Timestamp.UNDEFINED;
            public bool                            ignore_inhibitors = false;
            public Ft.Callback?                    idle_callback = null;
            public Ft.Callback?                    active_callback = null;
            public unowned Ft.IdleMonitorProvider? provider = null;
            public bool                            invalid = false;

            ~Watch ()
            {
                this.idle_callback = null;
                this.active_callback = null;
                this.provider = null;
            }
        }

        private GLib.HashTable<int64?, Watch> watches = null;
        private int64                         last_activity_time = Ft.Timestamp.UNDEFINED;

        private void on_became_idle (uint32 id)
        {
            // We don't expect idle watch to be called often, so linear scan is good enough.
            unowned Watch? watch = this.watches.find (
                (_id, watch) => {
                    return watch.external_id == id;
                });

            if (watch != null && !watch.invalid) {
                watch.idle_callback ();
            }
        }

        private void on_became_active ()
        {
            var monotonic_time = GLib.get_monotonic_time ();

            this.last_activity_time = monotonic_time;

            (unowned Watch)[] watches_to_trigger = new Watch[0];

            this.watches.@foreach (
                (id, watch) => {
                    if (watch.invalid) {
                        return;
                    }

                    if (watch.active_callback != null) {
                        watches_to_trigger += watch;
                    }

                    if (watch.idle_callback != null) {
                        try {
                            // Let the provider decide whether internally it needs a reset.
                            watch.external_id = this.provider.reset_idle_watch (watch.external_id, monotonic_time);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Unable to reset an idle watch: %s", error.message);
                            return;
                        }
                    }
                });

            for (var index = 0; index < watches_to_trigger.length; index++)
            {
                unowned Watch watch = watches_to_trigger[index];
                watch.active_callback ();
                watch.invalid = true;
            }

            this.watches.foreach_remove (
                (id, watch) => {
                    return watch.invalid && watch.active_callback != null;
                });
        }

        protected override void initialize ()
        {
            // Initialize here rather than in `construct` block, as base `construct` runs first
            // and may trigger `provider_enabled()` which accesses `watches`.
            this.watches = new GLib.HashTable<int64?, Watch> (GLib.int64_hash, GLib.int64_equal);
        }

        protected override void setup_providers ()
        {
            if (Ft.is_test ()) {
                this.providers.add (new Ft.DummyIdleMonitorProvider (), Ft.Priority.HIGH);
            }
        }

        protected override void provider_enabled (Ft.IdleMonitorProvider provider)
        {
            provider.became_idle.connect (this.on_became_idle);
            provider.became_active.connect (this.on_became_active);

            // Recreate watches with the new provider.
            this.watches.@foreach (
                (id, watch) => {
                    if (watch.idle_callback != null && watch.external_id == 0)
                    {
                        try {
                            watch.external_id = provider.add_idle_watch (
                                    watch.timeout,
                                    watch.ignore_inhibitors && provider.can_ignore_inhibitors,
                                    watch.reference_time);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while adding idle watch: %s", error.message);
                        }
                    }

                    if (watch.active_callback != null)
                    {
                        try {
                            provider.add_active_watch ();
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while adding active watch: %s", error.message);
                        }
                     }
                });
        }

        protected override void provider_disabled (Ft.IdleMonitorProvider provider)
        {
            provider.became_idle.disconnect (this.on_became_idle);
            provider.became_active.disconnect (this.on_became_active);

            this.watches.@foreach (
                (id, watch) => {
                    try {
                        provider.remove_idle_watch (watch.external_id);
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Error while removing idle watch: %s", error.message);
                    }

                    watch.external_id = 0;
                });
        }

        /**
         * Register an idle watch.
         *
         * `reference_time` specifies whether idle-time should be detected from this point of time,
         * otherwise the callback will be called counting from the time of users last activity.
         */
        public uint add_idle_watch (int64                   timeout,
                                    bool                    ignore_inhibitors,
                                    owned Ft.Callback       callback,
                                    int64                   monotonic_time = Ft.Timestamp.UNDEFINED)
        {
            if (timeout == 0) {
                return 0;
            }

            var watch_id = Ft.IdleMonitor.next_watch_id;
            Ft.IdleMonitor.next_watch_id++;

            var watch = new Watch ();
            watch.id = watch_id;
            watch.timeout = timeout;
            watch.ignore_inhibitors = ignore_inhibitors;
            watch.idle_callback = (owned) callback;
            watch.reference_time = monotonic_time;
            watch.provider = this.provider;

            if (this.provider != null && this.provider.enabled)
            {
                try {
                    watch.external_id = this.provider.add_idle_watch (
                            timeout,
                            ignore_inhibitors && this.provider.can_ignore_inhibitors,
                            monotonic_time);
                }
                catch (GLib.Error error) {
                    GLib.warning ("Unable to add an idle watch: %s", error.message);
                }
            }
            else {
                GLib.debug ("Unable to add an idle watch: no provider.");
            }

            this.watches.insert (watch_id, (owned) watch);

            return watch_id;
        }

        /**
         * Trigger callback on first user activity counting from now.
         */
        public uint add_active_watch (owned Ft.Callback callback,
                                      int64             monotonic_time = Ft.Timestamp.UNDEFINED)
        {
            var watch_id = Ft.IdleMonitor.next_watch_id;
            Ft.IdleMonitor.next_watch_id++;

            var watch = new Watch ();
            watch.id = watch_id;
            watch.active_callback = (owned) callback;
            watch.reference_time = monotonic_time;
            watch.provider = this.provider;

            if (this.provider != null && this.provider.enabled)
            {
                try {
                    this.provider.add_active_watch ();
                }
                catch (GLib.Error error) {
                    GLib.warning ("Unable to add an active watch: %s", error.message);
                }
            }
            else {
                GLib.debug ("Unable to add an active watch: no provider.");
            }

            this.watches.insert (watch_id, (owned) watch);

            return watch_id;
        }

        public void remove_watch (uint id)
        {
            unowned Watch? watch = this.watches.lookup (id);

            if (watch == null) {
                return;
            }

            if (this.provider == null)
            {
                watch.invalid = true;
                return;
            }

            try {
                if (watch.idle_callback != null && watch.external_id != 0) {
                    this.provider.remove_idle_watch (watch.external_id);
                }

                if (watch.active_callback != null) {
                    this.provider.remove_active_watch ();
                }

                this.watches.remove (id);
            }
            catch (GLib.Error error) {
                GLib.debug ("Error while removing watch: %s", error.message);
                watch.invalid = true;
            }
        }

        public override void dispose ()
        {
            base.dispose ();

            // Watches are needed for destroying providers during `base.dispose()`.
            this.watches = null;
        }
    }
}

