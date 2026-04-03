/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    /**
     * Settings of a `ShellIntegration` may have different lifespan than `ShellExtension`,
     * therefore settings are represented separately.
     */
    public class ShellExtensionSettings : GLib.Object
    {
        public string indicator_type {
            owned get {
                return this.proxy != null
                        ? this.proxy.indicator_type
                        : "";
            }
            set {
                if (this.proxy != null) {
                    this.proxy.indicator_type = value;
                }
            }
        }

        public bool blur_effect {
            get {
                return this.proxy != null
                        ? this.proxy.enable_blur_effect
                        : false;
            }
            set {
                if (this.proxy != null) {
                    this.proxy.enable_blur_effect = value;
                }
            }
        }

        public bool dismiss_gesture {
            get {
                return this.proxy != null
                        ? this.proxy.enable_dismiss_gesture
                        : false;
            }
            set {
                if (this.proxy != null) {
                    this.proxy.enable_dismiss_gesture = value;
                }
            }
        }

        public bool manage_notifications {
            get {
                return this.proxy != null
                        ? this.proxy.enable_manage_notifications
                        : false;
            }
            set {
                if (this.proxy != null) {
                    this.proxy.enable_manage_notifications = value;
                }
            }
        }

        private Gnome.ShellIntegration? proxy = null;

        public ShellExtensionSettings (Gnome.ShellIntegration shell_integration_proxy)
        {
            this.proxy = shell_integration_proxy;

            var proxy = (GLib.DBusProxy) shell_integration_proxy;
            proxy.g_properties_changed.connect (this.on_properties_changed);
        }

        private void on_properties_changed (GLib.Variant changed_properties,
                                            string[]     invalidated_properties)
        {
            if (changed_properties.lookup_value ("IndicatorType", null) != null) {
                this.notify_property ("indicator-type");
            }

            if (changed_properties.lookup_value ("EnableBlurEffect", null) != null) {
                this.notify_property ("blur_effect");
            }

            if (changed_properties.lookup_value ("EnableDismissGesture", null) != null) {
                this.notify_property ("dismiss-gesture");
            }

            if (changed_properties.lookup_value ("EnableManageNotifications", null) != null) {
                this.notify_property ("manage-notifications");
            }
        }

        public override void dispose ()
        {
            if (this.proxy != null)
            {
                var proxy = (GLib.DBusProxy) this.proxy;
                proxy.g_properties_changed.disconnect (this.on_properties_changed);

                this.proxy = null;
            }

            base.dispose ();
        }
    }
}
