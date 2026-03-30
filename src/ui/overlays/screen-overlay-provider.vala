/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    public class DefaultScreenOverlayProvider : Ft.Provider, Ft.ScreenOverlayProvider
    {
        private GLib.Cancellable? cancellable = null;

        construct
        {
            this.available = true;
        }

        public void open ()
        {
            if (this.cancellable != null &&
                !this.cancellable.is_cancelled ())
            {
                return;
            }

            var screen_overlay_group = new Ft.LightboxGroup (typeof (Ft.ScreenOverlay));
            var cancellable = new GLib.Cancellable ();

            screen_overlay_group.open.begin (
                cancellable,
                (obj, res) => {
                    try {
                        screen_overlay_group.open.end (res);
                    }
                    catch (GLib.Error error) {
                        if (!cancellable.is_cancelled ()) {
                            GLib.warning ("Failed to open overlay: %s", error.message);
                            cancellable.cancel ();
                        }
                    }

                    if (this.cancellable == cancellable) {
                        this.cancellable = null;
                        this.closed ();
                    }
                });

            if (!cancellable.is_cancelled ()) {
                this.cancellable = cancellable;
                this.opened ();
            }
        }

        public void close ()
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }
        }

        protected override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
        }

        protected override async void uninitialize () throws GLib.Error
        {
        }

        protected override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
        }

        protected override async void disable () throws GLib.Error
        {
            this.close ();
        }
    }
}
