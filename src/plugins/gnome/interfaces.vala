/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    [DBus (name = "org.gnome.ScreenSaver")]
    public interface ScreenSaver : GLib.Object
    {
        public abstract async bool get_active () throws GLib.DBusError, GLib.IOError;
        [DBus (no_reply = true)]
        public abstract async void @lock () throws GLib.DBusError, GLib.IOError;

        public signal void active_changed (bool active);
    }


    [DBus (name = "org.gnome.Mutter.IdleMonitor")]
    public interface IdleMonitor : GLib.Object
    {
        public abstract uint32 add_idle_watch (uint64 interval) throws GLib.DBusError, GLib.IOError;
        public abstract uint32 add_user_active_watch () throws GLib.DBusError, GLib.IOError;
        public abstract uint64 get_idletime () throws GLib.DBusError, GLib.IOError;
        public abstract void remove_watch (uint32 id) throws GLib.DBusError, GLib.IOError;

        public signal void watch_fired (uint32 id);
    }


    public enum ExtensionType
    {
        UNKNOWN = 0,
        SYSTEM = 1,
        PER_USER = 2;

        public string to_string ()
        {
            switch (this)
            {
                case SYSTEM:
                    return "system";

                case PER_USER:
                    return "per-user";

                case UNKNOWN:
                    return "";

                default:
                    assert_not_reached ();
            }
        }
    }


    public enum ExtensionState
    {
        UNKNOWN = 0,
        ENABLED = 1,
        INACTIVE = 2,
        ERROR = 3,
        OUT_OF_DATE = 4,
        DOWNLOADING = 5,
        INITIALIZED = 6,
        DEACTIVATING = 7,
        ACTIVATING = 8,

        // Used as an error state for operations on unknown extensions
        UNINSTALLED = 99;

        public string to_string ()
        {
            switch (this)
            {
                case ENABLED:
                    return "enabled";

                case INACTIVE:
                    return "inactive";

                case ERROR:
                    return "error";

                case OUT_OF_DATE:
                    return "out-of-date";

                case DOWNLOADING:
                    return "downloading";

                case INITIALIZED:
                    return "initialized";

                case UNINSTALLED:
                    return "uninstalled";

                case DEACTIVATING:
                    return "deactivating";

                case ACTIVATING:
                    return "activating";

                case UNKNOWN:
                    return "";

                default:
                    assert_not_reached ();
            }
        }
    }


    public struct ExtensionInfo
    {
        public string               uuid;
        public Gnome.ExtensionType  type;
        public Gnome.ExtensionState state;
        public bool                 enabled;
        public string               path;
        public string               error;
        public string               settings_schema;
        public bool                 has_prefs;
        public bool                 has_update;

        public ExtensionInfo (string uuid)
        {
            this.uuid = uuid;
            this.type = Gnome.ExtensionType.UNKNOWN;
            this.state = Gnome.ExtensionState.UNKNOWN;
            this.enabled = false;
            this.path = "";
            this.error = "";
            this.settings_schema = "";
        }

        public ExtensionInfo.deserialize (string                               uuid,
                                          GLib.HashTable<string, GLib.Variant> data)
        {
            this.uuid = data.contains ("uuid")
                    ? data.lookup ("uuid").get_string ()
                    : uuid;
            this.type = data.contains ("type")
                    ? (Gnome.ExtensionType) data.lookup ("type").get_double ()
                    : Gnome.ExtensionType.UNKNOWN;
            this.state = data.contains ("state")
                    ? (Gnome.ExtensionState) data.lookup ("state").get_double ()
                    : Gnome.ExtensionState.UNINSTALLED;
            this.enabled = data.contains ("enabled")
                    ? data.lookup ("enabled").get_boolean ()
                    : false;
            this.path = data.contains ("path")
                    ? data.lookup ("path").get_string ()
                    : "";
            this.error = data.contains ("error")
                    ? data.lookup ("error").get_string ()
                    : "";
            this.settings_schema = data.contains ("settings-schema")
                    ? data.lookup ("settings-schema").get_string ()
                    : "";
            this.has_prefs = data.contains ("hasPrefs")
                    ? data.lookup ("hasPrefs").get_boolean ()
                    : false;
            this.has_update = data.contains ("hasUpdate")
                    ? data.lookup ("hasUpdate").get_boolean ()
                    : false;
        }

        public string to_representation ()
        {
            var representation = new GLib.StringBuilder ("ExtensionInfo (\n");
            representation.append (@"    uuid = $uuid,\n");
            representation.append (@"    type = $(type.to_string()),\n");
            representation.append (@"    state = $(state.to_string()),\n");
            representation.append (@"    enabled = $enabled,\n");
            representation.append (@"    path = $path,\n");
            representation.append (@"    error = $error,\n");
            representation.append (@"    settings_schema = $settings_schema,\n");
            representation.append (@"    has_prefs = $has_prefs,\n");
            representation.append (@"    has_update = $has_update\n");
            representation.append (")");

            return representation.str;
        }
    }


    [DBus (name = "org.gnome.Shell.Extensions")]
    public interface ShellExtensions : GLib.Object
    {
        public abstract bool user_extensions_enabled { get; set; }

        public abstract async bool enable_extension
                                        (string uuid)
                                        throws GLib.DBusError, GLib.IOError;

        public abstract async bool disable_extension
                                        (string uuid)
                                        throws GLib.DBusError, GLib.IOError;

        public abstract async GLib.HashTable<string, GLib.Variant> get_extension_info
                                        (string uuid)
                                        throws GLib.DBusError, GLib.IOError;

        public abstract async string install_remote_extension
                                        (string uuid)
                                        throws GLib.DBusError, GLib.IOError;

        public abstract async bool uninstall_extension
                                        (string uuid)
                                        throws GLib.DBusError, GLib.IOError;

        public signal void extension_state_changed
                                        (string                               uuid,
                                         GLib.HashTable<string, GLib.Variant> state);
    }


    [DBus (name = "io.github.focustimerhq.FocusTimer.ShellIntegration")]
    public interface ShellIntegration : GLib.Object
    {
        public abstract string version { owned get; }
        public abstract string indicator_type { owned get; set; }
        public abstract bool enable_blur_effect { get; set; }
        public abstract bool enable_dismiss_gesture { get; set; }
        public abstract bool enable_manage_notifications { get; set; }

        public abstract async void open_screen_overlay () throws GLib.DBusError, GLib.IOError;
    }
}
