/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    private GLib.Variant build_platform_data (string activation_token)
    {
        var platform_data = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));

        if (activation_token != null && activation_token != "") {
            platform_data.add ("{sv}", "activation-token", new GLib.Variant.string (activation_token));
        }

        return platform_data.end ();
    }


    private inline string format_remaining_time (int64 remaining)
    {
        var seconds_uint = (uint) Ft.round_seconds (Ft.Timestamp.to_seconds (remaining));

        return _("%s remaining").printf (Ft.format_time (seconds_uint));
    }


    private string format_tooltip_title (Ft.State state,
                                         uint     cycle_number,
                                         uint     cycle_count,
                                         bool     is_finished)
    {
        if (is_finished) {
            return _("Finished!");
        }

        if (cycle_number > 0 && cycle_count > 1 && (
            state == Ft.State.POMODORO || state == Ft.State.SHORT_BREAK))
        {
            var state_label = state.get_label ();
            var cycle_label = _("%u of %u").printf (cycle_number, cycle_count);

            return @"$(state_label) ($(cycle_label))";
        }

        return state.get_label ();
    }


    private string normalize_separators (string resource_path)
    {
        return resource_path.replace ("/", GLib.Path.DIR_SEPARATOR_S);
    }


    private errordomain IndicatorError
    {
        CONNECTION,
        HOST,
        INDICATOR,
        INDICATOR_MENU
    }


    /**
     * Class for exporting and updating the indicator and its context menu
     */
    private class IndicatorController
    {
        private const string BUS_NAME = "%s.StatusNotifierItem";
        private const string OBJECT_PATH = "/StatusNotifierItem";
        private const string MENU_OBJECT_PATH = "%s/StatusNotifierMenu";

        private const uint ICON_STEPS = 20U;
        private const string[] ICONS = {
            "16x16/status/indicator-break-000-symbolic.svg",
            "16x16/status/indicator-break-005-symbolic.svg",
            "16x16/status/indicator-break-010-symbolic.svg",
            "16x16/status/indicator-break-015-symbolic.svg",
            "16x16/status/indicator-break-020-symbolic.svg",
            "16x16/status/indicator-break-025-symbolic.svg",
            "16x16/status/indicator-break-030-symbolic.svg",
            "16x16/status/indicator-break-035-symbolic.svg",
            "16x16/status/indicator-break-040-symbolic.svg",
            "16x16/status/indicator-break-045-symbolic.svg",
            "16x16/status/indicator-break-050-symbolic.svg",
            "16x16/status/indicator-break-055-symbolic.svg",
            "16x16/status/indicator-break-060-symbolic.svg",
            "16x16/status/indicator-break-065-symbolic.svg",
            "16x16/status/indicator-break-070-symbolic.svg",
            "16x16/status/indicator-break-075-symbolic.svg",
            "16x16/status/indicator-break-080-symbolic.svg",
            "16x16/status/indicator-break-085-symbolic.svg",
            "16x16/status/indicator-break-090-symbolic.svg",
            "16x16/status/indicator-break-095-symbolic.svg",
            "16x16/status/indicator-break-100-symbolic.svg",
            "16x16/status/indicator-break-paused-symbolic.svg",
            "16x16/status/indicator-pomodoro-000-symbolic.svg",
            "16x16/status/indicator-pomodoro-005-symbolic.svg",
            "16x16/status/indicator-pomodoro-010-symbolic.svg",
            "16x16/status/indicator-pomodoro-015-symbolic.svg",
            "16x16/status/indicator-pomodoro-020-symbolic.svg",
            "16x16/status/indicator-pomodoro-025-symbolic.svg",
            "16x16/status/indicator-pomodoro-030-symbolic.svg",
            "16x16/status/indicator-pomodoro-035-symbolic.svg",
            "16x16/status/indicator-pomodoro-040-symbolic.svg",
            "16x16/status/indicator-pomodoro-045-symbolic.svg",
            "16x16/status/indicator-pomodoro-050-symbolic.svg",
            "16x16/status/indicator-pomodoro-055-symbolic.svg",
            "16x16/status/indicator-pomodoro-060-symbolic.svg",
            "16x16/status/indicator-pomodoro-065-symbolic.svg",
            "16x16/status/indicator-pomodoro-070-symbolic.svg",
            "16x16/status/indicator-pomodoro-075-symbolic.svg",
            "16x16/status/indicator-pomodoro-080-symbolic.svg",
            "16x16/status/indicator-pomodoro-085-symbolic.svg",
            "16x16/status/indicator-pomodoro-090-symbolic.svg",
            "16x16/status/indicator-pomodoro-095-symbolic.svg",
            "16x16/status/indicator-pomodoro-100-symbolic.svg",
            "16x16/status/indicator-pomodoro-paused-symbolic.svg",
            "16x16/status/indicator-stopped-symbolic.svg",
            "22x22/status/indicator-break-000-symbolic.svg",
            "22x22/status/indicator-break-005-symbolic.svg",
            "22x22/status/indicator-break-010-symbolic.svg",
            "22x22/status/indicator-break-015-symbolic.svg",
            "22x22/status/indicator-break-020-symbolic.svg",
            "22x22/status/indicator-break-025-symbolic.svg",
            "22x22/status/indicator-break-030-symbolic.svg",
            "22x22/status/indicator-break-035-symbolic.svg",
            "22x22/status/indicator-break-040-symbolic.svg",
            "22x22/status/indicator-break-045-symbolic.svg",
            "22x22/status/indicator-break-050-symbolic.svg",
            "22x22/status/indicator-break-055-symbolic.svg",
            "22x22/status/indicator-break-060-symbolic.svg",
            "22x22/status/indicator-break-065-symbolic.svg",
            "22x22/status/indicator-break-070-symbolic.svg",
            "22x22/status/indicator-break-075-symbolic.svg",
            "22x22/status/indicator-break-080-symbolic.svg",
            "22x22/status/indicator-break-085-symbolic.svg",
            "22x22/status/indicator-break-090-symbolic.svg",
            "22x22/status/indicator-break-095-symbolic.svg",
            "22x22/status/indicator-break-100-symbolic.svg",
            "22x22/status/indicator-break-paused-symbolic.svg",
            "22x22/status/indicator-pomodoro-000-symbolic.svg",
            "22x22/status/indicator-pomodoro-005-symbolic.svg",
            "22x22/status/indicator-pomodoro-010-symbolic.svg",
            "22x22/status/indicator-pomodoro-015-symbolic.svg",
            "22x22/status/indicator-pomodoro-020-symbolic.svg",
            "22x22/status/indicator-pomodoro-025-symbolic.svg",
            "22x22/status/indicator-pomodoro-030-symbolic.svg",
            "22x22/status/indicator-pomodoro-035-symbolic.svg",
            "22x22/status/indicator-pomodoro-040-symbolic.svg",
            "22x22/status/indicator-pomodoro-045-symbolic.svg",
            "22x22/status/indicator-pomodoro-050-symbolic.svg",
            "22x22/status/indicator-pomodoro-055-symbolic.svg",
            "22x22/status/indicator-pomodoro-060-symbolic.svg",
            "22x22/status/indicator-pomodoro-065-symbolic.svg",
            "22x22/status/indicator-pomodoro-070-symbolic.svg",
            "22x22/status/indicator-pomodoro-075-symbolic.svg",
            "22x22/status/indicator-pomodoro-080-symbolic.svg",
            "22x22/status/indicator-pomodoro-085-symbolic.svg",
            "22x22/status/indicator-pomodoro-090-symbolic.svg",
            "22x22/status/indicator-pomodoro-095-symbolic.svg",
            "22x22/status/indicator-pomodoro-100-symbolic.svg",
            "22x22/status/indicator-pomodoro-paused-symbolic.svg",
            "22x22/status/indicator-stopped-symbolic.svg",
            "32x32/status/indicator-passive-symbolic.svg",
            "scalable/actions/ornament-check-symbolic.svg",
            "scalable/actions/ornament-dot-checked-symbolic.svg",
            "scalable/actions/ornament-dot-unchecked-symbolic.svg",
            "scalable/actions/timer-pause-symbolic.svg",
            "scalable/actions/timer-reset-symbolic.svg",
            "scalable/actions/timer-skip-symbolic.svg",
            "scalable/actions/timer-skip-symbolic-rtl.svg",
            "scalable/actions/timer-start-symbolic.svg",
            "scalable/actions/timer-stop-symbolic.svg",
            "index.theme",
        };
        private const string[] SCALES = {
            "@2",
        };

        private GLib.DBusConnection?               connection = null;
        private Sni.StatusNotifierWatcher?         watcher_proxy = null;
        private Ft.Timer?                          timer = null;
        private Ft.SessionManager?                 session_manager = null;
        private Ft.NotificationManager?            notification_manager = null;
        private GLib.Settings?                     application_settings = null;
        private Sni.IndicatorActionGroup?          action_group = null;
        private uint                               name_owner_id = 0;
        private Sni.StatusNotifierItemDBusService? service = null;
        private uint                               service_id = 0;
        private Sni.DBusMenuService?               menu_service = null;
        private uint                               menu_service_id = 0;
        private unowned Sni.MenuItem?              primary_item = null;
        private unowned Sni.MenuItem?              secondary_item = null;
        private uint                               update_icon_timeout_id = 0U;
        private uint                               update_idle_id = 0U;
        private string?                            tooltip_title = null;
        private bool                               is_completed = false;
        private bool                               have_icon_theme;
        private bool                               have_passive_status;
        private bool                               have_attention_status;
        private bool                               have_activation;
        private bool                               have_menu_icons;
        private bool                               have_tooltips;
        private bool                               have_toggles;

        public IndicatorController (GLib.DBusConnection       connection,
                                    Sni.StatusNotifierWatcher watcher_proxy)
        {
            this.connection = connection;
            this.watcher_proxy = watcher_proxy;

            this.timer = Ft.Timer.get_default ();
            this.session_manager = Ft.SessionManager.get_default ();
            this.notification_manager = new Ft.NotificationManager ();
            this.application_settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer");
            this.action_group = new Sni.IndicatorActionGroup ();
            this.have_icon_theme = Sni.Capabilities.have_icon_theme ();
            this.have_passive_status = Sni.Capabilities.have_passive_status ();
            this.have_attention_status = Sni.Capabilities.have_attention_status ();
            this.have_activation = Sni.Capabilities.have_activation ();
            this.have_menu_icons = Sni.Capabilities.have_menu_icons ();
            this.have_tooltips = Sni.Capabilities.have_tooltips ();
            this.have_toggles = Sni.Capabilities.have_toggles ();
        }

        ~IndicatorController ()
        {
            if (this.service_id != 0 || this.menu_service_id != 0 || this.name_owner_id != 0) {
                GLib.critical ("SNI D-Bus services not destroyed properly");
            }

            this.service = null;
            this.menu_service = null;
            this.watcher_proxy = null;
            this.connection = null;
            this.action_group = null;
            this.timer = null;
            this.session_manager = null;
            this.application_settings = null;
            this.notification_manager = null;
            this.primary_item = null;
            this.secondary_item = null;
        }

        private Sni.MenuItem build_menu ()
        {
            var is_rtl = Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL;

            var start_item = new Sni.MenuItem ("start", _("Start Pomodoro"), "timer-start-symbolic", "timer.start");
            start_item.visible = false;

            var pause_item = new Sni.MenuItem ("pause", _("Pause"), "timer-pause-symbolic", "timer.pause");
            pause_item.visible = false;

            var resume_item = new Sni.MenuItem ("resume", _("Resume"), "timer-start-symbolic", "timer.resume");
            resume_item.visible = false;

            var advance_item = new Sni.MenuItem ("advance", "", "timer-start-symbolic", "session-manager.advance");
            advance_item.visible = false;

            var stop_item = new Sni.MenuItem ("stop", _("Stop"), "timer-stop-symbolic", "timer.reset");
            stop_item.visible = false;

            var skip_item = new Sni.MenuItem ("skip", "", is_rtl ? "timer-skip-symbolic-rtl" : "timer-skip-symbolic", "session-manager.advance");
            skip_item.visible = false;

            var reset_item = new Sni.MenuItem ("reset", _("Reset"), "timer-reset-symbolic", "session-manager.reset");
            reset_item.visible = false;

            var pomodoro_item = new Sni.MenuItem ("pomodoro", _("Pomodoro"), "", "session-manager.state", new GLib.Variant.string ("pomodoro"));
            var short_break_item = new Sni.MenuItem ("short-break", _("Short Break"), "", "session-manager.state", new GLib.Variant.string ("short-break"));
            var long_break_item = new Sni.MenuItem ("long-break", _("Long Break"), "", "session-manager.state", new GLib.Variant.string ("long-break"));
            var break_item = new Sni.MenuItem ("break", _("Break"), "", "session-manager.state", new GLib.Variant.string ("break"));

            if (this.have_toggles) {
                pomodoro_item.toggle_type = Sni.MenuToggleType.RADIO;
                short_break_item.toggle_type = Sni.MenuToggleType.RADIO;
                long_break_item.toggle_type = Sni.MenuToggleType.RADIO;
                break_item.toggle_type = Sni.MenuToggleType.RADIO;
            }

            var root = new Sni.MenuItem.root ();
            root.append (start_item);
            root.append (pause_item);
            root.append (resume_item);
            root.append (advance_item);
            root.append (stop_item);
            root.append (skip_item);
            root.append (reset_item);
            root.append (new Sni.MenuItem.separator ("state-separator"));
            root.append (pomodoro_item);
            root.append (short_break_item);
            root.append (long_break_item);
            root.append (break_item);
            root.append (new Sni.MenuItem.separator ());
            root.append (new Sni.MenuItem ("screen-overlay", _("Screen Overlay"), "", "app.screen-overlay"));

            if (this.have_activation) {
                root.append (new Sni.MenuItem ("preferences", _("Preferences"), "", "app.preferences"));
                root.append (new Sni.MenuItem ("stats", _("Stats"), "", "app.window", new GLib.Variant.string ("stats")));
            }
            else {
                root.append (new Sni.MenuItem ("timer", _("Timer"), "", "app.window", new GLib.Variant.string ("timer")));
                root.append (new Sni.MenuItem ("stats", _("Stats"), "", "app.window", new GLib.Variant.string ("stats")));
                root.append (new Sni.MenuItem ("preferences", _("Preferences"), "", "app.preferences"));
            }

            root.append (new Sni.MenuItem.separator ());
            root.append (new Sni.MenuItem ("quit", _("Quit"), "", "indicator.quit"));

            if (!this.have_menu_icons) {
                root.traverse (menu_item => { menu_item.icon_name = ""; });
            }

            return root;
        }

        private void get_cycle_number_count (out uint cycle_number,
                                             out uint cycle_count)
        {
            var tmp_cycle_number = 0U;
            var tmp_cycle_count = 0U;

            this.session_manager.current_session?.get_cycles ().@foreach (
                (cycle) => {
                    var cycle_status = cycle.get_status ();

                    if (cycle_status == Ft.TimeBlockStatus.UNCOMPLETED ||
                        cycle.get_weight () <= 0.0) {
                        return;
                    }

                    if (cycle_status == Ft.TimeBlockStatus.COMPLETED ||
                        cycle_status == Ft.TimeBlockStatus.IN_PROGRESS) {
                        tmp_cycle_number++;
                    }

                    tmp_cycle_count++;
                });

            cycle_number = tmp_cycle_number;
            cycle_count = tmp_cycle_count;
        }

        private void set_toggle_state (Sni.MenuItem menu_item,
                                       bool         value)
        {
            if (this.have_toggles) {
                menu_item.toggle_state = value;
            }
            else {
                menu_item.icon_name = value
                        ? "ornament-dot-checked-symbolic"
                        : "ornament-dot-unchecked-symbolic";
            }
        }

        private string get_skip_label (int64 timestamp)
        {
            unowned var current_time_block = this.session_manager.current_time_block;

            if (current_time_block != null && current_time_block.state.is_break ()) {
                return current_time_block.has_reached_completion (timestamp)
                        ? _("Start Pomodoro")
                        : _("Skip Break");
            }

            return _("Take a Break");
        }

        private void update_menu_items (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            var state = this.session_manager.current_state;
            var is_break = state.is_break ();
            var is_started = this.timer.is_started ();
            var is_paused = this.timer.is_paused ();
            var is_finished = this.timer.is_finished ();

            unowned var current_time_block = this.session_manager.current_time_block;
            this.is_completed = current_time_block != null &&
                                current_time_block.has_reached_completion (timestamp);

            // Timer
            string primary_name = null;
            string secondary_name = null;

            if (!is_started) {
                primary_name = "start";
                secondary_name = this.session_manager.can_reset () ? "reset" : null;
            }
            else {
                if (is_paused) {
                    primary_name = "resume";
                    secondary_name = "stop";
                }
                else if (is_finished) {
                    primary_name = "advance";
                    secondary_name = "stop";
                }
                else {
                    primary_name = "pause";
                    secondary_name = "skip";
                }
            }

            if (this.primary_item?.name != primary_name)
            {
                if (this.primary_item != null) {
                    this.primary_item.visible = false;
                }

                if (primary_name != null) {
                    this.primary_item = this.menu_service.lookup_menu_item (primary_name);
                    this.primary_item.visible = true;
                }
            }

            if (this.secondary_item?.name != secondary_name)
            {
                if (this.secondary_item != null) {
                    this.secondary_item.visible = false;
                }

                if (secondary_name != null) {
                    this.secondary_item = this.menu_service.lookup_menu_item (secondary_name);
                    this.secondary_item.visible = true;
                }
            }

            if (primary_name == "advance") {
                this.primary_item.label = is_break ? _("Start Pomodoro") : _("Take a Break");
            }

            if (secondary_name == "skip") {
                this.secondary_item.label = this.get_skip_label (timestamp);
            }

            // State
            var state_separator = this.menu_service.lookup_menu_item ("state-separator");
            state_separator.visible = is_started;

            var pomodoro_item = this.menu_service.lookup_menu_item ("pomodoro");
            pomodoro_item.visible = is_started;
            this.set_toggle_state (pomodoro_item, state == Ft.State.POMODORO);

            var break_item = this.menu_service.lookup_menu_item ("break");
            break_item.visible = is_started && this.session_manager.has_uniform_breaks;
            this.set_toggle_state (break_item, state == Ft.State.BREAK);

            var short_break_item = this.menu_service.lookup_menu_item ("short-break");
            short_break_item.visible = is_started && !break_item.visible;
            this.set_toggle_state (short_break_item, state == Ft.State.SHORT_BREAK);

            var long_break_item = this.menu_service.lookup_menu_item ("long-break");
            long_break_item.visible = is_started && !break_item.visible;
            this.set_toggle_state (long_break_item, state == Ft.State.LONG_BREAK);

            // Windows
            var screen_overlay_item = this.menu_service.lookup_menu_item ("screen-overlay");
            screen_overlay_item.enabled = is_break && !is_finished;
            screen_overlay_item.visible = is_break &&
                    this.application_settings.get_boolean ("screen-overlay");

            menu_service.emit_updates ();
        }

        private void update_is_completed (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            unowned var current_time_block = this.session_manager.current_time_block;
            var is_completed = current_time_block != null &&
                               current_time_block.has_reached_completion (timestamp);

            if (is_completed != this.is_completed) {
                this.is_completed = is_completed;
                this.update_menu_items (timestamp);
            }
        }

        /**
         * Extract icon theme from gresource to cache directory.
         */
        private async void extract_icons (string           icons_path,
                                          GLib.Cancellable cancellable) throws GLib.Error
        {
            if (!this.have_icon_theme) {
                return;
            }

            var icons_theme_path = GLib.Path.build_filename (icons_path, "hicolor");
            var directories = new GLib.GenericSet<string> (GLib.str_hash, GLib.str_equal);
            var sizes = new GLib.GenericSet<string> (GLib.str_hash, GLib.str_equal);

            foreach (var filename in ICONS)
            {
                if (cancellable.is_cancelled ()) {
                    return;
                }

                try {
                    var icon_file = GLib.File.new_build_filename (
                            icons_theme_path,
                            normalize_separators (filename));
                    var icon_data = GLib.resources_lookup_data (
                            @"/plugins/sni/icons/$(filename)",
                            GLib.ResourceLookupFlags.NONE);
                    var directory = icon_file.get_parent ();
                    var directory_path = directory.get_path ();

                    if (!directories.contains (directory_path))
                    {
                        directories.add (directory_path);

                        if (!directory.query_exists ()) {
                            directory.make_directory_with_parents (cancellable);
                        }

                        var filename_parts = filename.split ("/");
                        if (filename_parts.length == 3) {  // size, category, icon name
                            sizes.add (filename_parts[0]);
                        }
                    }

                    yield icon_file.replace_contents_async (
                            icon_data.get_data (),
                            null,
                            false,
                            GLib.FileCreateFlags.REPLACE_DESTINATION,
                            null,
                            null);
                }
                catch (GLib.Error error) {
                    GLib.warning ("Failed to extract %s: %s", filename, error.message);
                    throw error;
                }
            }

            sizes.@foreach (
                (size) => {
                    if (size == "scalable") {
                        return;
                    }

                    foreach (var scale in SCALES)
                    {
                        try {
                            var scale_directory = GLib.File.new_for_path (
                                    GLib.Path.build_filename (icons_theme_path, size + scale));
                            if (!scale_directory.query_exists ()) {
                                scale_directory.make_symbolic_link (size, cancellable);
                            }
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Failed to make symbolic link: %s", error.message);
                        }
                    }
                });
        }

        private void export_menu (string menu_object_path,
                                  string icons_path) throws Sni.IndicatorError
        {
            var root = this.build_menu ();
            var menu_service = new Sni.DBusMenuService (root, this.action_group, icons_path);

            try {
                this.menu_service_id = this.connection.register_object (menu_object_path,
                                                                        menu_service);
                this.menu_service = menu_service;
            }
            catch (GLib.Error error) {
                throw new Sni.IndicatorError.INDICATOR_MENU (error.message);
            }

            this.update_menu_items ();
        }

        private void export_icon (string menu_object_path,
                                  string icons_path) throws Sni.IndicatorError
                                  requires (this.menu_service != null)
        {
            var service = new Sni.StatusNotifierItemDBusService (menu_object_path, icons_path);
            service.received_activation_token.connect ((token) => {
                if (this.menu_service != null) {
                    this.menu_service.activation_token = token;
                }
            });
            service.activated.connect ((token) => {
                var application = Ft.Application.get_default ();
                var window = application.get_window<Ft.Window> ();

                if (window == null || !window.is_active) {
                    this.action_group.activate_action_full ("app.window",
                                                            new GLib.Variant.string ("timer"),
                                                            build_platform_data (token));
                }
                else {
                    window.close_to_background ();
                }
            });
            service.secondary_activated.connect (() => {
                if (this.have_icon_theme || this.have_tooltips)
                {
                    // Mimic behaviour of the primary button
                    if (!this.timer.is_finished ()) {
                        this.action_group?.activate_action ("timer.start-pause-resume", null);
                    }
                    else {
                        this.action_group?.activate_action ("session-manager.advance", null);
                    }
                }
            });
            service.scrolled.connect ((delta) => {
                if (this.have_tooltips)
                {
                    this.notification_manager.inhibit ();
                    Ft.Context.set_event_source ("timer.extend");
                    this.timer.extend (delta > 0 ? Ft.Interval.MINUTE : -Ft.Interval.MINUTE);
                    this.notification_manager.uninhibit (false);
                }
            });

            this.service = service;

            var timestamp = this.timer.get_current_time ();
            this.update_status ();
            this.update_icon (timestamp);
            this.update_tooltip (timestamp);

            try {
                this.service_id = this.connection.register_object (OBJECT_PATH, service);
            }
            catch (GLib.Error error) {
                this.service = null;
                this.invalidate_tooltip ();

                throw new Sni.IndicatorError.INDICATOR (error.message);
            }
        }

        public async void export (GLib.Cancellable cancellable) throws Sni.IndicatorError
        {
            var bus_name = BUS_NAME.printf (Config.APPLICATION_ID);
            var menu_object_path = MENU_OBJECT_PATH.printf (
                    GLib.Application.get_default ().get_dbus_object_path ());
            var icons_path = GLib.Path.build_filename (
                    GLib.Environment.get_user_cache_dir (), Config.PACKAGE_NAME, "icons");

            try {
                yield this.extract_icons (icons_path, cancellable);
                this.export_menu (menu_object_path, icons_path);
                this.export_icon (menu_object_path, icons_path);

                this.connect_signals ();
                this.update_icon_timeout ();

                this.name_owner_id = GLib.Bus.own_name_on_connection (
                        this.connection,
                        bus_name,
                        GLib.BusNameOwnerFlags.REPLACE,
                        null,
                        null);

                yield this.watcher_proxy.register_status_notifier_item (bus_name);
            }
            catch (GLib.Error error) {
                throw new Sni.IndicatorError.INDICATOR (error.message);
            }

            if (!cancellable.is_cancelled ()) {
                this.menu_service.emit_layout_updated ();
                this.service.emit_new_menu ();
            }
        }

        private void update_status ()
        {
            Sni.IndicatorStatus status;

            if (this.session_manager.current_state == Ft.State.STOPPED) {
                status = this.have_passive_status
                        ? Sni.IndicatorStatus.PASSIVE
                        : Sni.IndicatorStatus.ACTIVE;
            }
            else if (this.have_attention_status && (
                    this.timer.is_paused () || this.timer.is_finished ()))
            {
                status = Sni.IndicatorStatus.NEEDS_ATTENTION;
            }
            else {
                status = Sni.IndicatorStatus.ACTIVE;
            }

            this.service.set_status_internal (status, this.service_id != 0);
        }

        private void update_icon (int64 timestamp)
        {
            if (!this.have_icon_theme) {
                return;
            }

            string icon_name;

            var progress = this.timer.calculate_progress (timestamp);
            var progress_uint = (uint) Math.round (progress * ICON_STEPS) * (100U / ICON_STEPS);

            switch (this.session_manager.current_state)
            {
                case Ft.State.STOPPED:
                    icon_name = this.have_passive_status
                            ? "indicator-passive-symbolic"
                            : "indicator-stopped-symbolic";
                    break;

                case Ft.State.POMODORO:
                    icon_name = this.timer.is_paused ()
                            ? "indicator-pomodoro-paused-symbolic"
                            : "indicator-pomodoro-%03u-symbolic".printf (progress_uint);
                    break;

                case Ft.State.BREAK:
                case Ft.State.SHORT_BREAK:
                case Ft.State.LONG_BREAK:
                    icon_name = this.timer.is_paused ()
                            ? "indicator-break-paused-symbolic"
                            : "indicator-break-%03u-symbolic".printf (progress_uint);
                    break;

                default:
                    assert_not_reached ();
            }

            this.service.set_icon_name_internal (icon_name, this.service_id != 0);
        }

        private void update_tooltip (int64 timestamp = Ft.Timestamp.UNDEFINED)
        {
            if (!this.have_tooltips) {
                return;
            }

            if (this.tooltip_title == null)
            {
                uint cycle_number;
                uint cycle_count;

                this.get_cycle_number_count (out cycle_number, out cycle_count);

                this.tooltip_title = format_tooltip_title (
                        this.session_manager.current_state,
                        cycle_number,
                        cycle_count,
                        this.timer.is_finished ());
            }

            var tooltip = Sni.Tooltip () {
                title = this.tooltip_title,
            };

            if (this.have_icon_theme) {
                tooltip.description = this.timer.duration > 0 && !this.timer.is_finished ()
                        ? format_remaining_time (this.timer.calculate_remaining (timestamp))
                        : "";
            }
            else {
                tooltip.description = this.timer.is_running ()
                        ? format_remaining_time (this.timer.calculate_remaining (timestamp))
                        : "";
            }

            this.service.set_tooltip_internal (tooltip, this.service_id != 0);
        }

        private void update_icon_timeout ()
        {
            if (this.update_icon_timeout_id != 0) {
                GLib.Source.remove (this.update_icon_timeout_id);
                this.update_icon_timeout_id = 0;
            }

            this.timer.tick.disconnect (this.update_icon);

            if (!this.timer.is_running () || !this.have_icon_theme) {
                return;
            }

            var interval = Ft.Timestamp.to_milliseconds_uint (this.timer.duration / ICON_STEPS);

            if (interval < 5000 && interval > 0)
            {
                var offset = Ft.Timestamp.to_milliseconds_uint (this.timer.calculate_elapsed ())
                        % interval;
                var deviation = int.min ((int) interval - (int) offset, (int) offset);

                if (deviation < 100) {
                    this.update_icon_timeout_id = GLib.Timeout.add (
                            interval, this.on_update_icon_timeout);
                    GLib.Source.set_name_by_id (this.update_icon_timeout_id,
                                                "Sni.IndicatorController.update_icon");
                }
                else {
                    this.update_icon_timeout_id = GLib.Timeout.add (
                        interval - offset,
                        () => {
                            this.on_update_icon_timeout ();

                            this.update_icon_timeout_id = GLib.Timeout.add (
                                    interval, this.on_update_icon_timeout);
                            GLib.Source.set_name_by_id (this.update_icon_timeout_id,
                                                        "Sni.IndicatorController.update_icon");

                            return GLib.Source.REMOVE;
                        });
                }
            }
            else {
                this.timer.tick.connect (this.update_icon);
            }
        }

        private inline void invalidate_tooltip ()
        {
            this.tooltip_title = null;
        }

        private void update (int64 timestamp)
        {
            if (this.update_idle_id != 0) {
                GLib.Source.remove (this.update_idle_id);
                this.update_idle_id = 0;
            }

            this.update_icon (timestamp);
            this.update_icon_timeout ();
            this.update_status ();
            this.update_menu_items (timestamp);

            this.invalidate_tooltip ();
            this.update_tooltip (timestamp);
        }

        private void queue_update ()
        {
            if (this.update_idle_id != 0) {
                return;
            }

            this.update_idle_id = GLib.Idle.add (
                () => {
                    var timestamp = this.timer.get_current_time (GLib.MainContext.current_source ().get_time ());

                    this.update_idle_id = 0;
                    this.update (timestamp);

                    return GLib.Source.REMOVE;
                });
        }

        private bool on_update_icon_timeout ()
        {
            var timestamp = this.timer.get_current_time (GLib.MainContext.current_source ().get_time ());

            this.update_icon (timestamp);

            return GLib.Source.CONTINUE;
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            this.update (this.timer.get_last_state_changed_time ());
        }

        private void on_session_manager_notify_current_session ()
        {
            this.queue_update ();
        }

        private void on_session_manager_notify_current_state ()
        {
            this.queue_update ();
        }

        private void on_session_manager_notify_has_uniform_breaks ()
        {
            this.queue_update ();
        }

        private void on_application_settings_changed (GLib.Settings settings,
                                                      string        key)
        {
            switch (key)
            {
                case "screen-overlay":
                    this.update_menu_items ();
                    break;

                default:
                    break;
            }
        }

        private void connect_signals ()
        {
            this.timer.state_changed.connect (this.on_timer_state_changed);
            this.timer.tick.connect (this.update_is_completed);

            if (this.have_tooltips) {
                this.timer.tick.connect (this.update_tooltip);
            }

            this.session_manager.notify["current-session"].connect (this.on_session_manager_notify_current_session);
            this.session_manager.notify["current-state"].connect (this.on_session_manager_notify_current_state);
            this.session_manager.notify["has-uniform-breaks"].connect (this.on_session_manager_notify_has_uniform_breaks);

            this.application_settings.changed.connect (this.on_application_settings_changed);
        }

        private void disconnect_signals ()
        {
            if (this.timer != null) {
                this.timer.state_changed.disconnect (this.on_timer_state_changed);
                this.timer.tick.disconnect (this.update_tooltip);
                this.timer.tick.disconnect (this.update_icon);
                this.timer.tick.disconnect (this.update_is_completed);
            }

            if (this.session_manager != null) {
                this.session_manager.notify["current-session"].disconnect (this.on_session_manager_notify_current_session);
                this.session_manager.notify["current-state"].disconnect (this.on_session_manager_notify_current_state);
                this.session_manager.notify["has-uniform-breaks"].disconnect (this.on_session_manager_notify_has_uniform_breaks);
            }

            if (this.application_settings != null) {
                this.application_settings.changed.disconnect (this.on_application_settings_changed);
            }
        }

        /**
         * Unexport services and cleanup.
         */
        public void destroy ()
        {
            this.disconnect_signals ();

            if (this.update_icon_timeout_id != 0) {
                GLib.Source.remove (this.update_icon_timeout_id);
                this.update_icon_timeout_id = 0;
            }

            if (this.update_idle_id != 0) {
                GLib.Source.remove (this.update_idle_id);
                this.update_idle_id = 0;
            }

            if (this.service_id != 0) {
                this.connection.unregister_object (this.service_id);
                this.service_id = 0;
            }

            if (this.menu_service_id != 0) {
                this.connection.unregister_object (this.menu_service_id);
                this.menu_service_id = 0;
            }

            if (this.name_owner_id != 0) {
                GLib.Bus.unown_name (this.name_owner_id);
                this.name_owner_id = 0;
            }
        }
    }


    public class IndicatorProvider : Ft.Provider, Ft.IndicatorProvider
    {
        public bool visible {
            get {
                return this.indicator_controller != null;
            }
        }

        private GLib.Settings?                     settings = null;
        private GLib.DBusConnection?               connection = null;
        private uint                               watcher_id = 0;
        private Sni.StatusNotifierWatcher?         watcher_proxy = null;
        private Sni.IndicatorController?           indicator_controller = null;
        private GLib.Cancellable?                  cancellable = null;

        private void update_available ()
        {
            this.available = this.watcher_proxy != null &&
                             this.watcher_proxy.is_status_notifier_host_registered;
        }

        private async void create_indicator_controller ()
        {
            if (this.indicator_controller != null) {
                return;
            }

            var application = Ft.Application.get_default ();
            application.hold ();

            this.indicator_controller = new Sni.IndicatorController (this.connection,
                                                                     this.watcher_proxy);

            try {
                yield this.indicator_controller.export (this.cancellable);

                this.notify_property ("visible");
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to export SNI: %s", error.message);
                this.destroy_indicator_controller ();
            }

            application.release ();
        }

        private void destroy_indicator_controller ()
        {
            if (this.indicator_controller != null) {
                this.indicator_controller.destroy ();
                this.indicator_controller = null;

                this.notify_property ("visible");
            }
        }

        private void on_properties_changed (GLib.Variant changed_properties,
                                            string[]     invalidated_properties)
        {
            this.update_available ();
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "indicator":
                    if (settings.get_boolean (key)) {
                        this.create_indicator_controller.begin ();
                    }
                    else {
                        var application = Ft.Application.get_default ();
                        application.hold ();

                        this.destroy_indicator_controller ();

                        // Ensure there is a main window when disabling the indicator.
                        // It undoes the close-to-tray behaviour.
                        var main_window = application.get_window<Ft.Window> ();
                        if (main_window == null) {
                            application.show_window ();
                        }

                        application.release ();
                    }

                    break;

                default:
                    break;
            }
        }

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
        {
            if (this.watcher_proxy != null) {
                return;
            }

            try {
                this.watcher_proxy = GLib.Bus.get_proxy_sync<Sni.StatusNotifierWatcher> (
                        GLib.BusType.SESSION,
                        "org.kde.StatusNotifierWatcher",
                        "/StatusNotifierWatcher",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                        this.cancellable);

                var watcher_proxy = (GLib.DBusProxy) this.watcher_proxy;
                watcher_proxy.g_properties_changed.connect (this.on_properties_changed);

                this.update_available ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while initializing StatusNotifierWatcher proxy: %s",
                              error.message);
            }
        }

        private void on_name_vanished (GLib.DBusConnection? connection,
                                       string               name)
        {
            if (this.watcher_proxy != null)
            {
                var watcher_proxy = (GLib.DBusProxy) this.watcher_proxy;
                watcher_proxy.g_properties_changed.disconnect (this.on_properties_changed);

                this.watcher_proxy = null;
            }

            this.available = false;
            this.enabled = false;
        }

        /**
         * Mark provider as `available` when `org.kde.StatusNotifierWatcher` exists
         * and has a host registered.
         */
        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.connection = GLib.Application.get_default ().get_dbus_connection ();

            if (this.connection?.get_unique_name () == null) {
                throw new Sni.IndicatorError.CONNECTION ("No connection");
            }

            if (this.watcher_id == 0) {
                this.watcher_id = GLib.Bus.watch_name (GLib.BusType.SESSION,
                                                       "org.kde.StatusNotifierWatcher",
                                                       GLib.BusNameWatcherFlags.NONE,
                                                       this.on_name_appeared,
                                                       this.on_name_vanished);
            }
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.cancellable = cancellable ?? new GLib.Cancellable ();

            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.sni");
            this.settings.changed.connect (this.on_settings_changed);

            if (this.settings.get_boolean ("indicator")) {
                yield this.create_indicator_controller ();
            }
        }

        public override async void disable () throws GLib.Error
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            if (this.settings != null) {
                this.settings.changed.disconnect (this.on_settings_changed);
                this.settings = null;
            }

            this.destroy_indicator_controller ();
        }

        public override async void uninitialize () throws GLib.Error
        {
            if (this.watcher_id != 0) {
                GLib.Bus.unwatch_name (this.watcher_id);
                this.watcher_id = 0;
            }

            this.connection = null;
        }
    }
}
