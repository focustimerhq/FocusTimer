/*
 * Copyright (c) 2013,2014,2016,2024 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    private class PreferencesPanelInfo : GLib.Object
    {
        public string    name { get; set; }
        public string    title { get; set; }
        public string    icon_name { get; set; }
        public GLib.Type content_class { get; set; }
        public bool      visible { get; set; default = true; }
    }


    private Gtk.SingleSelection create_model ()
    {
        Ft.PreferencesPanelInfo? panel_info;

        var model = new GLib.ListStore (typeof (Ft.PreferencesPanelInfo));

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "timer";
        panel_info.title = _("Timer");
        panel_info.icon_name = "timer-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelTimer);
        model.append (panel_info);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "notifications";
        panel_info.title = _("Notifications");
        panel_info.icon_name = "preferences-notifications-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelNotifications);
        model.append (panel_info);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "sounds";
        panel_info.title = _("Sounds");
        panel_info.icon_name = "preferences-sounds-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelSounds);
        model.append (panel_info);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "appearance";
        panel_info.title = _("Appearance");
        panel_info.icon_name = "preferences-appearance-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelAppearance);
        model.append (panel_info);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "keyboard-shortcuts";
        panel_info.title = _("Keyboard Shortcuts");
        panel_info.icon_name = "preferences-keyboard-shortcuts-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelKeyboardShortcuts);
        model.append (panel_info);

        var keyboard_manager = new Ft.KeyboardManager ();
        keyboard_manager.bind_property ("global-shortcuts-supported",
                                        panel_info,
                                        "visible",
                                        GLib.BindingFlags.SYNC_CREATE);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "integrations";
        panel_info.title = _("Integrations");
        panel_info.icon_name = "plugin-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelIntegrations);
        model.append (panel_info);

        panel_info = new PreferencesPanelInfo ();
        panel_info.name = "automation";
        panel_info.title = _("Automation");
        panel_info.icon_name = "custom-action-symbolic";
        panel_info.content_class = typeof (Ft.PreferencesPanelAutomation);
        model.append (panel_info);

        return new Gtk.SingleSelection ((owned) model);
    }


    public abstract class PreferencesPanel : Adw.NavigationPage
    {
        private unowned Adw.PreferencesGroup? find_named_group (Gtk.Widget widget,
                                                                string     name)
        {
            if (widget is Adw.PreferencesGroup)
            {
                if (widget.get_data<string> ("name") == name) {
                    return (Adw.PreferencesGroup) widget;
                }

                return null;
            }

            for (unowned var child = widget.get_first_child ();
                 child != null;
                 child = child.get_next_sibling ())
            {
                unowned var group = this.find_named_group (child, name);

                if (group != null) {
                    return group;
                }
            }

            return null;
        }

        private void apply_group_order ()
        {
            unowned string[]? order = this.get_group_order ();

            if (order == null || order.length == 0) {
                return;
            }

            unowned Adw.PreferencesGroup? first_group = null;

            foreach (var name in order)
            {
                first_group = this.get_group (name);

                if (first_group != null) {
                    break;
                }
            }

            if (first_group == null) {
                return;
            }

            unowned var parent = first_group.get_parent ();

            if (parent == null) {
                return;
            }

            // Keep preferences groups after non-group siblings (e.g. description).
            Gtk.Widget? previous = null;

            for (unowned var child = parent.get_first_child ();
                 child != null;
                 child = child.get_next_sibling ())
            {
                if (child is Adw.PreferencesGroup) {
                    break;
                }

                previous = child;
            }

            foreach (unowned string name in order)
            {
                unowned var group = this.get_group (name);

                if (group == null) {
                    continue;
                }

                group.insert_after (parent, previous);
                previous = group;
            }
        }

        public abstract unowned Adw.PreferencesPage get_preferences_page ();

        public unowned Adw.PreferencesGroup? get_group (string name)
        {
            unowned var page = this.get_preferences_page ();

            return this.find_named_group (page, name);
        }

        protected virtual unowned string[]? get_group_order ()
        {
            return null;
        }

        public void add_group (string               name,
                               Adw.PreferencesGroup group)
        {
            unowned var page = this.get_preferences_page ();

            group.set_data<string> ("name", name);
            page?.add (group);

            this.apply_group_order ();
        }

        public void remove_group (Adw.PreferencesGroup group)
        {
            unowned var page = this.get_preferences_page ();

            page?.remove (group);
        }
    }


    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/preferences-window.ui")]
    public class PreferencesWindow : Adw.ApplicationWindow, Gtk.Buildable
    {
        public Gtk.SingleSelection? model
        {
            get {
                return this._model;
            }
            construct {
                this._model = create_model ();
                this._model.selection_changed.connect (this.on_selection_changed);
            }
        }

        public Ft.PreferencesPanel? visible_panel {
            get {
                return this.split_view.content as Ft.PreferencesPanel;
            }
        }

        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild]
        private unowned Adw.NavigationSplitView split_view;
        [GtkChild]
        private unowned Ft.PreferencesSidebar sidebar;

        private Gtk.SingleSelection? _model = null;
        private GLib.Settings?       settings = null;
        private Peas.ExtensionSet?   extensions = null;

        construct
        {
            this.settings = Ft.get_settings ();
            this.sidebar.model = this._model;
            this.split_view.notify["collapsed"].connect (this.on_split_view_collapsed_notify);

            this.load_window_state ();
            this.update_split_view_content ();

            this.extensions = new Peas.ExtensionSet.with_properties (
                    Peas.Engine.get_default (),
                    typeof (Ft.PreferencesWindowExtension), {}, {});
            this.extensions.extension_added.connect (this.on_extension_added);

            foreach_extension (this.extensions,
                (object) => {
                    this.setup_extension (object);
                });
        }

        private void load_window_state ()
        {
            var current_width = -1;
            var current_height = -1;
            var maximized = false;

            this.settings.@get ("preferences-window-state",
                                "(iib)",
                                out current_width,
                                out current_height,
                                out maximized);

            if (current_width != -1 && current_height != -1) {
                this.set_default_size (current_width, current_height);
            }

            if (maximized) {
                this.maximize ();
            }
        }

        private void save_window_state ()
        {
            var current_width = -1;
            var current_height = -1;
            var maximized = this.is_maximized ();

            this.get_default_size (out current_width, out current_height);

            this.settings.@set ("preferences-window-state",
                                "(iib)",
                                current_width,
                                current_height,
                                maximized);
        }

        private void update_split_view_content ()
        {
            var panel_info = (Ft.PreferencesPanelInfo?) this._model.selected_item;

            if (panel_info != null)
            {
                var panel = (Ft.PreferencesPanel) GLib.Object.@new (
                        panel_info.content_class,
                        tag: panel_info.name,
                        title: panel_info.title);

                this.split_view.content = panel;
                this.split_view.show_content = true;

                this.notify_property ("visible-panel");
            }
            else {
                this.split_view.show_content = false;
            }
        }

        private void setup_extension (GLib.Object object)
        {
            var extension = (Ft.PreferencesWindowExtension) object;
            extension.window = this;
        }

        private void on_split_view_collapsed_notify ()
        {
            this.sidebar.selection_mode = this.split_view.collapsed
                    ? Gtk.SelectionMode.NONE
                    : Gtk.SelectionMode.SINGLE;
        }

        private void on_selection_changed (uint position,
                                           uint n_items)
        {
            this.update_split_view_content ();
        }

        private void on_extension_added (Peas.ExtensionSet extension_set,
                                         Peas.PluginInfo   plugin_info,
                                         GLib.Object       object)
        {
            this.setup_extension (object);
        }

        public bool select_panel (string panel_name)
        {
            var n_items = this._model.get_n_items ();

            for (var position = 0U; position < n_items; position++)
            {
                var panel_info = (Ft.PreferencesPanelInfo?) this._model.get_item (position);

                if (panel_info.name == panel_name) {
                    this._model.select_item (position, true);
                    return true;
                }
            }

            return false;
        }

        public void add_toast (owned Adw.Toast toast)
        {
            this.toast_overlay.add_toast (toast);
        }

        public override void unmap ()
        {
            this.save_window_state ();

            base.unmap ();
        }

        public override void dispose ()
        {
            if (this._model != null) {
                this._model.selection_changed.disconnect (this.on_selection_changed);
                this._model = null;
            }

            this.extensions = null;

            base.dispose ();
        }
    }
}
