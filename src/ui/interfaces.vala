/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 *
 * This module holds public interfaces for Peas extensions.
 */

namespace Ft
{
    public abstract class ApplicationExtension : GLib.Object
    {
    }


    public abstract class WindowExtension : GLib.Object
    {
        public Ft.Window? window {
            get {
                return this._window;
            }
            set {
                this._window = value;
            }
        }

        private unowned Ft.Window? _window = null;
    }


    public abstract class PreferencesWindowExtension : GLib.Object
    {
        public Ft.PreferencesWindow? window {
            get {
                return this._window;
            }
            set {
                this._window = value;
            }
        }

        private unowned Ft.PreferencesWindow? _window = null;
    }
}
