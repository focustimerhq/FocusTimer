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
        public bool active {
            get {
                return this._active;
            }
        }

        public bool handles_lock_delay {
            get {
                return false;
            }
        }

        private bool                _active = false;
        private GLib.Cancellable?   cancellable = null;
        private Ft.SessionManager?  session_manager = null;
        private uint                idle_inhibit_cookie = 0U;

        construct
        {
            this.available = true;
        }

        private void update_idle_inhibitor ()
        {
            var inhibit_idle = this._active &&
                               this.session_manager != null &&
                               !this.session_manager.lockscreen_active;
            var is_idle_inhibited = this.idle_inhibit_cookie != 0U;

            if (inhibit_idle == is_idle_inhibited) {
                return;
            }

            var application = GLib.Application.get_default () as Gtk.Application;

            if (application == null) {
                return;
            }

            if (inhibit_idle) {
                // translators: reason for inhibiting the session from going idle
                this.idle_inhibit_cookie = application.inhibit (null,
                                                                Gtk.ApplicationInhibitFlags.IDLE,
                                                                _("Screen overlay is open"));
            }
            else if (this.idle_inhibit_cookie != 0U) {
                application.uninhibit (this.idle_inhibit_cookie);
                this.idle_inhibit_cookie = 0U;
            }
        }

        private void on_session_manager_notify_lockscreen_active (GLib.Object    object,
                                                                  GLib.ParamSpec pspec)
        {
            this.update_idle_inhibitor ();
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
                        this._active = false;
                        this.notify_property ("active");
                        this.update_idle_inhibitor ();
                    }
                });

            if (!cancellable.is_cancelled ()) {
                this.cancellable = cancellable;
                this._active = true;
                this.notify_property ("active");
                this.update_idle_inhibitor ();
            }
        }

        public void close ()
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            this._active = false;
            this.notify_property ("active");
            this.update_idle_inhibitor ();
        }

        protected override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.session_manager = Ft.SessionManager.get_default ();
            this.session_manager.notify["lockscreen-active"].connect (
                    this.on_session_manager_notify_lockscreen_active);

            this.update_idle_inhibitor ();
        }

        protected override async void uninitialize () throws GLib.Error
        {
            if (this.session_manager != null) {
                this.session_manager.notify["lockscreen-active"].disconnect (
                        this.on_session_manager_notify_lockscreen_active);
                this.session_manager = null;
            }

            this.update_idle_inhibitor ();
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
