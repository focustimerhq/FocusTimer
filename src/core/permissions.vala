/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft.Permissions
{
    private int _has_flatpak_dbus_name = -1;

    private bool has_dbus_name (string dbus_name) throws GLib.Error
    {
        var connection = GLib.Bus.get_sync (GLib.BusType.SESSION);
        var response = connection.call_sync (
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            new GLib.Variant ("(s)", dbus_name),
            new GLib.VariantType ("(b)"),
            GLib.DBusCallFlags.NONE,
            -1
        );

        var exists = false;
        response.get ("(b)", out exists);

        return exists;
    }

    public bool allow_commands ()
    {
        if (!Ft.is_flatpak ()) {
            return true;
        }

        if (_has_flatpak_dbus_name == -1)
        {
            try {
                _has_flatpak_dbus_name = (int) has_dbus_name ("org.freedesktop.Flatpak");
            }
            catch (GLib.Error error) {
                GLib.debug ("Error while checking `allow_commands` permission: %s", error.message);
            }
        }

        return _has_flatpak_dbus_name > 0;
    }
}
