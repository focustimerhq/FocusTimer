/*
 * Copyright (c) 2017-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    public errordomain ShellExtensionError
    {
        TIMED_OUT,
        NOT_ALLOWED,
        DOWNLOAD_FAILED,
        OTHER
    }


    [SingleInstance]
    public class ShellExtension : GLib.Object
    {
        public const string EXTENSION_UUID = "focus-timer@focustimerhq.github.io";

        // When published we suggest to install it
        public const bool IS_PUBLISHED = false;

        [CCode (notify = false)]
        public bool available {
            get {
                return this._available;
            }
            private set {
                if (this._available != value) {
                    this._available = value;
                    this.notify_property ("available");
                }
            }
        }

        [CCode (notify = false)]
        public bool enabled {
            get {
                return this._enabled;
            }
            private set {
                if (this._enabled != value) {
                    this._enabled = value;
                    this.notify_property ("enabled");
                }
            }
        }

        public Gnome.ExtensionState state {
            get {
                return this.extension_info.state;
            }
        }

        public Gnome.ShellExtensionSettings? settings {
            get {
                return this._settings;
            }
        }

        private bool                            _available = false;
        private bool                            _enabled = false;
        private Gnome.ShellExtensionSettings?   _settings = null;
        private Gnome.ShellExtensions?          shell_extensions_proxy = null;
        private Gnome.ShellIntegration?         shell_integration_proxy = null;
        private Gnome.ExtensionInfo             extension_info;
        private uint                            shell_watcher_id = 0;
        private uint                            shell_integration_watcher_id = 0;
        private GLib.Cancellable?               cancellable = null;

        construct
        {
            this.extension_info = Gnome.ExtensionInfo (EXTENSION_UUID);
            this.cancellable = new GLib.Cancellable ();

            this.shell_watcher_id = GLib.Bus.watch_name (
                    GLib.BusType.SESSION,
                    "org.gnome.Shell",
                    GLib.BusNameWatcherFlags.NONE,
                    this.on_shell_name_appeared,
                    this.on_shell_name_vanished);
            this.shell_integration_watcher_id = GLib.Bus.watch_name (
                    GLib.BusType.SESSION,
                    "io.github.focustimerhq.FocusTimer.ShellIntegration",
                    GLib.BusNameWatcherFlags.NONE,
                    this.on_shell_integration_name_appeared,
                    this.on_shell_integration_name_vanished);
        }

        internal unowned Gnome.ShellIntegration? get_shell_integration_proxy ()
        {
            return this.shell_integration_proxy;
        }

        private void update_available ()
        {
            this.available = this.shell_extensions_proxy != null &&
                             this.shell_extensions_proxy.user_extensions_enabled &&
                             this.extension_info.state != Gnome.ExtensionState.UNKNOWN;
        }

        private void on_properties_changed (GLib.Variant changed_properties,
                                            string[]     invalidated_properties)
        {
            this.update_available ();
        }

        private void on_shell_name_appeared (GLib.DBusConnection connection,
                                             string              name,
                                             string              name_owner)
        {
            if (shell_extensions_proxy != null) {
                return;
            }

            try {
                this.shell_extensions_proxy = GLib.Bus.get_proxy_sync<Gnome.ShellExtensions> (
                        GLib.BusType.SESSION,
                        "org.gnome.Shell",
                        "/org/gnome/Shell",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                        this.cancellable);

                var shell_extensions_proxy = (GLib.DBusProxy) this.shell_extensions_proxy;
                shell_extensions_proxy.g_properties_changed.connect (this.on_properties_changed);

                this.shell_extensions_proxy.extension_state_changed.connect (
                        this.on_extension_state_changed);

                this.query_extension_state.begin ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while initializing extensions proxy: %s", error.message);
            }
        }

        private void on_shell_name_vanished (GLib.DBusConnection? connection,
                                             string               name)
        {
            if (this.shell_extensions_proxy == null) {
                return;
            }

            var shell_extensions_proxy = (GLib.DBusProxy) this.shell_extensions_proxy;
            shell_extensions_proxy.g_properties_changed.disconnect (this.on_properties_changed);

            this.shell_extensions_proxy.extension_state_changed.disconnect (
                    this.on_extension_state_changed);

            this.extension_info = Gnome.ExtensionInfo (EXTENSION_UUID);
            this.notify_property ("state");

            this.shell_extensions_proxy = null;
            this.available = false;
            this.enabled = false;
        }

        private void on_shell_integration_name_appeared (GLib.DBusConnection connection,
                                                         string              name,
                                                         string              name_owner)
        {
            if (this.shell_integration_proxy != null) {
                return;
            }

            try {
                this.shell_integration_proxy = GLib.Bus.get_proxy_sync<Gnome.ShellIntegration> (
                        GLib.BusType.SESSION,
                        "io.github.focustimerhq.FocusTimer.ShellIntegration",
                        "/io/github/focustimerhq/FocusTimer/ShellIntegration",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                        this.cancellable);

                this._settings = new Gnome.ShellExtensionSettings (this.shell_integration_proxy);
                this.notify_property ("settings");
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while initializing Shell integration proxy: %s", error.message);
            }
        }

        private void on_shell_integration_name_vanished (GLib.DBusConnection? connection,
                                                         string               name)
        {
            if (this._settings != null) {
                this._settings = null;
                this.notify_property ("settings");
            }

            this.shell_integration_proxy = null;
        }

        private void on_extension_state_changed (string                               uuid,
                                                 GLib.HashTable<string, GLib.Variant> state)
        {
            if (uuid != EXTENSION_UUID) {
                return;
            }

            this.extension_info = Gnome.ExtensionInfo.deserialize (uuid, state);
            this.enabled = this.extension_info.enabled;
            this.update_available ();
            this.notify_property ("state");
        }

        private async void query_extension_state ()
        {
            try {
                this.extension_info = Gnome.ExtensionInfo.deserialize (
                        EXTENSION_UUID,
                        yield this.shell_extensions_proxy.get_extension_info (EXTENSION_UUID));
                this.enabled = this.extension_info.enabled;
                this.notify_property ("state");
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while querying extension state: %s", error.message);
            }

            this.update_available ();
        }

        public bool is_installed ()
        {
            if (this.extension_info.state == Gnome.ExtensionState.UNINSTALLED) {
                return false;
            }

            return this.extension_info.path != "";
        }

        public bool has_update ()
        {
            return this.extension_info.has_update;
        }

        public async bool enable_extension ()
        {
            if (this.shell_extensions_proxy == null) {
                return false;
            }

            try {
                return yield this.shell_extensions_proxy.enable_extension (EXTENSION_UUID);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while enabling extension: %s", error.message);
                return false;
            }
        }

        public async bool disable_extension ()
        {
            if (this.shell_extensions_proxy == null) {
                return false;
            }

            try {
                return yield this.shell_extensions_proxy.disable_extension (EXTENSION_UUID);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while disabling extension: %s", error.message);
                return false;
            }
        }

        public async bool install_extension () throws Gnome.ShellExtensionError
        {
            if (this.shell_extensions_proxy == null) {
                return false;
            }

            try {
                var result = yield this.shell_extensions_proxy.install_remote_extension (EXTENSION_UUID);

                switch (result)
                {
                    case "successful":
                        return true;

                    case "cancelled":
                        return false;

                    default:
                        GLib.warning ("Unhandled InstallRemoteExtension result: `%s`", result);
                        return false;
                }
            }
            catch (GLib.IOError error) {
                if (error.code == GLib.IOError.TIMED_OUT) {
                    throw new Gnome.ShellExtensionError.TIMED_OUT ("Timed out");
                }

                if (error.code == GLib.IOError.DBUS_ERROR &&
                    error.message.contains ("Shell.Extensions.Error.NotAllowed"))
                {
                    throw new Gnome.ShellExtensionError.NOT_ALLOWED ("Not allowed");
                }

                if (error.code == GLib.IOError.DBUS_ERROR &&
                    error.message.contains ("Shell.Extensions.Error.InfoDownloadFailed") ||
                    error.message.contains ("Shell.Extensions.Error.DownloadFailed"))
                {
                    throw new Gnome.ShellExtensionError.DOWNLOAD_FAILED ("Failed to download the extension");
                }

                GLib.warning ("Error while installing extension: %s", error.message);
                throw new Gnome.ShellExtensionError.OTHER (error.message);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while installing extension: %s", error.message);
                throw new Gnome.ShellExtensionError.OTHER (error.message);
            }
        }

        public async bool uninstall_extension ()
        {
            if (this.shell_extensions_proxy == null) {
                return false;
            }

            try {
                return yield this.shell_extensions_proxy.uninstall_extension (EXTENSION_UUID);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while uninstalling extension: %s", error.message);
                return false;
            }
        }

        public override void dispose ()
        {
            if (this.shell_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.shell_watcher_id);
                this.shell_watcher_id = 0;
            }

            if (this.shell_integration_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.shell_integration_watcher_id);
                this.shell_integration_watcher_id = 0;
            }

            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            this._settings = null;
            this.shell_extensions_proxy = null;
            this.shell_integration_proxy = null;

            base.dispose ();
        }
    }
}
