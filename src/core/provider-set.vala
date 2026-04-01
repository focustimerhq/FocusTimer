/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    /**
     * Time between the start of provider initialization to resolution of availability.
     */
    private const int64 AVAILABILITY_TIMEOUT = Ft.Interval.MILLISECOND * 100;
    private const int64 AVAILABILITY_TIMEOUT_TOLERANCE = Ft.Interval.MILLISECOND * 20;


    public enum SelectionMode
    {
        NONE,
        SINGLE,
        ALL
    }


    private enum ProviderStatus
    {
        NOT_INITIALIZED,
        INITIALIZING,
        UNINITIALIZING,
        DISABLING,
        DISABLED,
        ENABLING,
        ENABLED;

        public bool is_transient ()
        {
            switch (this)
            {
                case INITIALIZING:
                case UNINITIALIZING:
                case DISABLING:
                case ENABLING:
                    return true;

                default:
                    return false;
            }
        }
    }


    private class ProviderInfo
    {
        public Ft.Provider       instance;
        public Ft.Priority       priority;
        public Ft.ProviderStatus status = Ft.ProviderStatus.NOT_INITIALIZED;
        public bool              selected = false;
        public bool              destroying = false;
        public GLib.Cancellable? cancellable = null;
        public int64             initialization_time = Ft.Timestamp.UNDEFINED;

        public ProviderInfo (Ft.Provider instance,
                             Ft.Priority priority)
        {
            this.instance = instance;
            this.priority = priority;
        }

        public int64 get_availability_timeout (ref int64 monotonic_time)
        {
            if (this.instance.available_set) {
                return 0;
            }

            if (Ft.Timestamp.is_undefined (this.initialization_time)) {
                return 0;
            }

            if (Ft.Timestamp.is_undefined (monotonic_time)) {
                monotonic_time = GLib.get_monotonic_time ();
            }

            return monotonic_time - this.initialization_time;
        }

        ~ProviderInfo ()
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            this.instance = null;
        }
    }


    public class ProviderSet<T> : GLib.Object
    {
        private GLib.GenericSet<Ft.ProviderInfo> providers = null;
        private Ft.SelectionMode                 _selection_mode = Ft.SelectionMode.ALL;
        private uint                             update_selection_timeout_id = 0;
        private uint                             update_selection_idle_id = 0;
        private bool                             selection_invalid = false;
        private bool                             updating_selection = false;
        private bool                             should_enable = false;

        public Ft.SelectionMode selection_mode
        {
            get {
                return this._selection_mode;
            }
            construct {
                this._selection_mode = value;
            }
        }

        construct
        {
            this.providers = new GLib.GenericSet<Ft.ProviderInfo> (GLib.direct_hash,
                                                                   GLib.direct_equal);
        }

        public ProviderSet (Ft.SelectionMode selection_mode = Ft.SelectionMode.ALL)
        {
            GLib.Object (
                selection_mode: selection_mode
            );
        }

        /**
         * Manage provider according to its status.
         *
         * It should be called after every async action or status changed.
         */
        private void check_provider_status (Ft.ProviderInfo provider_info)
        {
            var provider = provider_info.instance;

            // Each action should call check_provider_status() at the end, so if the status is transient
            // we can ignore it.
            if (provider_info.status.is_transient ()) {
                return;
            }

            if (provider_info.selected && !provider_info.destroying)
            {
                if (provider_info.status == Ft.ProviderStatus.NOT_INITIALIZED)
                {
                    provider_info.status = Ft.ProviderStatus.INITIALIZING;
                    provider_info.cancellable = new GLib.Cancellable ();
                    provider_info.initialization_time = GLib.get_monotonic_time ();
                    provider.initialize.begin (
                        provider_info.cancellable,
                        (obj, res) => {
                            try {
                                provider.initialize.end (res);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                this.check_provider_status (provider_info);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while initializing %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.NOT_INITIALIZED;
                            }
                        });
                }
                else if (this.should_enable &&
                         provider_info.status == Ft.ProviderStatus.DISABLED &&
                         provider.available)
                {
                    provider_info.status = Ft.ProviderStatus.ENABLING;
                    provider_info.cancellable = new GLib.Cancellable ();
                    provider.enable.begin (
                        provider_info.cancellable,
                        (obj, res) => {
                            try {
                                provider.enable.end (res);
                                provider_info.status = Ft.ProviderStatus.ENABLED;
                                provider.enabled = true;
                                this.check_provider_status (provider_info);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while enabling %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.DISABLED;
                            }
                        });
                }
                else if (!this.should_enable &&
                         provider_info.status == Ft.ProviderStatus.ENABLED)
                {
                    provider_info.status = Ft.ProviderStatus.DISABLING;
                    provider.enabled = false;
                    provider.disable.begin (
                        (obj, res) => {
                            try {
                                provider.disable.end (res);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                this.check_provider_status (provider_info);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while disabling %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.DISABLED;
                            }
                        });
                }
            }
            else if (provider_info.status == Ft.ProviderStatus.ENABLED)
            {
                // Ensure provider is disabled and uninitialized before destroying.
                // We try to disable provider even if it's unavailable.

                provider_info.status = Ft.ProviderStatus.DISABLING;
                provider.enabled = false;
                provider.disable.begin (
                    (obj, res) => {
                        try {
                            provider.disable.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while disabling %s: %s",
                                          provider.get_type ().name (),
                                          error.message);
                        }

                        // We always mark it here as DISABLED, so that it will be deallocated when destroying.
                        provider_info.status = Ft.ProviderStatus.DISABLED;

                        this.check_provider_status (provider_info);
                    });
            }
            else if (provider_info.status == Ft.ProviderStatus.DISABLED && provider_info.destroying)
            {
                provider_info.status = Ft.ProviderStatus.UNINITIALIZING;
                provider.uninitialize.begin (
                    (obj, res) => {
                        try {
                            provider.uninitialize.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while uninitializing %s: %s",
                                          provider.get_type ().name (),
                                          error.message);
                        }

                        // We always mark it here as NOT_INITIALIZED when destroying.
                        provider_info.status = Ft.ProviderStatus.NOT_INITIALIZED;
                    });
            }
        }

        private static int compare (Ft.ProviderInfo provider_info,
                                    int64           provider_timeout,
                                    Ft.ProviderInfo other_info,
                                    int64           other_timeout)
        {
            var provider_available = provider_info.instance.available_set
                    ? provider_info.instance.available
                    : provider_timeout < AVAILABILITY_TIMEOUT;
            var other_available = other_info.instance.available_set
                    ? other_info.instance.available
                    : other_timeout < AVAILABILITY_TIMEOUT;

            if (provider_available != other_available) {
                return provider_available ? -1 : 1;
            }

            if (provider_info.priority != other_info.priority) {
                return provider_info.priority > other_info.priority ? -1 : 1;
            }

            if (provider_info.selected != other_info.selected) {
                return provider_info.selected ? -1 : 1;
            }

            return 0;
        }

        private void get_preferred_provider_info (out unowned Ft.ProviderInfo? preferred_provider_info,
                                                  out int64                    preferred_provider_timeout)
        {
            unowned Ft.ProviderInfo? tmp_preferred_provider_info = null;
            int64                    tmp_preferred_provider_timeout = 0;
            int64                    monotonic_time = Ft.Timestamp.UNDEFINED;

            this.providers.@foreach (
                (provider_info) => {
                    var provider_timeout = provider_info.get_availability_timeout (ref monotonic_time);

                    if (tmp_preferred_provider_info == null)
                    {
                        tmp_preferred_provider_info = provider_info;
                        tmp_preferred_provider_timeout = provider_timeout;
                    }
                    else {
                        var comparison_result = compare (tmp_preferred_provider_info,
                                                         tmp_preferred_provider_timeout,
                                                         provider_info,
                                                         provider_timeout);
                        if (comparison_result > 0) {
                            tmp_preferred_provider_info = provider_info;
                            tmp_preferred_provider_timeout = provider_timeout;
                        }
                    }
                });

            preferred_provider_info = tmp_preferred_provider_info;
            preferred_provider_timeout = tmp_preferred_provider_timeout;
        }

        /**
         * Find best provider, preferably available with highest priority.
         */
        private void select_single ()
        {
            unowned Ft.ProviderInfo? preferred_provider_info = null;
            int64                    preferred_provider_timeout = 0;
            var                      selection_changed = false;

            this.get_preferred_provider_info (out preferred_provider_info,
                                              out preferred_provider_timeout);

            if (preferred_provider_timeout > 0)
            {
                this.update_selection_timeout_id = GLib.Timeout.add (
                        Ft.Timestamp.to_milliseconds_uint (preferred_provider_timeout +
                                                           AVAILABILITY_TIMEOUT_TOLERANCE),
                        this.on_update_selection_timeout);
                GLib.Source.set_name_by_id (this.update_selection_timeout_id,
                                            "Ft.ProviderSet.on_update_selection_timeout");
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    var selected = provider_info == preferred_provider_info;

                    if (provider_info.selected != selected)
                    {
                        provider_info.selected = selected;
                        selection_changed = true;

                        if (selected) {
                            this.provider_selected ((T) provider_info.instance);
                        }
                        else {
                            this.provider_unselected ((T) provider_info.instance);
                        }

                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        /**
         * Disable all providers.
         */
        private void select_none ()
        {
            var selection_changed = false;

            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.selected) {
                        provider_info.selected = false;
                        selection_changed = true;

                        this.provider_unselected ((T) provider_info.instance);
                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        /**
         * Try enabling all providers.
         */
        private void select_all ()
        {
            var selection_changed = false;

            this.providers.@foreach (
                (provider_info) => {
                    if (!provider_info.selected) {
                        provider_info.selected = true;
                        selection_changed = true;
                        this.provider_selected ((T) provider_info.instance);
                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        private void update_selection ()
        {
            if (this.updating_selection) {
                this.selection_invalid = true;
                return;
            }

            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            if (this.update_selection_idle_id != 0) {
                GLib.Source.remove (this.update_selection_idle_id);
                this.update_selection_idle_id = 0;
            }

            this.updating_selection = true;
            this.selection_invalid = false;

            switch (this._selection_mode)
            {
                case Ft.SelectionMode.NONE:
                    this.select_none ();
                    break;

                case Ft.SelectionMode.SINGLE:
                    this.select_single ();
                    break;

                case Ft.SelectionMode.ALL:
                    this.select_all ();
                    break;

                default:
                    assert_not_reached ();
            }

            this.updating_selection = false;

            if (this.selection_invalid) {
                this.update_selection ();
            }
        }

        private void schedule_update_selection ()
        {
            if (this.update_selection_idle_id != 0) {
                return;
            }

            this.update_selection_idle_id = GLib.Idle.add (
                () => {
                    this.update_selection_idle_id = 0;
                    this.update_selection ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.update_selection_idle_id,
                                        "Ft.ProviderSet.update_selection");
        }

        private unowned Ft.ProviderInfo? lookup_info (Ft.Provider instance)
        {
            unowned Ft.ProviderInfo provider_info = null;

            this.providers.@foreach (
                (_provider_info) => {
                    if (_provider_info.instance == instance) {
                        provider_info = _provider_info;
                    }
                });

            return provider_info;
        }

        private bool on_update_selection_timeout ()
        {
            this.update_selection_timeout_id = 0;
            this.update_selection ();

            return GLib.Source.REMOVE;
        }

        private void on_provider_notify_available (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            var provider = (Ft.Provider) object;
            var provider_info = this.lookup_info (provider);

            assert (provider_info != null);

            if (provider_info.selected && provider.available) {
                this.check_provider_status (provider_info);
            }
            else {
                this.update_selection ();
            }
        }

        private void on_provider_notify_enabled (GLib.Object    object,
                                                 GLib.ParamSpec pspec)
        {
            var provider = (Ft.Provider) object;

            if (provider.enabled) {
                this.provider_enabled ((T) provider);
            }
            else {
                this.provider_disabled ((T) provider);
            }
        }

        private void destroy_info (Ft.ProviderInfo provider_info)
        {
            provider_info.instance.notify["available"].disconnect (this.on_provider_notify_available);
            provider_info.instance.notify["enabled"].connect (this.on_provider_notify_enabled);

            provider_info.destroying = true;

            if (provider_info.cancellable != null) {
                provider_info.cancellable.cancel ();
                provider_info.cancellable = null;
            }

            this.check_provider_status (provider_info);
        }

        public void add (T           provider,
                         Ft.Priority priority = Ft.Priority.DEFAULT)
        {
            var instance = provider as Ft.Provider;

            assert (instance != null);

            var existing_provider_info = this.lookup_info (instance);

            if (existing_provider_info != null) {
                existing_provider_info.priority = priority;
            }
            else {
                var provider_info = new Ft.ProviderInfo (instance, priority);

                if (this.providers.add (provider_info)) {
                    provider_info.instance.notify["available"].connect (this.on_provider_notify_available);
                    provider_info.instance.notify["enabled"].connect (this.on_provider_notify_enabled);
                }
            }

            this.schedule_update_selection ();
        }

        public void remove (T provider)
        {
            var instance = provider as Ft.Provider;

            assert (instance != null);

            var provider_info = this.lookup_info (instance);

            if (provider_info == null || !this.providers.remove (provider_info)) {
                return;
            }

            this.destroy_info (provider_info);

            if (provider_info.selected) {
                this.update_selection ();
            }
        }

        public void remove_all ()
        {
            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            this.providers.@foreach (
                (provider_info) => {
                    this.destroy_info (provider_info);
                });
            this.providers.remove_all ();
        }

        public void enable ()
        {
            this.should_enable = true;

            this.update_selection ();

            this.providers.@foreach (
                (provider_info) => {
                    this.check_provider_status (provider_info);
                });
        }

        public void disable ()
        {
            this.should_enable = false;

            this.providers.@foreach (
                (provider_info) => {
                    this.check_provider_status (provider_info);
                });
        }

        public void @foreach (GLib.Func<T> func)
        {
            this.providers.@foreach (
                (provider_info) => {
                    func ((T) provider_info.instance);
                });
        }

        public void foreach_selected (GLib.Func<T> func)
        {
            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.selected) {
                        func ((T) provider_info.instance);
                    }
                });
        }

        public void foreach_enabled (GLib.Func<T> func)
        {
            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.instance.enabled) {
                        func ((T) provider_info.instance);
                    }
                });
        }

        internal signal void provider_selected (T provider);

        internal signal void provider_unselected (T provider);

        public signal void provider_enabled (T provider);

        public signal void provider_disabled (T provider);

        public signal void selection_changed ();

        public override void dispose ()
        {
            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            if (this.update_selection_idle_id != 0) {
                GLib.Source.remove (this.update_selection_idle_id);
                this.update_selection_idle_id = 0;
            }

            if (this.providers != null)
            {
                this.remove_all ();

                this.providers = null;
            }

            base.dispose ();
        }
    }
}
