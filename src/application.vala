/*
 * Copyright (c) 2013-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    public enum ExitStatus
    {
        UNDEFINED = -1,
        SUCCESS   =  0,
        FAILURE   =  1
    }


    public class Application : Adw.Application
    {
        [Compact]
        private class Option
        {
            public string          long_name;
            public char            short_name;
            public string          description;
            public GLib.OptionArg  arg_type;
            public string?         arg_description;
            public string?         group;
            public string?         action_name;
            public GLib.Variant?   action_parameter;
            public bool            is_exclusive;

            public bool            bool_value;
            public int             int_value;

            public Option (string         long_name,
                           char           short_name,
                           string         description,
                           GLib.OptionArg arg_type,
                           string?        arg_description,
                           string?        action_name = null,
                           GLib.Variant?  action_parameter = null,
                           bool           is_exclusive = true)
            {
                var parts = long_name.split (".", 2);

                if (parts.length > 1) {
                    this.group = parts[0];
                    this.long_name = parts[1];
                }
                else {
                    this.group = "main";
                    this.long_name = long_name;
                }

                this.short_name = short_name;
                this.description = description;
                this.arg_description = arg_description;
                this.arg_type = arg_type;
                this.action_name = action_name;
                this.action_parameter = action_parameter;
                this.is_exclusive = is_exclusive;
            }

            public void* get_arg_data ()
            {
                switch (this.arg_type)
                {
                    case GLib.OptionArg.NONE:
                        return (void*) (&this.bool_value);

                    case GLib.OptionArg.INT:
                        return (void*) (&this.int_value);

                    default:
                        assert_not_reached ();
                }
            }

            public bool is_set ()
            {
                switch (this.arg_type)
                {
                    case GLib.OptionArg.NONE:
                        return this.bool_value;

                    case GLib.OptionArg.INT:
                        return this.int_value > 0;

                    default:
                        assert_not_reached ();
                }
            }

            public GLib.Variant? get_value ()
            {
                switch (this.arg_type)
                {
                    case GLib.OptionArg.NONE:
                        return new GLib.Variant.boolean (true);

                    case GLib.OptionArg.INT:
                        return new GLib.Variant.int32 (this.int_value);

                    default:
                        assert_not_reached ();
                }
            }

            public GLib.Variant? get_action_parameter (GLib.Variant? value)
            {
                return this.arg_type != GLib.OptionArg.NONE
                        ? value
                        : this.action_parameter;
            }
        }

        private static Option[] OPTIONS;

        public Ft.Timer?               timer;
        public Ft.SessionManager?      session_manager;
        public Ft.CapabilityManager?   capability_manager;

        private Ft.KeyboardManager?         keyboard_manager;
        private Ft.StatsManager?            stats_manager;
        private Ft.EventProducer?           event_producer;
        private Ft.EventBus?                event_bus;
        private Ft.Extension?               extension;
        private Ft.JobQueue?                job_queue;
        private Ft.ActionManager?           action_manager;
        private Ft.BackgroundManager?       background_manager;
        private Ft.Logger?                  logger;
        private GLib.Settings?              settings;
        private uint                        save_idle_id = 0;
        private Ft.ApplicationDBusService?  dbus_service;
        private uint                        dbus_service_id;
        private Ft.TimerDBusService?        timer_dbus_service;
        private uint                        timer_dbus_service_id;
        private Ft.SessionDBusService?      session_dbus_service;
        private uint                        session_dbus_service_id;
        private uint                        service_hold_id = 0U;
        private bool                        preferences_requested = false;

        static construct
        {
            OPTIONS = {
                new Option ("timer.start-stop", '\0', N_("Start or Stop"),
                            GLib.OptionArg.NONE, null,
                            "timer.start-stop"),
                new Option ("timer.start-pause-resume", '\0', N_("Start, Pause or Resume"),
                            GLib.OptionArg.NONE, null,
                            "timer.start-pause-resume"),
                new Option ("timer.start-pomodoro", '\0', N_("Start Pomodoro"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.state", new GLib.Variant.string ("pomodoro")),
                new Option ("timer.start-break", '\0', N_("Start break"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.state", new GLib.Variant.string ("break")),
                new Option ("timer.start-short-break", '\0', N_("Start short break"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.state", new GLib.Variant.string ("short-break")),
                new Option ("timer.start-long-break", '\0', N_("Start long break"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.state", new GLib.Variant.string ("long-break")),
                new Option ("timer.start", '\0', N_("Start"),
                            GLib.OptionArg.NONE, null,
                            "timer.start"),
                new Option ("timer.stop", '\0', N_("Stop"),
                            GLib.OptionArg.NONE, null,
                            "timer.reset"),
                new Option ("timer.pause", '\0', N_("Pause"),
                            GLib.OptionArg.NONE, null,
                            "timer.pause"),
                new Option ("timer.resume", '\0', N_("Resume"),
                            GLib.OptionArg.NONE, null,
                            "timer.resume"),
                new Option ("timer.skip", '\0', N_("Skip"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.advance"),
                new Option ("timer.rewind", '\0', N_("Rewind"),
                            GLib.OptionArg.INT, N_("SECONDS"),
                            "timer.rewind-by"),
                new Option ("timer.extend", '\0', N_("Extend current pomodoro or break"),
                            GLib.OptionArg.INT, N_("SECONDS"),
                            "timer.extend-by"),
                new Option ("timer.reset", '\0', N_("Reset"),
                            GLib.OptionArg.NONE, null,
                            "session-manager.reset"),
                new Option ("timer.status", 's', N_("Print timer status"),
                            GLib.OptionArg.NONE, null,
                            null, null, false),
                new Option ("preferences", '\0', N_("Show preferences"),
                            GLib.OptionArg.NONE, null,
                            null, null, false),
                new Option ("quit", 'q', N_("Quit application"),
                            GLib.OptionArg.NONE, null,
                            "app.quit"),
                new Option ("version", 'v', N_("Print version information and exit"),
                            GLib.OptionArg.NONE, null)
            };
        }

        private static GLib.OptionEntry[] get_option_entries (string group)
        {
            GLib.OptionEntry[] result = {};

            foreach (unowned var option in OPTIONS)
            {
                if (option.group == group)
                {
                    result += GLib.OptionEntry () {
                        long_name       = option.long_name,
                        short_name      = option.short_name,
                        description     = option.description,
                        flags           = GLib.OptionFlags.NONE,
                        arg             = option.arg_type,
                        arg_data        = option.get_arg_data (),
                        arg_description = option.arg_description
                    };
                }
            }

            result += GLib.OptionEntry ();  // null entry

            return result;
        }

        construct
        {
            var timer_options = new GLib.OptionGroup (
                    "timer",
                    _("Timer Options:"),
                    _("Show options for controlling the timer"));
            timer_options.add_entries (get_option_entries ("timer"));
            timer_options.set_translation_domain (Config.GETTEXT_PACKAGE);
            this.add_option_group (timer_options);

            this.add_main_option_entries (get_option_entries ("main"));
            this.set_option_context_description (
                    _("Bugs may be reported at: %s").printf (Config.PACKAGE_ISSUE_URL));
        }

        public Application ()
        {
            GLib.Object (
                application_id: Config.APPLICATION_ID,
                flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE,
                resource_base_path: "/io/github/focustimerhq/FocusTimer/"
            );
        }

        public new static unowned Ft.Application get_default ()
        {
            return GLib.Application.get_default () as Ft.Application;
        }

        public unowned Gtk.Window? get_last_focused_window ()
        {
            unowned GLib.List<Gtk.Window> link = this.get_windows ();

            return link != null
                ? link.first ().data
                : null;
        }

        public unowned T? get_window<T> ()
        {
            unowned GLib.List<Gtk.Window> link = this.get_windows ();

            var window_type = typeof (T);

            while (link != null)
            {
                if (link.data.get_type () == window_type) {
                    return link.data;
                }

                link = link.next;
            }

            return null;
        }

        private void schedule_save ()
        {
            if (this.save_idle_id != 0) {
                return;
            }

            this.save_idle_id = GLib.Idle.add (() => {
                this.save_idle_id = 0;
                this.session_manager.save.begin ((obj, res) => {
                    this.session_manager.save.end (res);
                });

                return GLib.Source.REMOVE;
            });
            GLib.Source.set_name_by_id (this.save_idle_id, "Ft.Application.schedule_save");
        }

        public void show_window (Ft.WindowView view = Ft.WindowView.DEFAULT)
        {
            var window = this.get_window<Ft.Window> ();

            if (window == null)
            {
                window = new Ft.Window ();
                this.add_window (window);

                if (this.application_id.has_suffix ("Devel")) {
                    window.add_css_class ("devel");
                }
            }

            if (view != Ft.WindowView.DEFAULT) {
                window.view = view;
            }

            window.present ();
        }

        public void show_preferences (string panel_name = "")
        {
            var preferences_window = this.get_window<Ft.PreferencesWindow> ();

            if (preferences_window == null)
            {
                preferences_window = new Ft.PreferencesWindow ();
                this.add_window (preferences_window);
            }

            if (panel_name != "") {
                preferences_window.select_panel (panel_name);
            }

            preferences_window.present ();
        }

        private void show_about_dialog ()
        {
            var window = this.get_window<Ft.Window> ();
            var about_dialog = this.get_window<Adw.AboutDialog> ();

            if (about_dialog == null) {
                about_dialog = Ft.create_about_dialog ();
            }

            about_dialog.present (window);
        }

        private void activate_prefixed_action (string        action_name,
                                               GLib.Variant? parameter)
        {
            GLib.ActionGroup action_group;

            var parts = action_name.split (".", 2);

            if (parts.length < 2) {
                this.activate_action (action_name, parameter);
                return;
            }

            switch (parts[0])
            {
                case "app":
                    action_group = (GLib.ActionGroup) this;
                    break;

                case "timer":
                    action_group = new Ft.TimerActionGroup ();
                    break;

                case "session-manager":
                    action_group = new Ft.SessionManagerActionGroup ();
                    break;

                default:
                    GLib.warning ("Unhandled action '%s'", action_name);
                    return;
            }

            action_group.activate_action (parts[1], parameter);
        }

        private void activate_window (GLib.SimpleAction action,
                                      GLib.Variant?     parameter)
        {
            var view = Ft.WindowView.from_string (parameter.get_string ());

            this.show_window (view);
        }

        private void activate_toggle_window (GLib.SimpleAction action,
                                             GLib.Variant?     parameter)
        {
            var window = this.get_window<Ft.Window> ();

            if (window == null || !window.is_active) {
                this.show_window (Ft.WindowView.TIMER);
            }
            else {
                window.close_to_background ();
            }
        }

        private void activate_preferences (GLib.SimpleAction action,
                                           GLib.Variant?     parameter)
        {
            this.show_preferences ();
        }

        private void activate_log (GLib.SimpleAction action,
                                   GLib.Variant?     parameter)
        {
            var log_window = this.get_window<Ft.LogWindow> ();

            if (log_window == null) {
                log_window = new Ft.LogWindow ();
                this.add_window (log_window);
            }

            if (parameter != null) {
                log_window.select ((ulong) parameter.get_uint64 ());
            }

            log_window.present ();
        }

        private void activate_about (GLib.SimpleAction action,
                                     GLib.Variant?     parameter)
        {
            this.show_about_dialog ();
        }

        private void activate_screen_overlay (GLib.SimpleAction action,
                                              GLib.Variant?     parameter)
        {
            this.capability_manager.activate ("notifications");
        }

        private void activate_visit_website (GLib.SimpleAction action,
                                             GLib.Variant?     parameter)
        {
            try {
                string[] spawn_args = { "xdg-open", Config.PACKAGE_WEBSITE };
                string[] spawn_env = GLib.Environ.get ();

                GLib.Process.spawn_async (null,
                                          spawn_args,
                                          spawn_env,
                                          GLib.SpawnFlags.SEARCH_PATH,
                                          null,
                                          null);
            }
            catch (GLib.SpawnError error) {
                GLib.warning ("Failed to spawn process: %s", error.message);
            }
        }

        private void activate_report_issue (GLib.SimpleAction action,
                                            GLib.Variant?     parameter)
        {
            try {
                string[] spawn_args = { "xdg-open", Config.PACKAGE_ISSUE_URL };
                string[] spawn_env = GLib.Environ.get ();

                GLib.Process.spawn_async (null,
                                          spawn_args,
                                          spawn_env,
                                          GLib.SpawnFlags.SEARCH_PATH,
                                          null,
                                          null);
            }
            catch (GLib.SpawnError error) {
                GLib.warning ("Failed to spawn process: %s", error.message);
            }
        }

        private void activate_quit (GLib.SimpleAction action,
                                    GLib.Variant?     parameter)
        {
            this.quit ();
        }

        private void activate_advance (GLib.SimpleAction action,
                                       GLib.Variant?     parameter)
        {
            this.activate_prefixed_action ("session-manager.advance", parameter);
        }

        private void activate_advance_to_state (GLib.SimpleAction action,
                                                GLib.Variant?     parameter)
        {
            this.activate_prefixed_action ("session-manager.state", parameter);
        }

        private void activate_extend (GLib.SimpleAction action,
                                      GLib.Variant?     parameter)
        {
            this.activate_prefixed_action ("timer.extend-by", parameter);
        }

        private void setup_resources ()
        {
            var display = Gdk.Display.get_default ();

            var icon_theme = Gtk.IconTheme.get_for_display (display);
            icon_theme.add_resource_path ("/io/github/focustimerhq/FocusTimer/icons");
        }

        private void setup_capabilities ()
        {
            this.capability_manager = new Ft.CapabilityManager ();
            this.capability_manager.register (new Ft.NotificationsCapability ());
            this.capability_manager.register (new Ft.GlobalShortcutsCapability ());
            this.capability_manager.register (new Ft.SoundsCapability ());

            this.hold ();

            var idle_id = GLib.Idle.add (() => {
                this.capability_manager.enable ("notifications");
                this.capability_manager.enable ("global-shortcuts");

                if (this.settings.get_boolean ("sounds")) {
                    this.capability_manager.enable ("sounds");
                }

                this.release ();

                return GLib.Source.REMOVE;
            });
            GLib.Source.set_name_by_id (idle_id, "Ft.Application.setup_capabilities");
        }

        private void setup_database ()
        {
            Ft.Database.open ();
        }

        private void setup_actions ()
        {
            GLib.SimpleAction action;

            action = new GLib.SimpleAction ("window", GLib.VariantType.STRING);
            action.activate.connect (this.activate_window);
            this.add_action (action);

            action = new GLib.SimpleAction ("toggle-window", null);
            action.activate.connect (this.activate_toggle_window);
            this.add_action (action);

            action = new GLib.SimpleAction ("preferences", null);
            action.activate.connect (this.activate_preferences);
            this.add_action (action);

            action = new GLib.SimpleAction ("log", GLib.VariantType.UINT64);
            action.activate.connect (this.activate_log);
            this.add_action (action);

            action = new GLib.SimpleAction ("screen-overlay", null);
            action.activate.connect (this.activate_screen_overlay);
            this.add_action (action);

            action = new GLib.SimpleAction ("visit-website", null);
            action.activate.connect (this.activate_visit_website);
            this.add_action (action);

            action = new GLib.SimpleAction ("report-issue", null);
            action.activate.connect (this.activate_report_issue);
            this.add_action (action);

            action = new GLib.SimpleAction ("about", null);
            action.activate.connect (this.activate_about);
            this.add_action (action);

            action = new GLib.SimpleAction ("quit", null);
            action.activate.connect (this.activate_quit);
            this.add_action (action);

            // Include timer and session-manager actions under the "app" namespace
            // for use in notifications.
            action = new GLib.SimpleAction ("advance", null);
            action.activate.connect (this.activate_advance);
            this.add_action (action);

            action = new GLib.SimpleAction ("advance-to-state", GLib.VariantType.STRING);
            action.activate.connect (this.activate_advance_to_state);
            this.add_action (action);

            action = new GLib.SimpleAction ("extend", GLib.VariantType.INT32);
            action.activate.connect (this.activate_extend);
            this.add_action (action);

            this.set_accels_for_action ("app.preferences", {"<Control>comma"});
            this.set_accels_for_action ("app.log", {"<Control>l"});
            this.set_accels_for_action ("app.quit", {"<Control>q"});
            this.set_accels_for_action ("window.close", {"<Control>w"});
            this.set_accels_for_action ("win.toggle-compact-size", {"F9"});

            this.keyboard_manager = new Ft.KeyboardManager ();
            this.keyboard_manager.add_shortcut ("timer.start-stop",
                                                _("Start or Stop"),
                                                "<Control><Alt>p");
            this.keyboard_manager.add_shortcut ("timer.start-pause-resume",
                                                _("Start, Pause or Resume"));
            this.keyboard_manager.add_shortcut ("timer.start",
                                                _("Start"));
            this.keyboard_manager.add_shortcut ("timer.reset",
                                                _("Stop"));
            this.keyboard_manager.add_shortcut ("timer.pause",
                                                _("Pause"));
            this.keyboard_manager.add_shortcut ("timer.resume",
                                                _("Resume"));
            this.keyboard_manager.add_shortcut ("session-manager.advance",
                                                _("Skip"));
            this.keyboard_manager.add_shortcut ("timer.rewind",
                                                _("Rewind"));
            this.keyboard_manager.add_shortcut ("app.toggle-window",
                                                _("Bring to Focus"),
                                                "<Control><Alt><Shift>p");
            this.keyboard_manager.shortcut_activated.connect (this.on_shortcut_activated);
        }

        private void setup_extension ()
        {
            this.extension = new Ft.Extension ();

            // TODO
            // this.capabilities.register_many (this.extension.capabilities);
        }

        private void update_color_scheme ()
        {
            var style_manager = Adw.StyleManager.get_default ();

            if (this.settings.get_boolean ("dark-theme")) {
                style_manager.set_color_scheme (Adw.ColorScheme.FORCE_DARK);
            }
            else {
                style_manager.set_color_scheme (Adw.ColorScheme.DEFAULT);
            }
        }

        /**
         * Emitted on the primary instance immediately after registration.
         */
        public override void startup ()
        {
            var dbus_connection = this.get_dbus_connection ();
            var dbus_object_path = this.get_dbus_object_path ();
            var main_context = GLib.MainContext.@default ();
            var ready = false;

            this.hold ();
            this.mark_busy ();

            base.startup ();

            this.settings           = Ft.get_settings ();
            this.session_manager    = Ft.SessionManager.get_default ();
            this.timer              = this.session_manager.timer;
            this.stats_manager      = new Ft.StatsManager ();
            this.event_producer     = new Ft.EventProducer ();
            this.event_bus          = this.event_producer.bus;
            this.job_queue          = new Ft.JobQueue ();
            this.logger             = new Ft.Logger ();
            this.background_manager = new Ft.BackgroundManager ();

#if ENABLE_AUTOMATION
            this.action_manager = new Ft.ActionManager ();
#endif

            this.setup_resources ();
            this.setup_database ();
            this.setup_capabilities ();
            this.setup_extension ();
            this.setup_actions ();
            this.update_color_scheme ();

            this.settings.changed.connect (this.on_settings_changed);
            this.event_bus.event.connect (this.on_event);

            this.session_manager.restore.begin (
                Ft.Timestamp.UNDEFINED,
                (obj, res) => {
                    this.session_manager.restore.end (res);
                    this.session_manager.ensure_session ();

                    this.session_manager.enter_session.connect (this.on_enter_session);
                    this.session_manager.leave_session.connect (this.on_leave_session);
                    this.session_manager.advanced.connect (this.on_advanced);

                    this.on_enter_session (this.session_manager.current_session);

                    ready = true;
                    main_context.wakeup ();
                });

            if (this.timer_dbus_service == null)
            {
                try {
                    this.timer_dbus_service = new Ft.TimerDBusService (
                            dbus_connection,
                            dbus_object_path,
                            this.timer,
                            this.session_manager);
                    this.timer_dbus_service_id = dbus_connection.register_object (
                            dbus_object_path,
                            this.timer_dbus_service);
                }
                catch (GLib.IOError error) {
                    GLib.warning ("Error while initializing timer dbus service: %s",
                                  error.message);
                    this.timer_dbus_service = null;
                }
            }

            if (this.session_dbus_service == null)
            {
                try {
                    this.session_dbus_service = new Ft.SessionDBusService (
                            dbus_connection,
                            dbus_object_path,
                            this.session_manager);
                    this.session_dbus_service_id = dbus_connection.register_object (
                            dbus_object_path,
                            this.session_dbus_service);
                }
                catch (GLib.IOError error) {
                    GLib.warning ("Error while initializing session dbus service: %s",
                                  error.message);
                    this.session_dbus_service = null;
                }
            }

            if (GLib.ApplicationFlags.IS_SERVICE in this.flags)
            {
                this.background_manager.hold.begin (
                    "",
                    (obj, res) => {
                        this.service_hold_id = this.background_manager.hold.end (res);
                    });
            }

            while (!ready) {
                main_context.iteration (true);
            }

            this.unmark_busy ();
            this.release ();
        }

        private void print_timer_status (GLib.ApplicationCommandLine command_line)
        {
            var timestamp = this.timer.get_current_time ();
            var last_state_changed_time = this.timer.get_last_state_changed_time ();

            if (timestamp - last_state_changed_time < Ft.Interval.SECOND) {
                timestamp = last_state_changed_time;
            }

            var message = new GLib.StringBuilder ();
            var glyph = " ";

            if (this.timer.is_running ()) {
                glyph = "▶";
            }
            else if (this.timer.is_paused ()) {
                glyph = "⏸";
            }
            else if (!this.timer.is_started ()) {
                glyph = "⏹";
            }

            message.append_printf (" %s %s\n",
                                   glyph,
                                   this.session_manager.current_state.get_label ());

            if (this.session_manager.current_state != Ft.State.STOPPED)
            {
                var seconds_uint = (uint) Ft.Timestamp.to_seconds_uint (
                        this.timer.calculate_remaining (timestamp));
                message.append_printf (
                        "   %s\n",
                        _("%s remaining").printf (Ft.format_time (seconds_uint)));
            }

            command_line.print_literal (message.str);
        }

        private void print_version ()
        {
            stdout.printf ("%s %s\n",
                           GLib.Environment.get_application_name (),
                           Config.PACKAGE_VERSION);
        }

        /**
         * GLib only fills `options` for entries with empty `arg_data`, and empty `arg_data` aren't
         * supported for option groups. Therefore, we fill `options` manually before it's passed
         * to the remote instance.
         */
        public override int handle_local_options (GLib.VariantDict options)
        {
            var exclusive_options_count = 0U;
            var version_requested = false;

            foreach (unowned var option in OPTIONS)
            {
                if (option.is_set ())
                {
                    if (option.is_exclusive) {
                        exclusive_options_count++;
                    }

                    if (option.long_name == "version") {
                        version_requested = true;
                        continue;
                    }

                    options.insert_value (option.long_name, option.get_value ());
                }
            }

            if (exclusive_options_count > 1U) {
                stderr.printf (
                        "%s\n",
                        _("Invalid use. Pass one flag for controlling the timer at a time."));
                return ExitStatus.FAILURE;
            }

            if (version_requested) {
                this.print_version ();
                return Ft.ExitStatus.SUCCESS;
            }

            return Ft.ExitStatus.UNDEFINED;
        }

        public override int command_line (GLib.ApplicationCommandLine command_line)
        {
            var options = command_line.get_options_dict ();
            var exit_status = ExitStatus.UNDEFINED;

            foreach (unowned var option in OPTIONS)
            {
                var value = options.lookup_value (option.long_name, null);

                if (value == null) {
                    continue;
                }

                if (option.action_name != null) {
                    this.activate_prefixed_action (option.action_name,
                                                   option.get_action_parameter (value));
                    exit_status = Ft.ExitStatus.SUCCESS;
                }
                else if (option.long_name == "status") {
                    this.print_timer_status (command_line);
                    exit_status = Ft.ExitStatus.SUCCESS;
                }
            }

            if (exit_status != ExitStatus.UNDEFINED) {
                return exit_status;
            }

            this.preferences_requested = options.contains ("preferences");
            this.activate ();
            this.preferences_requested = false;

            return Ft.ExitStatus.SUCCESS;
        }

        public override void activate ()
        {
            if (this.preferences_requested) {
                this.show_preferences ();
            }
            else {
                this.show_window ();
            }
        }

        /* Save the state before exit.
         *
         * Emitted only on the registered primary instance immediately after
         * the main loop terminates.
         */
        public override void shutdown ()
        {
            if (this.service_hold_id != 0U) {
                this.background_manager.release (this.service_hold_id);
                this.service_hold_id = 0U;
            }

            if (this.save_idle_id != 0) {
                GLib.Source.remove (this.save_idle_id);
                this.save_idle_id = 0;
            }

            this.settings.changed.disconnect (this.on_settings_changed);
            this.event_bus.event.disconnect (this.on_event);
            this.keyboard_manager.shortcut_activated.disconnect (this.on_shortcut_activated);

            base.shutdown ();

            // Stop emitting new events
            this.event_producer.destroy ();
            this.event_bus.destroy ();
            this.action_manager?.destroy ();
            this.capability_manager.destroy ();
            this.background_manager.destroy ();
            this.session_manager.enter_session.disconnect (this.on_enter_session);
            this.session_manager.leave_session.disconnect (this.on_leave_session);
            this.session_manager.advanced.disconnect (this.on_advanced);

            if (this.session_manager.current_session != null) {
                this.session_manager.current_session.changed.disconnect (
                        this.on_current_session_changed);
            }

            // Pause the timer before saving the session
            this.timer.pause ();

            // Wait until all async jobs are completed
            var main_context = GLib.MainContext.@default ();
            var remaining = 2;

            this.job_queue.wait.begin (
                (obj, res) => {
                    this.job_queue.wait.end (res);
                    remaining--;
                });

            this.session_manager.save.begin (
                (obj, res) => {
                    this.session_manager.save.end (res);
                    remaining--;
                });

            while (remaining > 0 && main_context.iteration (true));

            // Cleanup
            Ft.Database.close ();
            Ft.SessionManager.set_default (null);
            Ft.Timer.set_default (null);

            this.event_producer = null;
            this.event_bus = null;
            this.extension = null;
            this.job_queue = null;
            this.action_manager = null;
            this.logger = null;
            this.background_manager = null;
            this.keyboard_manager = null;
            this.capability_manager = null;
            this.stats_manager = null;
            this.session_manager = null;
            this.timer = null;
            this.settings = null;
        }

        /**
         * Register main D-Bus service for the app.
         */
        public override bool dbus_register (GLib.DBusConnection connection,
                                            string              object_path)
                                            throws GLib.Error
        {
            if (!base.dbus_register (connection, object_path)) {
                return false;
            }

            if (this.dbus_service == null)
            {
                try {
                    this.dbus_service = new Ft.ApplicationDBusService (this);
                    this.dbus_service_id = connection.register_object (object_path, dbus_service);
                }
                catch (GLib.IOError error) {
                    GLib.warning ("Error while initializing application dbus service: %s",
                                  error.message);
                    this.dbus_service = null;
                    return false;
                }
            }

            return true;
        }

        public override void dbus_unregister (GLib.DBusConnection connection,
                                              string              object_path)
        {
            if (this.timer_dbus_service != null) {
                connection.unregister_object (this.timer_dbus_service_id);
                this.timer_dbus_service = null;
                this.timer_dbus_service_id = 0U;
            }

            if (this.session_dbus_service != null) {
                connection.unregister_object (this.session_dbus_service_id);
                this.session_dbus_service = null;
                this.session_dbus_service_id = 0U;
            }

            if (this.dbus_service != null) {
                connection.unregister_object (this.dbus_service_id);
                this.dbus_service = null;
                this.dbus_service_id = 0U;
            }

            base.dbus_unregister (connection, object_path);
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "dark-theme":
                    this.update_color_scheme ();
                    break;

                case "sounds":
                    if (settings.get_boolean (key)) {
                        this.capability_manager.enable ("sounds");
                    }
                    else {
                        this.capability_manager.disable ("sounds");
                    }
                    break;
            }
        }

        private void on_current_session_changed ()
        {
            this.schedule_save ();
        }

        private void on_enter_session (Ft.Session session)
        {
            session.changed.connect (this.on_current_session_changed);
        }

        private void on_leave_session (Ft.Session session)
        {
            session.changed.disconnect (this.on_current_session_changed);

            Ft.Database.schedule_backup ();
        }

        private void on_advanced (Ft.Session?   current_session,
                                  Ft.TimeBlock? current_time_block,
                                  Ft.Session?   previous_session,
                                  Ft.TimeBlock? previous_time_block)
        {
            this.schedule_save ();
        }

        private void on_event (Ft.Event event)
        {
            this.logger.log_event (event);
        }

        private void on_shortcut_activated (string shortcut_name)
        {
            this.activate_prefixed_action (shortcut_name, null);
        }

        public override void dispose ()
        {
            assert (this.save_idle_id == 0);

            base.dispose ();
        }
    }
}
