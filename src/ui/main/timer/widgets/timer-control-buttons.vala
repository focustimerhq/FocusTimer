/*
 * Copyright (c) 2022-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


namespace Ft
{
    private inline Gtk.StackPage? get_stack_page_by_name (Gtk.Stack stack,
                                                          string name)
    {
        return stack.get_page (stack.get_child_by_name (name));
    }


    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/main/timer/widgets/timer-control-buttons.ui")]
    public sealed class TimerControlButtons : Gtk.Box, Gtk.Buildable
    {
        private const uint FADE_IN_DURATION = 500;
        private const uint FADE_OUT_DURATION = 500;

        public bool has_suggested_action {
            get {
                return this.center_button.has_css_class ("suggested-action");
            }
            set {
                if (value) {
                    this.center_button.add_css_class ("suggested-action");
                }
                else {
                    this.center_button.remove_css_class ("suggested-action");
                }
            }
        }

        public bool circular {
            get {
                return this.center_button.has_css_class ("circular");
            }
            set {
                if (value) {
                    this.left_button.add_css_class ("circular");
                    this.center_button.add_css_class ("circular");
                    this.right_button.add_css_class ("circular");
                }
                else {
                    this.left_button.remove_css_class ("circular");
                    this.center_button.remove_css_class ("circular");
                    this.right_button.remove_css_class ("circular");
                }
            }
        }

        [GtkChild]
        private unowned Gtk.Button left_button;
        [GtkChild]
        private unowned Gtk.Button center_button;
        [GtkChild]
        private unowned Gtk.Button right_button;
        [GtkChild]
        private unowned Gtk.Stack left_image_stack;
        [GtkChild]
        private unowned Gtk.Stack center_image_stack;
        [GtkChild]
        private unowned Gtk.Stack right_image_stack;
        [GtkChild]
        private unowned Gtk.Image skip_image;

        private Ft.SessionManager?            session_manager;
        private Ft.Timer?                     timer;
        private ulong                         timer_state_changed_id = 0;
        private ulong                         session_manager_notify_current_session_id = 0;
        private GLib.List<Adw.TimedAnimation> animations;


        static construct
        {
            set_css_name ("timercontrolbuttons");
        }

        construct
        {
            this.session_manager = Ft.SessionManager.get_default ();
            this.timer           = Ft.Timer.get_default ();

            this.update_images ();
        }

        private void add_animation (Adw.TimedAnimation animation)
        {
            this.animations.append (animation);
        }

        private void remove_animation_link (GLib.List<Adw.TimedAnimation>? link)
        {
            if (link == null) {
                return;
            }

            link.data.pause ();
            link.data = null;
            this.animations.delete_link (link);
        }

        private void remove_animation (Adw.TimedAnimation animation)
        {
            unowned GLib.List<Adw.TimedAnimation> link = this.animations.find (animation);

            if (link != null) {
                this.remove_animation_link (link);
            }
        }

        private void stop_animations ()
        {
            unowned GLib.List<Adw.TimedAnimation> link;

            while ((link = this.animations.first ()) != null)
            {
                this.remove_animation_link (link);
            }
        }

        private unowned Adw.TimedAnimation? get_animation (Gtk.Widget widget)
        {
            unowned GLib.List<Adw.TimedAnimation> link = this.animations.first ();

            while (link != null)
            {
                if (link.data.widget == widget) {
                    return link.data;
                }

                link = link.next;
            }

            return null;
        }

        private void fade_in (Gtk.Widget widget,
                              bool       animate = true)
        {
            var animation = this.get_animation (widget);

            if (animation != null) {
                this.remove_animation (animation);
            }

            widget.has_tooltip = true;

            if (!this.get_mapped () || !animate) {
                widget.opacity = 1.0;
                return;
            }

            if (widget.opacity == 1.0) {
                return;
            }

            var animation_target = new Adw.PropertyAnimationTarget (widget, "opacity");

            animation = new Adw.TimedAnimation (widget,
                                                widget.opacity,
                                                1.0,
                                                FADE_IN_DURATION,
                                                animation_target);
            animation.set_easing (Adw.Easing.EASE_OUT_QUAD);
            animation.play ();

            this.add_animation (animation);
        }

        private void fade_out (Gtk.Widget widget,
                               bool       animate = true)
        {
            var animation = this.get_animation (widget);

            if (animation != null) {
                this.remove_animation (animation);
            }

            widget.has_tooltip = false;

            if (!this.get_mapped () || !animate) {
                widget.opacity = 0.0;
                return;
            }

            if (widget.opacity == 0.0) {
                return;
            }

            var animation_target = new Adw.PropertyAnimationTarget (widget, "opacity");

            animation = new Adw.TimedAnimation (widget,
                                                widget.opacity,
                                                0.0,
                                                FADE_OUT_DURATION,
                                                animation_target);
            animation.set_easing (Adw.Easing.EASE_IN_OUT_CUBIC);
            animation.play ();

            this.add_animation (animation);
        }

        private string get_action_name (string page_name)
        {
            switch (page_name)
            {
                case "advance":
                    return "session-manager.advance";

                case "skip":
                    return "session-manager.advance";

                case "skip-break":
                    return "session-manager.skip-break";

                case "reset":
                    return "session-manager.reset";

                case "stop":
                    return "timer.reset";

                default:
                    return "timer.%s".printf (page_name);
            }
        }

        private void update_buttons (bool animate = true)
        {
            var current_time_block = this.session_manager.current_time_block;
            var is_started = this.timer.is_started ();
            var is_paused = this.timer.is_paused ();
            var is_finished = this.timer.is_finished ();
            var is_break = current_time_block != null
                    ? current_time_block.state.is_break ()
                    : true;
            var can_reset = this.session_manager.can_reset ();

            Gtk.StackPage? left_page = null;
            Gtk.StackPage? center_page = null;
            Gtk.StackPage? right_page = null;

            if (!is_started)
            {
                left_page = can_reset
                        ? get_stack_page_by_name (this.left_image_stack, "reset")
                        : null;
                center_page = get_stack_page_by_name (this.center_image_stack, "start");

                assert (center_page != null);

                if (left_page != null) {
                    this.fade_in (this.left_button, animate);
                    this.fade_out (this.right_button, animate);
                }
                else {
                    this.fade_out (this.left_button, animate);
                    this.fade_out (this.right_button, animate);
                }
            }
            else {
                if (is_paused) {
                    left_page = get_stack_page_by_name (this.left_image_stack, "rewind");
                    center_page = get_stack_page_by_name (this.center_image_stack, "resume");
                    right_page = get_stack_page_by_name (this.right_image_stack, "stop");
                }
                else if (is_finished) {
                    left_page = get_stack_page_by_name (this.left_image_stack, "rewind");
                    center_page = get_stack_page_by_name (this.center_image_stack, "advance");
                    right_page = get_stack_page_by_name (this.right_image_stack, "stop");
                }
                else {
                    left_page = get_stack_page_by_name (this.left_image_stack, "rewind");
                    center_page = get_stack_page_by_name (this.center_image_stack, "pause");
                    right_page = get_stack_page_by_name (this.right_image_stack, "skip");
                }

                assert (left_page != null);
                assert (center_page != null);
                assert (right_page != null);

                this.fade_in (this.left_button, animate);
                this.fade_in (this.right_button, animate);
            }

            if (left_page != null)
            {
                if (this.left_button.opacity > 0.0) {
                    this.left_image_stack.visible_child = left_page.child;
                }
                else {
                    this.left_image_stack.set_visible_child_full (left_page.name,
                                                                  Gtk.StackTransitionType.NONE);
                }

                this.left_button.action_name = this.get_action_name (left_page.name);
                this.left_button.tooltip_text = left_page.title;
            }

            if (center_page != null)
            {
                this.center_image_stack.visible_child = center_page.child;
                this.center_button.action_name = this.get_action_name (center_page.name);
                this.center_button.tooltip_text = center_page.name == "advance"
                        ? (is_break ? _("Start Pomodoro") : _("Take a break"))
                        : center_page.title;
            }

            if (right_page != null)
            {
                if (this.right_button.opacity > 0.0) {
                    this.right_image_stack.visible_child = right_page.child;
                }
                else {
                    this.right_image_stack.set_visible_child_full (right_page.name,
                                                                   Gtk.StackTransitionType.NONE);
                }

                this.right_button.action_name = this.get_action_name (right_page.name);
                this.right_button.tooltip_text = right_page.name == "skip"
                        ? (is_break ? _("Start Pomodoro") : _("Take a break"))
                        : right_page.title;
            }

            this.left_button.can_focus = is_started || can_reset;
            this.right_button.can_focus = is_started;
        }

        private void update_images ()
        {
            var is_rtl = this.get_direction () == Gtk.TextDirection.RTL;

            this.skip_image.icon_name = is_rtl
                    ? "timer-skip-symbolic-rtl"
                    : "timer-skip-symbolic";
        }

        private void on_timer_state_changed (Ft.TimerState current_state,
                                             Ft.TimerState previous_state)
        {
            this.update_buttons ();
        }

        /**
         * Hide the reset button once the session has been reset, without animation.
         */
        private void on_session_manager_notify_current_session ()
        {
            var animate = this.session_manager.current_session != null &&
                         !this.session_manager.current_session.is_scheduled ();

            this.update_buttons (animate);
        }

        private void connect_signals ()
        {
            if (this.timer_state_changed_id == 0) {
                this.timer_state_changed_id = this.timer.state_changed.connect_after (this.on_timer_state_changed);
            }

            if (this.session_manager_notify_current_session_id == 0) {
                this.session_manager_notify_current_session_id = this.session_manager.notify["current-session"].connect (this.on_session_manager_notify_current_session);
            }
        }

        private void disconnect_signals ()
        {
            if (this.timer_state_changed_id != 0) {
                this.timer.disconnect (this.timer_state_changed_id);
                this.timer_state_changed_id = 0;
            }

            if (this.session_manager_notify_current_session_id != 0) {
                this.session_manager.disconnect (this.session_manager_notify_current_session_id);
                this.session_manager_notify_current_session_id = 0;
            }
        }

        public override void direction_changed (Gtk.TextDirection previous_direction)
        {
            base.direction_changed (previous_direction);

            this.update_images ();
        }

        public override void map ()
        {
            this.update_buttons (false);
            this.connect_signals ();

            base.map ();
        }

        public override void unmap ()
        {
            this.stop_animations ();
            this.disconnect_signals ();

            base.unmap ();
       }

        public override void dispose ()
        {
            this.stop_animations ();
            this.disconnect_signals ();

            this.session_manager = null;
            this.timer           = null;
            this.animations      = null;

            base.dispose ();
        }
    }
}
