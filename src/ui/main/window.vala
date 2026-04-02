/*
 * Copyright (c) 2016-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    public enum WindowSize
    {
        NORMAL = 0,
        COMPACT = 1;

        public static WindowSize from_string (string? name)
        {
            switch (name)
            {
                case "compact":
                    return WindowSize.COMPACT;

                default:
                    return WindowSize.NORMAL;
            }
        }

        public string to_string ()
        {
            switch (this)
            {
                case NORMAL:
                    return "normal";

                case COMPACT:
                    return "compact";

                default:
                    assert_not_reached ();
            }
        }
    }

    public enum WindowView
    {
        DEFAULT = 0,
        TIMER = 1,
        STATS = 2;

        public static WindowView from_string (string? view_name)
        {
            switch (view_name)
            {
                case "timer":
                    return WindowView.TIMER;

                case "stats":
                    return WindowView.STATS;

                default:
                    return WindowView.DEFAULT;
            }
        }

        public string to_string ()
        {
            switch (this)
            {
                case TIMER:
                    return "timer";

                case STATS:
                    return "stats";

                case DEFAULT:
                    return "";

                default:
                    assert_not_reached ();
            }
        }
    }


    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/main/window.ui")]
    public class Window : Adw.ApplicationWindow, Gtk.Buildable
    {
        private const uint TOAST_DISMISS_TIMEOUT = 3;


        [CCode (notify = false)]
        public Ft.WindowSize size {
            get {
                return this._size;
            }
            set {
                if (this._size == value) {
                    return;
                }

                this._size = value;

                this.size_stack.visible_child_name = value.to_string ();
                this.notify_property ("size");
            }
        }

        [CCode (notify = false)]
        public Ft.WindowView view {
            get {
                return this._view;
            }
            set {
                if (this._view == value) {
                    return;
                }

                this._view = value;

                var resolved_view = value;
                if (resolved_view == Ft.WindowView.DEFAULT) {
                    resolved_view = this.get_default_view ();
                }

                this.view_stack.visible_child_name = resolved_view.to_string ();
                this.notify_property ("view");
            }
        }

        [GtkChild]
        private unowned Ft.SizeStack size_stack;
        [GtkChild]
        private unowned Adw.ViewStack view_stack;
        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild]
        private unowned Ft.TimerView timer_view;

        private Ft.WindowSize           _size = Ft.WindowSize.NORMAL;
        private Ft.WindowView           _view = Ft.WindowView.DEFAULT;
        private Ft.SessionManager?      session_manager = null;
        private Ft.Timer?               timer = null;
        private Ft.BackgroundManager?   background_manager = null;
        private Peas.ExtensionSet?      extensions = null;
        private static uint             background_hold_id = 0U;

        construct
        {
            var settings = Ft.get_settings ();

            this.session_manager = Ft.SessionManager.get_default ();
            this.timer           = session_manager.timer;
            this.timer.state_changed.connect (() => {
                this.update_timer_indicator ();
            });

            this.insert_action_group ("session-manager", new Ft.SessionManagerActionGroup ());
            this.insert_action_group ("timer", new Ft.TimerActionGroup ());

            if (settings.get_boolean ("prefer-compact-size")) {
                this.size = Ft.WindowSize.COMPACT;
            }

            this.background_manager = new Ft.BackgroundManager ();

            this.notify["is-active"].connect (this.on_notify_is_active);
            this.notify["maximized"].connect (this.on_notify_maximized);

            this.update_title ();
            this.update_timer_indicator ();

            var window_value = GLib.Value (GLib.Type.OBJECT);
            window_value.set_object (this);

            this.extensions = new Peas.ExtensionSet.with_properties (
                    Peas.Engine.get_default (),
                    typeof (Ft.WindowExtension), {"window"}, {window_value});
        }

        private void update_title ()
        {
            var page = this._size == Ft.WindowSize.NORMAL
                ? this.view_stack.get_page (this.view_stack.visible_child)
                : null;

            this.title = page != null ? page.title : _("Pomodoro");
        }

        private void update_timer_indicator ()
        {
            var timer_page = this.view_stack.get_page (this.timer_view);
            var timer      = Ft.Timer.get_default ();

            timer_page.needs_attention = this.view_stack.visible_child != timer_page.child &&
                                         timer.is_started ();
        }

        public Ft.WindowView get_default_view ()
                                               ensures (result != Ft.WindowView.DEFAULT)
        {
            return Ft.WindowView.TIMER;
        }

        private async void close_to_background_internal ()
        {
            var window_id = yield Ft.get_window_identifier (this);

            Ft.Window.background_hold_id = yield this.background_manager.hold (window_id);

            if (Ft.Window.background_hold_id != 0U) {
                this.close ();
            }
            else {
                this.minimize ();  // fallback
            }
        }

        public void close_to_background ()
        {
            this.close_to_background_internal.begin ();
        }

        /**
         *  Keep the toast until window is focused.
         */
        private void dismiss_toast_once_focused (Adw.Toast toast)
        {
            toast.timeout = 0;

            var state_flags_changed_id = this.state_flags_changed.connect (
                (previous_state_flags) => {
                    var is_backdrop = Gtk.StateFlags.BACKDROP in this.get_state_flags ();

                    if (!is_backdrop) {
                        toast.timeout = TOAST_DISMISS_TIMEOUT;
                        this.toast_overlay.add_toast (toast);  // necessary for updating the timeout
                    }
                }
            );

            toast.dismissed.connect (() => {
                if (state_flags_changed_id != 0) {
                    this.disconnect (state_flags_changed_id);
                    state_flags_changed_id = 0;
                }
            });
        }

        /**
         * Monitor user activity and dismiss notification once user becomes active.
         */
        private void dismiss_toast_once_user_becomes_active (Adw.Toast toast)
        {
            // toast.timeout = 0;

            // TODO
        }

        public void add_toast (owned Adw.Toast toast)
        {
            if (toast.timeout != 0 && this._size == Ft.WindowSize.NORMAL)
            {
                if (Gtk.StateFlags.BACKDROP in this.get_state_flags ()) {
                    this.dismiss_toast_once_focused (toast);
                }
                else {
                    this.dismiss_toast_once_user_becomes_active (toast);
                }
            }

            this.toast_overlay.add_toast (toast);
        }

        private void show_close_confirmation_dialog ()
        {
            unowned var self = this;

            var dialog = new Adw.AlertDialog (
                _("Keep timer running?"),
                _("You can keep it running in the background — notifications and keyboard shortcuts will still work.")
            );
            dialog.prefer_wide_layout = true;

            dialog.add_response ("quit", _("Quit"));
            dialog.set_response_appearance ("quit", Adw.ResponseAppearance.DEFAULT);

            dialog.add_response ("run-in-background", _("Run in background"));
            dialog.set_response_appearance ("run-in-background", Adw.ResponseAppearance.SUGGESTED);

            dialog.set_default_response ("run-in-background");
            dialog.set_close_response ("cancel");
            dialog.response.connect (
                (response) => {
                    switch (response)
                    {
                        case "run-in-background":
                            self.close_to_background ();
                            break;

                        case "quit":
                            self.application.quit ();
                            break;

                        case "cancel":
                            dialog.close ();
                            break;

                        default:
                            assert_not_reached ();
                    }
                });

            dialog.present (self);
        }

        [GtkCallback]
        private void on_size_stack_visible_child_notify (GLib.Object    object,
                                                         GLib.ParamSpec pspec)
        {
            this.size = Ft.WindowSize.from_string (this.size_stack.visible_child_name);
        }

        [GtkCallback]
        private void on_view_stack_visible_child_notify (GLib.Object    object,
                                                         GLib.ParamSpec pspec)
        {
            var view = Ft.WindowView.from_string (this.view_stack.visible_child_name);

            this._view = this._view == Ft.WindowView.DEFAULT && this.get_default_view () == view
                ? Ft.WindowView.DEFAULT
                : view;

            this.update_title ();
            this.update_timer_indicator ();
        }

        [GtkCallback]
        private void on_gesture_click_pressed (Gtk.GestureClick gesture,
                                               int              n_press,
                                               double           x,
                                               double           y)
        {
            var toggle_compact_size_action = this.lookup_action ("toggle-compact-size");

            if (toggle_compact_size_action.enabled &&
                gesture.get_current_button () == Gdk.BUTTON_PRIMARY &&
                n_press == 2)
            {
                toggle_compact_size_action.activate (null);
                gesture.set_state (Gtk.EventSequenceState.CLAIMED);
            }
        }

        [GtkCallback]
        private bool on_close_request ()
        {
            if (this.background_manager.active) {
                return false;
            }

            if (this.timer.is_running ())
            {
                this.show_close_confirmation_dialog ();

                return true;
            }
            else {
                this.application.quit ();

                return false;
            }
        }

        private void on_notify_is_active (GLib.Object    object,
                                          GLib.ParamSpec pspec)
        {
            if (this.is_active && Ft.Window.background_hold_id != 0U) {
                this.background_manager.release (Ft.Window.background_hold_id);
                Ft.Window.background_hold_id = 0U;
            }
        }

        private void on_notify_maximized (GLib.Object    object,
                                          GLib.ParamSpec pspec)
        {
            var can_change_size = !this.maximized;

            var compact_size_action = (GLib.SimpleAction) this.lookup_action ("compact-size");
            compact_size_action.set_enabled (can_change_size);

            var toggle_compact_size_action =
                    (GLib.SimpleAction) this.lookup_action ("toggle-compact-size");
            toggle_compact_size_action.set_enabled (can_change_size);
        }

        private void on_compact_size_activate (GLib.SimpleAction action,
                                               GLib.Variant?     parameter)
        {
            this.size = Ft.WindowSize.COMPACT;
        }

        private void on_normal_size_activate (GLib.SimpleAction action,
                                              GLib.Variant?     parameter)
        {
            this.size = Ft.WindowSize.NORMAL;
            this.view = Ft.WindowView.TIMER;
        }

        private void on_toggle_compact_size_activate (GLib.SimpleAction action,
                                                      GLib.Variant?     parameter)
        {
            if (this.size == Ft.WindowSize.NORMAL) {
                this.lookup_action ("compact-size").activate (null);
            }
            else {
                this.lookup_action ("normal-size").activate (null);
            }
        }

        private void setup_actions ()
        {
            var action_map = (GLib.ActionMap) this;

            var compact_size_action = new GLib.SimpleAction ("compact-size", null);
            compact_size_action.activate.connect (this.on_compact_size_activate);
            action_map.add_action (compact_size_action);

            var normal_size_action = new GLib.SimpleAction ("normal-size", null);
            normal_size_action.activate.connect (this.on_normal_size_activate);
            action_map.add_action (normal_size_action);

            var toggle_compact_size_action = new GLib.SimpleAction ("toggle-compact-size", null);
            toggle_compact_size_action.activate.connect (this.on_toggle_compact_size_activate);
            action_map.add_action (toggle_compact_size_action);
        }

        public void parser_finished (Gtk.Builder builder)
        {
            this.setup_actions ();
        }

        public override void dispose ()
        {
            this.extensions = null;
            this.background_manager = null;

            base.dispose ();
        }
    }
}
