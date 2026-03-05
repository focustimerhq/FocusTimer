/*
 * Copyright (c) 2017-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    public errordomain DesktopExtensionError
    {
        TIMED_OUT,
        NOT_ALLOWED,
        DOWNLOAD_FAILED,
        OTHER
    }


    public interface DesktopExtensionProvider : Ft.Provider
    {
        public abstract bool extension_enabled { get; }

        public abstract async bool enable_extension ();

        public abstract async bool disable_extension ();

        public abstract async bool install_extension () throws Ft.DesktopExtensionError;

        public abstract async bool uninstall_extension ();

        public abstract bool is_installed ();
    }


    [SingleInstance]
    public class DesktopExtension : GLib.Object
    {
        public bool available {
            get {
                return this._available;
            }
        }

        public bool enabled {
            get {
                return this._enabled;
            }
        }

        public unowned Ft.CapabilitySet capabilities {
            get {
                return this._capabilities;
            }
        }

        public unowned Ft.Provider provider {
            get {
                return this._provider;
            }
        }

        private Ft.ProviderSet<Ft.DesktopExtensionProvider> providers = null;
        private Ft.DesktopExtensionProvider? _provider = null;
        private Ft.CapabilitySet?            _capabilities = null;
        private bool                         _available = false;
        private bool                         _enabled = false;

        construct
        {
            this.providers = new Ft.ProviderSet<Ft.DesktopExtensionProvider> (Ft.SelectionMode.SINGLE);
            this.providers.provider_selected.connect (this.on_provider_selected);
            this.providers.provider_unselected.connect (this.on_provider_unselected);
            this.providers.provider_enabled.connect (this.on_provider_enabled);
            this.providers.provider_disabled.connect (this.on_provider_disabled);

            this._capabilities = new Ft.CapabilitySet ();

            this.setup_providers ();

            this.providers.enable ();
        }

        private void setup_providers ()
        {
            this.providers.add (new Gnome.DesktopExtensionProvider (), Ft.Priority.HIGH);
        }

        private void update_status ()
        {
            var available = this._provider != null && this._provider.enabled;
            var enabled = available && this._provider.extension_enabled
                    ? this._provider.extension_enabled
                    : false;

            if (this._available != available) {
                this._available = available;
                this.notify_property ("available");
            }

            if (this._enabled != enabled) {
                this._enabled = enabled;
                this.notify_property ("enabled");
            }
        }

        private void on_notify_extension_enabled (GLib.Object    object,
                                                  GLib.ParamSpec pspec)
        {
            this.update_status ();
        }

        private void on_provider_selected (Ft.DesktopExtensionProvider provider)
        {
            if (this._provider != provider) {
                this._provider = provider;
                this.notify_property ("provider");
            }

            this.update_status ();
        }

        private void on_provider_unselected (Ft.DesktopExtensionProvider provider)
        {
            if (this._provider == provider) {
                this._provider = null;
                this.notify_property ("provider");
            }

            this.update_status ();
        }

        private void on_provider_enabled (Ft.DesktopExtensionProvider provider)
        {
            provider.notify["extension-enabled"].connect (this.on_notify_extension_enabled);

            this.update_status ();
        }

        private void on_provider_disabled (Ft.DesktopExtensionProvider provider)
        {
            provider.notify["extension-enabled"].disconnect (this.on_notify_extension_enabled);

            this.update_status ();
        }

        public bool is_installed ()
        {
            return this._provider != null
                    ? this._provider.is_installed ()
                    : false;
        }

        public async bool enable ()
        {
            return this._provider != null
                    ? yield this._provider.enable_extension ()
                    : false;
        }

        public async bool disable ()
        {
            return this._provider != null
                    ? yield this._provider.disable_extension ()
                    : false;
        }

        public async bool install () throws Ft.DesktopExtensionError
        {
            return this._provider != null
                    ? yield this._provider.install_extension ()
                    : false;
        }

        public async bool uninstall ()
        {
            return this._provider != null
                    ? yield this._provider.uninstall_extension ()
                    : false;
        }

        public override void dispose ()
        {
            this.providers.provider_selected.disconnect (this.on_provider_selected);
            this.providers.provider_unselected.disconnect (this.on_provider_unselected);
            this.providers.provider_enabled.disconnect (this.on_provider_enabled);
            this.providers.provider_disabled.disconnect (this.on_provider_disabled);

            this._capabilities = null;
            this._provider = null;
            this.providers = null;

            base.dispose ();
        }
    }
}
