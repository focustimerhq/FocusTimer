/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    public interface ScreenOverlayProvider : Ft.Provider
    {
        public abstract void open ();

        public abstract void close ();

        public signal void opened ();

        public signal void closed ();
    }


    /**
     * A helper primitive for representing the screen overlay.
     * The actual logic for showing/hiding the overlay is in `Ft.NotificationManager`.
     */
    [SingleInstance]
    public class ScreenOverlayManager : GLib.Object
    {
        public Ft.ScreenOverlayProvider? provider {
            get {
                return this._provider;
            }
        }

        private Ft.ProviderSet<Ft.ScreenOverlayProvider>? providers = null;
        private unowned Ft.ScreenOverlayProvider? _provider = null;
        private Ft.NotificationManager? notification_manager = null;

        construct
        {
            this.notification_manager = new Ft.NotificationManager ();
            this.notification_manager.request_screen_overlay_open.connect (this.on_request_screen_overlay_open);
            this.notification_manager.request_screen_overlay_close.connect (this.on_request_screen_overlay_close);

            this.providers = new Ft.ProviderSet<Ft.ScreenOverlayProvider> (Ft.SelectionMode.SINGLE);
            this.providers.provider_selected.connect (this.on_provider_selected);
            this.providers.provider_unselected.connect (this.on_provider_unselected);
            this.providers.enable ();
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

        private void on_request_screen_overlay_open ()
        {
            this.open ();
        }

        private void on_request_screen_overlay_close ()
        {
            this.close ();
        }

        private void on_screen_overlay_opened (Ft.ScreenOverlayProvider provider)
        {
            this.notification_manager.screen_overlay_opened ();
        }

        private void on_screen_overlay_closed (Ft.ScreenOverlayProvider provider)
        {
            this.notification_manager.screen_overlay_closed ();
        }

        private void on_provider_selected (Ft.ScreenOverlayProvider provider)
        {
            provider.opened.connect (this.on_screen_overlay_opened);
            provider.closed.connect (this.on_screen_overlay_closed);

            this._provider = provider;
            this.notify_property ("provider");
        }

        private void on_provider_unselected (Ft.ScreenOverlayProvider provider)
        {
            provider.opened.disconnect (this.on_screen_overlay_opened);
            provider.closed.disconnect (this.on_screen_overlay_closed);
        }

        public override void dispose ()
        {
            if (this.notification_manager != null) {
                this.notification_manager.request_screen_overlay_open.disconnect (this.on_request_screen_overlay_open);
                this.notification_manager.request_screen_overlay_close.disconnect (this.on_request_screen_overlay_close);
                this.notification_manager = null;
            }

            this._provider = null;
            this.providers = null;

            base.dispose ();
        }
    }
}
