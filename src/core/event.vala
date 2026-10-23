/*
 * Copyright (c) 2024-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    private bool trigger_start_event (Ft.TimerState current_state,
                                      Ft.TimerState previous_state)
    {
        if (Ft.Context.get_event_source () != "timer.start") {
            return false;
        }

        return current_state.user_data != null && previous_state.user_data == null;
    }

    private bool trigger_stop_event (Ft.TimerState current_state,
                                     Ft.TimerState previous_state)
    {
        if (Ft.Context.get_event_source () != "timer.reset") {
            return false;
        }

        return current_state.user_data == null && previous_state.user_data != null;
    }

    private bool trigger_pause_event (Ft.TimerState current_state,
                                      Ft.TimerState previous_state)
    {
        if (Ft.Context.get_event_source () != "timer.pause") {
            return false;
        }

        return current_state.user_data == previous_state.user_data &&
               current_state.is_paused () && !previous_state.is_paused ();
    }

    private bool trigger_resume_event (Ft.TimerState current_state,
                                       Ft.TimerState previous_state)
    {
        if (Ft.Context.get_event_source () != "timer.resume") {
            return false;
        }

        return current_state.user_data == previous_state.user_data &&
               !current_state.is_paused () && previous_state.is_paused ();
    }

    private bool trigger_rewind_event (Ft.TimerState current_state,
                                       Ft.TimerState previous_state)
    {
        if (Ft.Context.get_event_source () != "timer.rewind") {
            return false;
        }

        return current_state.user_data == previous_state.user_data &&
               current_state.paused_time == previous_state.paused_time &&
               current_state.offset != previous_state.offset;
    }

    private bool trigger_skip_event (Ft.Session?   current_session,
                                     Ft.TimeBlock? current_time_block,
                                     Ft.Session?   previous_session,
                                     Ft.TimeBlock? previous_time_block)
    {
        if (Ft.Context.get_event_source () != "session-manager.advance") {
            return false;
        }

        if (current_time_block == null || previous_time_block == null) {
            return false;
        }

        if (current_time_block.state != Ft.State.POMODORO &&
            previous_time_block.state != Ft.State.POMODORO)
        {
            return false;
        }

        if (current_time_block.state.is_break () == previous_time_block.state.is_break ()) {
            return false;
        }

        return current_time_block.get_status () == Ft.TimeBlockStatus.IN_PROGRESS &&
               previous_time_block.get_status () == Ft.TimeBlockStatus.UNCOMPLETED;
    }

    private bool trigger_reset_event (Ft.Session?   current_session,
                                      Ft.TimeBlock? current_time_block,
                                      Ft.Session?   previous_session,
                                      Ft.TimeBlock? previous_time_block)
    {
        if (Ft.Context.get_event_source () != "session-manager.reset") {
            return false;
        }

        if (current_session == previous_session || previous_session == null) {
            return false;
        }

        if (current_session == null) {
            return true;
        }

        return !previous_session.is_completed ();
    }

    private bool trigger_finish_event (Ft.TimerState current_state,
                                       Ft.TimerState previous_state)
    {
        return current_state.is_finished () && !previous_state.is_finished ();
    }

    private bool trigger_confirm_advancement_event (Ft.TimeBlock next_time_block,
                                                    Ft.TimeBlock previous_time_block)
    {
        return true;
    }

    private bool trigger_advance_event (Ft.Session?   current_session,
                                        Ft.TimeBlock? current_time_block,
                                        Ft.Session?   previous_session,
                                        Ft.TimeBlock? previous_time_block)
    {
        // Internally `SessionManager.advanced` includes a stopped state, as it follows the call to `advance_*`
        // methods. For user this behaviour may not be obvious. The second thing is that it would intersect with
        // `start` and `stop` events. It makes more sense to have `start`, `stop` and `advance` events
        // complementary.

        return current_time_block != null && previous_time_block != null;
    }

    private bool trigger_change_event (Ft.TimerState current_state,
                                       Ft.TimerState previous_state)
    {
        // If timer finishes no true change has been done - the timer finished according to plan.
        if (current_state.is_finished () && current_state.user_data == previous_state.user_data) {
            return false;
        }

        return !current_state.equals (previous_state);
    }

    private bool trigger_state_change_event (Ft.State current_state,
                                             Ft.State previous_state)
    {
        return true;
    }

    private bool trigger_reschedule_event (Ft.Session session)
    {
        return true;
    }

    private bool trigger_expire_event (Ft.Session session)
    {
        return true;
    }


    public enum EventCategory
    {
        OTHER,
        ACTIONS,
        COUNTDOWN,
        SESSION;

        public string get_label ()
        {
            switch (this)
            {
                case ACTIONS:
                    return _("Actions");

                case COUNTDOWN:
                    return _("Countdown");

                case SESSION:
                    return _("Session");

                case OTHER:
                    return _("Other");

                default:
                    assert_not_reached ();
            }
        }

        public static void @foreach (GLib.Func<Ft.EventCategory> func)
        {
            func (ACTIONS);
            func (COUNTDOWN);
            func (SESSION);
            func (OTHER);
        }
    }


    public class EventSpec
    {
        public string                 name;
        public string                 display_name;
        public string                 description;
        public Ft.EventCategory category;

        internal Ft.Trigger[] triggers;

        public EventSpec (string            name,
                          string            display_name,
                          string            description,
                          Ft.EventCategory category = Ft.EventCategory.OTHER)
        {
            this.name = name;
            this.display_name = display_name;
            this.description = description;
            this.category = category;
            this.triggers = new Ft.Trigger[0];
        }

        public void add_trigger (Ft.TriggerHook trigger_hook,
                                 Ft.TriggerFunc trigger_func)
        {
            unowned var self = this;

            this.triggers += Ft.Trigger () {
                event_spec = self,
                hook       = trigger_hook,
                func       = trigger_func
            };
        }
    }


    [Compact]
    public class Event
    {
        public Ft.EventSpec spec;
        public Ft.Context   context;

        public Event (Ft.EventSpec spec,
                      Ft.Context   context)
        {
            this.spec = spec;
            this.context = context;
        }

        ~Event ()
        {
            this.spec = null;
            this.context = null;
        }
    }


    internal void initialize_events (Ft.EventProducer producer)
    {
        Ft.EventSpec event_spec;

        // Actions
        event_spec = new Ft.EventSpec ("start",
                                       _("Start"),
                                       _("Started the timer"),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_start_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("stop",
                                       _("Stop"),
                                       _("Stopped the timer manually"),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_stop_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("pause",
                                       _("Pause"),
                                       _("The countdown has been manually paused. Not triggered when locking the screen or when suspending the system."),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_pause_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("resume",
                                       _("Resume"),
                                       _("The countdown has been manually resumed"),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_resume_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("skip",
                                       _("Skip"),
                                       _("Jumped to a next time-block before the countdown has finished"),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_ADVANCED,
                                (Ft.TriggerFunc) trigger_skip_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("rewind",
                                       _("Rewind"),
                                       _("Rewind action has been used. It adds a pause in the past."),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_rewind_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("reset",
                                       _("Reset"),
                                       _("Manually cleared the session"),
                                       Ft.EventCategory.ACTIONS);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_ADVANCED,
                                (Ft.TriggerFunc) trigger_reset_event);
        producer.install_event (event_spec);

        // Countdown
        event_spec = new Ft.EventSpec ("finish",
                                       _("Finished"),
                                       _("The countdown has finished. If waiting for confirmation, the duration of the time-block still may be altered."),
                                       Ft.EventCategory.COUNTDOWN);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_finish_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("change",
                                       _("Changed"),
                                       _("Triggered on any change related to the countdown"),
                                       Ft.EventCategory.COUNTDOWN);
        event_spec.add_trigger (Ft.TriggerHook.TIMER_STATE_CHANGED,
                                (Ft.TriggerFunc) trigger_change_event);
        producer.install_event (event_spec);

        // Session
        event_spec = new Ft.EventSpec ("confirm-advancement",
                                       _("Confirm Advancement"),
                                       _("A manual confirmation is required to start next time-block"),
                                       Ft.EventCategory.SESSION);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_CONFIRM_ADVANCEMENT,
                                (Ft.TriggerFunc) trigger_confirm_advancement_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("advance",
                                       _("Advanced"),
                                       _("Transitioned or skipped to a next time-block"),
                                       Ft.EventCategory.SESSION);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_ADVANCED,
                                (Ft.TriggerFunc) trigger_advance_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("state-change",
                                       _("State Changed"),
                                       _("Transitioned to a next time-block or when a break gets relabelled"),
                                       Ft.EventCategory.SESSION);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_NOTIFY_CURRENT_STATE,
                                (Ft.TriggerFunc) trigger_state_change_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("reschedule",
                                       _("Rescheduled"),  // translators: Change of plan
                                       _("Triggered when scheduled time-blocks have changed"),
                                       Ft.EventCategory.SESSION);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_SESSION_RESCHEDULED,
                                (Ft.TriggerFunc) trigger_reschedule_event);
        producer.install_event (event_spec);

        event_spec = new Ft.EventSpec ("expire",
                                       _("Expired"),
                                       _("Triggered when session is about to be reset due to inactivity"),
                                       Ft.EventCategory.SESSION);
        event_spec.add_trigger (Ft.TriggerHook.SESSION_MANAGER_SESSION_EXPIRED,
                                (Ft.TriggerFunc) trigger_expire_event);
        producer.install_event (event_spec);
    }
}
