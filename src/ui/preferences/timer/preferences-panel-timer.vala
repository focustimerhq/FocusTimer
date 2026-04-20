/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/timer/preferences-panel-timer.ui")]
    public class PreferencesPanelTimer : Ft.PreferencesPanel
    {
        private const uint MIN_TOAST_TIMEOUT = 3;
        private const uint MAX_TOAST_TIMEOUT = 30;

        [GtkChild]
        private unowned Adw.PreferencesPage page;
        [GtkChild]
        private unowned Gtk.Adjustment pomodoro_duration_adjustment;
        [GtkChild]
        private unowned Gtk.Adjustment short_break_duration_adjustment;
        [GtkChild]
        private unowned Gtk.Adjustment long_break_duration_adjustment;
        [GtkChild]
        private unowned Gtk.Adjustment cycles_adjustment;
        [GtkChild]
        private unowned Gtk.Label session_stats_label;
        [GtkChild]
        private unowned Gtk.Label breaks_stats_label;
        [GtkChild]
        private unowned Adw.SwitchRow pause_on_lockscreen_switchrow;
        [GtkChild]
        private unowned Adw.SwitchRow confirm_starting_break_switchrow;
        [GtkChild]
        private unowned Adw.SwitchRow confirm_starting_pomodoro_switchrow;
        [GtkChild]
        private unowned Ft.LogScaleRow long_break_row;

        private GLib.Settings?  settings;
        private ulong           settings_changed_id = 0;
        private Ft.Timer?       timer;
        private ulong           timer_state_changed_id = 0;
        private Ft.IdleMonitor? idle_monitor;
        private Adw.Toast?      apply_changes_toast;

        construct
        {
            this.settings = Ft.get_settings ();
            this.settings.bind ("pomodoro-duration", this.pomodoro_duration_adjustment, "value", GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("short-break-duration", this.short_break_duration_adjustment, "value", GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("long-break-duration", this.long_break_duration_adjustment, "value", GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("cycles", this.cycles_adjustment, "value", GLib.SettingsBindFlags.DEFAULT);

            this.settings.bind ("pause-on-lockscreen",
                                 this.pause_on_lockscreen_switchrow,
                                 "active",
                                 GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("confirm-starting-break",
                                 this.confirm_starting_break_switchrow,
                                 "active",
                                 GLib.SettingsBindFlags.DEFAULT);
            this.settings.bind ("confirm-starting-pomodoro",
                                 this.confirm_starting_pomodoro_switchrow,
                                 "active",
                                 GLib.SettingsBindFlags.DEFAULT);

            this.idle_monitor = new Ft.IdleMonitor ();
            this.idle_monitor.bind_property ("enabled",
                                             this.confirm_starting_pomodoro_switchrow,
                                             "visible",
                                             GLib.BindingFlags.SYNC_CREATE);

            this.settings_changed_id = settings.changed.connect (this.on_settings_changed);

            this.timer = Ft.Timer.get_default ();

            if (this.timer_state_changed_id == 0) {
                this.timer_state_changed_id = this.timer.state_changed.connect (this.on_timer_state_changed);
            }

            this.update_long_break_row_sensitivity ();
            this.update_stats_labels ();
        }

        private void update_long_break_row_sensitivity ()
        {
            this.long_break_row.sensitive = this.cycles_adjustment.value > 1.0;
        }

        private void update_stats_labels ()
        {
            var session_template = Ft.SessionTemplate.with_defaults ();
            var total_duration = Ft.Timestamp.to_seconds_uint (session_template.calculate_total_duration ());
            var break_percentage = (uint) Math.round (session_template.calculate_break_percentage ());

            // translators: time formatted as text: "5 minutes 30 seconds"
            this.session_stats_label.label = _("A single session will take <b>%s</b>.").printf (Ft.format_time (total_duration));
            this.breaks_stats_label.label = _("<b>%u%%</b> of the time will be allocated for breaks.").printf (break_percentage);
        }

        private void apply_changes ()
        {
            var current_time_block = this.timer.user_data as Ft.TimeBlock;

            if (current_time_block != null)
            {
                var duration = current_time_block.state.get_default_duration ();

                current_time_block.set_intended_duration (duration);
                this.timer.duration = duration;
            }
        }

        private uint calculate_apply_changes_toast_timeout (Ft.State changed_state)
        {
            var current_time_block = this.timer.user_data as Ft.TimeBlock;

            if (current_time_block == null ||
                current_time_block.state != changed_state ||
                current_time_block.get_intended_duration () == current_time_block.state.get_default_duration ())
            {
                return 0U;
            }

            if (this.timer.is_paused ()) {
                return MAX_TOAST_TIMEOUT;
            }

            var timeout = Ft.Timestamp.to_seconds_uint (
                    current_time_block.state.get_default_duration () -
                    this.timer.calculate_elapsed ());

            return uint.min (timeout, MAX_TOAST_TIMEOUT);
        }

        private void show_apply_changes_toast (Ft.State changed_state,
                                               uint     timeout)
        {
            var window = this.get_root () as Ft.PreferencesWindow;
            var toast = this.apply_changes_toast;

            if (toast == null)
            {
                toast = new Adw.Toast (changed_state == Ft.State.POMODORO
                                       ? _("Apply changes to ongoing Pomodoro?")
                                       : _("Apply changes to ongoing break?"));
                toast.use_markup = false;
                toast.button_label = _("Apply");
                toast.button_clicked.connect (
                    () => {
                        this.apply_changes_toast = null;
                        this.apply_changes ();
                    }
                );
                toast.dismissed.connect (() => { this.apply_changes_toast = null; });

                this.apply_changes_toast = toast;
            }

            toast.timeout = timeout;

            window?.add_toast (toast);
        }

        private void hide_apply_changes_toast ()
        {
            if (this.apply_changes_toast != null) {
                this.apply_changes_toast.dismiss ();
            }
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            this.hide_apply_changes_toast ();
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            var changed_state = Ft.State.STOPPED;
            var session_manager = Ft.SessionManager.get_default ();

            switch (key)
            {
                case "pomodoro-duration":
                    changed_state = Ft.State.POMODORO;
                    this.update_stats_labels ();
                    break;

                case "short-break-duration":
                    changed_state = settings.get_uint ("cycles") > 1
                        ? Ft.State.SHORT_BREAK
                        : Ft.State.BREAK;
                    this.update_stats_labels ();
                    break;

                case "long-break-duration":
                    changed_state = Ft.State.LONG_BREAK;
                    this.update_stats_labels ();
                    break;

                case "cycles":
                    this.update_long_break_row_sensitivity ();
                    this.update_stats_labels ();
                    break;

                default:
                    break;
            }

            if (session_manager.current_time_block != null &&
                session_manager.current_time_block.state == changed_state)
            {
                var apply_changes_toast_timeout = this.calculate_apply_changes_toast_timeout (changed_state);

                if (apply_changes_toast_timeout >= MIN_TOAST_TIMEOUT) {
                    this.show_apply_changes_toast (changed_state, apply_changes_toast_timeout);
                }
                else {
                    this.hide_apply_changes_toast ();
                }
            }
        }

        public override unowned Adw.PreferencesPage get_preferences_page ()
        {
            return this.page;
        }

        public override void dispose ()
        {
            this.hide_apply_changes_toast ();

            if (this.settings_changed_id != 0) {
                this.settings.disconnect (this.settings_changed_id);
                this.settings_changed_id = 0;
            }

            if (this.timer_state_changed_id != 0) {
                this.timer.disconnect (this.timer_state_changed_id);
                this.timer_state_changed_id = 0;
            }

            this.settings = null;
            this.timer = null;
            this.idle_monitor = null;

            base.dispose ();
        }
    }
}
