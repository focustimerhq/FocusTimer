/*
 * Copyright (c) 2025-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Portal
{
    public struct Shortcut
    {
        public string id;
        public string description;
        public string preferred_trigger;
        public string trigger_description;
    }


    [DBus (name = "org.freedesktop.portal.Request")]
    public interface Request : GLib.Object
    {
        [DBus (timeout = 5000)]
        public abstract async void close () throws GLib.DBusError, GLib.IOError;

        public signal void response (uint32                                    response,
                                     [DBus (signature = "a{sv}")] GLib.Variant results);
    }


    [DBus (name = "org.freedesktop.portal.Background")]
    public interface Background : GLib.Object
    {
        [DBus (name = "version")]
        public abstract uint32 version { get; }

        // The method returns a request handle; it is not a no-reply call.
        [DBus (timeout = 10000)]
        public abstract async GLib.ObjectPath request_background (
                string                                    parent_window,
                [DBus (signature = "a{sv}")] GLib.Variant options) throws GLib.DBusError, GLib.IOError;
    }


    [DBus (name = "org.freedesktop.portal.GlobalShortcuts")]
    public interface GlobalShortcuts : GLib.Object
    {
        [DBus (name = "version")]
        public abstract uint32 version { get; }

        public abstract async GLib.ObjectPath create_session (
                [DBus (signature = "a{sv}")] GLib.Variant options) throws GLib.DBusError, GLib.IOError;

        public abstract async GLib.ObjectPath bind_shortcuts (
                GLib.ObjectPath                               session_handle,
                [DBus (signature = "a(sa{sv})")] GLib.Variant shortcuts,
                string                                        parent_window,
                [DBus (signature = "a{sv}")] GLib.Variant     options) throws GLib.DBusError, GLib.IOError;

        public abstract async GLib.ObjectPath list_shortcuts (
                GLib.ObjectPath                           session_handle,
                [DBus (signature = "a{sv}")] GLib.Variant options) throws GLib.DBusError, GLib.IOError;

        public abstract async void configure_shortcuts (
                GLib.ObjectPath                           session_handle,
                string                                    parent_window,
                [DBus (signature = "a{sv}")] GLib.Variant options) throws GLib.DBusError, GLib.IOError;

        public signal void activated (GLib.ObjectPath                           session_handle,
                                      string                                    shortcut_id,
                                      uint64                                    timestamp,
                                      [DBus (signature = "a{sv}")] GLib.Variant options);

        public signal void deactivated (GLib.ObjectPath                           session_handle,
                                        string                                    shortcut_id,
                                        uint64                                    timestamp,
                                        [DBus (signature = "a{sv}")] GLib.Variant options);

        public signal void shortcuts_changed (GLib.ObjectPath session_handle,
                                              [DBus (signature = "a(sa{sv})")] GLib.Variant shortcuts);
    }


    /**
     * https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html
     */
    [DBus (name = "org.freedesktop.portal.Notification")]
    public interface Notification : GLib.Object
    {
        [DBus (name = "version")]
        public abstract uint32 version { get; }

        [DBus (signature = "a{sv}")]
        public abstract GLib.Variant supported_options { owned get; }

        public abstract async void add_notification (
                string                                    id,
                [DBus (signature = "a{sv}")] GLib.Variant notification,
                GLib.Cancellable?                         cancellable) throws GLib.DBusError, GLib.IOError;

        public abstract async void remove_notification (string id) throws GLib.DBusError, GLib.IOError;

        public signal void action_invoked (string id, string action, GLib.Variant[] parameter);
    }


    internal bool has_dbus_interface (GLib.DBusConnection connection,
                                      string              bus_name,
                                      string              object_path,
                                      string              interface_name,
                                      int                 timeout = -1)
    {
        try {
            var result = connection.call_sync (
                    bus_name,
                    object_path,
                    "org.freedesktop.DBus.Introspectable",
                    "Introspect",
                    null,
                    new GLib.VariantType ("(s)"),
                    GLib.DBusCallFlags.NONE,
                    timeout);

            string xml_data;
            result.get ("(s)", out xml_data);

            var node_info = new GLib.DBusNodeInfo.for_xml (xml_data);

            foreach (var iface in node_info.interfaces)
            {
                if (iface.name == interface_name) {
                    return true;
                }
            }
        }
        catch (GLib.Error error) {
            GLib.debug ("Failed to introspect %s: %s", bus_name, error.message);
        }

        return false;
    }


    internal bool has_dbus_method (GLib.DBusProxy proxy,
                                   string         name)
    {
        return proxy.g_interface_info?.lookup_method (name) != null;
    }
}
