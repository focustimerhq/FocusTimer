/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    public interface ScreenOverlayProvider : Ft.Provider
    {
        public abstract bool active { get; }

        /**
         * Whether the provider applies the screen-overlay lock-delay itself.
         * When false, `Ft.ScreenOverlayManager` handles the lock-delay.
         */
        public abstract bool handles_lock_delay { get; }

        public abstract void open ();

        public abstract void close ();
    }


    /**
     * A helper primitive for representing the screen overlay.
     * The actual logic for showing/hiding the overlay is in `Ft.NotificationManager`.
     */
    [SingleInstance]
    public class ScreenOverlayManager : GLib.Object
    {
        [CCode (notify = false)]
        public bool active {
            get {
                return this._active;
            }
            private set {
                if (this._active == value) {
                    return;
                }

                this._active = value;
                this.notify_property ("active");
            }
        }

        [CCode (notify = false)]
        public Ft.ScreenOverlayProvider? provider {
            get {
                return this._provider;
            }
            private set {
                if (this._provider == value) {
                    return;
                }

                this._provider = value;
                this.notify_property ("provider");
            }
        }

        private bool                                        _active = false;
        private unowned Ft.ScreenOverlayProvider?           _provider = null;
        private Ft.ProviderSet<Ft.ScreenOverlayProvider>?   providers = null;
        private Ft.NotificationManager?                     notification_manager = null;
        private Ft.IdleMonitor?                             idle_monitor = null;
        private Ft.LockScreen?                              lock_screen = null;
        private GLib.Settings?                              settings = null;
        private uint                                        lock_delay_watch_id = 0;
        private uint                                        lock_delay_timeout_id = 0;

        construct
        {
            this.settings = Ft.get_settings ();

            this.lock_screen = new Ft.LockScreen ();
            this.lock_screen.notify["active"].connect (this.on_lock_screen_notify_active);

            this.idle_monitor = new Ft.IdleMonitor ();
            this.idle_monitor.notify["provider"].connect (this.on_idle_monitor_notify);
            this.idle_monitor.notify["enabled"].connect (this.on_idle_monitor_notify);

            this.notification_manager = new Ft.NotificationManager ();
            this.notification_manager.request_screen_overlay_open.connect (this.on_request_screen_overlay_open);
            this.notification_manager.request_screen_overlay_close.connect (this.on_request_screen_overlay_close);

            this.providers = new Ft.ProviderSet<Ft.ScreenOverlayProvider> (Ft.SelectionMode.SINGLE);
            this.providers.provider_selected.connect (this.on_provider_selected);
            this.providers.provider_unselected.connect (this.on_provider_unselected);

            this.providers.discover ();
            this.providers.enable ();
        }

        private void update_active ()
        {
            var active = this._provider != null && this._provider.active;

            if (this._active == active) {
                return;
            }

            this.active = active;
            this.update_lock_delay ();

            if (this.notification_manager == null) {
                return;
            }

            if (active) {
                this.notification_manager.emit_screen_overlay_opened ();
            }
            else {
                this.notification_manager.emit_screen_overlay_closed ();
            }
        }

        private void activate_lock_screen ()
        {
            if (this.lock_screen != null && this.lock_screen.enabled) {
                this.lock_screen.activate ();
            }
        }

        private void remove_lock_delay_watch ()
        {
            if (this.lock_delay_watch_id != 0) {
                this.idle_monitor?.remove_watch (this.lock_delay_watch_id);
                this.lock_delay_watch_id = 0;
            }
        }

        private void remove_lock_delay_timeout ()
        {
            if (this.lock_delay_timeout_id != 0) {
                GLib.Source.remove (this.lock_delay_timeout_id);
                this.lock_delay_timeout_id = 0;
            }
        }

        private void schedule_lock_delay_timeout (uint seconds)
        {
            this.remove_lock_delay_timeout ();

            if (seconds == 0 || !this._active) {
                return;
            }

            this.lock_delay_timeout_id = GLib.Timeout.add_seconds (
                seconds,
                () => {
                    this.lock_delay_timeout_id = 0;
                    this.activate_lock_screen ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.lock_delay_timeout_id,
                                        "Ft.ScreenOverlayManager.lock_delay");
        }

        private void update_lock_delay ()
        {
            if (!this._active ||
                this._provider == null ||
                this._provider.handles_lock_delay ||
                this.lock_screen == null ||
                this.lock_screen.active ||
                this.settings == null)
            {
                this.remove_lock_delay_watch ();
                this.remove_lock_delay_timeout ();
                return;
            }

            var lock_delay = this.settings.get_uint ("screen-overlay-lock-delay");

            if (lock_delay == 0) {
                this.remove_lock_delay_watch ();
                this.remove_lock_delay_timeout ();
                return;
            }

            if (this.idle_monitor != null &&
                this.idle_monitor.enabled &&
                this.idle_monitor.provider != null &&
                this.idle_monitor.provider.can_ignore_inhibitors)
            {
                this.lock_delay_watch_id = this.idle_monitor.add_idle_watch (
                        (int64) lock_delay * Ft.Interval.SECOND,
                        true,
                        this.activate_lock_screen,
                        GLib.get_monotonic_time ());
            }
            else {
                this.schedule_lock_delay_timeout (lock_delay);
            }
        }

        private void on_request_screen_overlay_open ()
        {
            this.open ();
        }

        private void on_request_screen_overlay_close ()
        {
            this.close ();
        }

        private void on_provider_notify_active (GLib.Object    object,
                                                GLib.ParamSpec pspec)
        {
            this.update_active ();
        }

        private void on_provider_selected (Ft.ScreenOverlayProvider provider)
        {
            provider.notify["active"].connect (this.on_provider_notify_active);

            this.provider = provider;
            this.update_active ();
        }

        private void on_provider_unselected (Ft.ScreenOverlayProvider provider)
        {
            provider.notify["active"].disconnect (this.on_provider_notify_active);

            if (this._provider == provider) {
                this.provider = null;
                this.update_active ();
            }
        }

        private void on_lock_screen_notify_active (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            this.update_lock_delay ();
        }

        private void on_idle_monitor_notify (GLib.Object    object,
                                             GLib.ParamSpec pspec)
        {
            if (this._active) {
                this.update_lock_delay ();
            }
        }

        // TODO: providers should be registered staticly
        public void add_provider (Ft.ScreenOverlayProvider provider,
                                  Ft.Priority              priority = Ft.Priority.DEFAULT)
        {
            this.providers.add (provider, priority);
        }

        public void open ()
        {
            this._provider?.open ();
        }

        public void close ()
        {
            this._provider?.close ();
        }

        public void mark_user_activity ()
        {
            if (this.lock_delay_timeout_id != 0 && this.settings != null)
            {
                var lock_delay = this.settings.get_uint ("screen-overlay-lock-delay");

                this.schedule_lock_delay_timeout (lock_delay);
            }
        }

        public override void dispose ()
        {
            this.provider = null;
            this.update_active ();
            this.remove_lock_delay_watch ();
            this.remove_lock_delay_timeout ();

            if (this.notification_manager != null) {
                this.notification_manager.request_screen_overlay_open.disconnect (this.on_request_screen_overlay_open);
                this.notification_manager.request_screen_overlay_close.disconnect (this.on_request_screen_overlay_close);
                this.notification_manager = null;
            }

            if (this.idle_monitor != null) {
                this.idle_monitor.notify["provider"].disconnect (this.on_idle_monitor_notify);
                this.idle_monitor.notify["enabled"].disconnect (this.on_idle_monitor_notify);
                this.idle_monitor = null;
            }

            if (this.lock_screen != null) {
                this.lock_screen.notify["active"].disconnect (this.on_lock_screen_notify_active);
                this.lock_screen = null;
            }

            this.providers = null;
            this.settings = null;

            base.dispose ();
        }
    }
}
