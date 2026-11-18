/*
 * Copyright (c) 2017, 2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    public enum Timeframe
    {
        DAY,
        WEEK,
        MONTH;

        public static Ft.Timeframe from_string (string? timeframe)
        {
            switch (timeframe)
            {
                case "day":
                    return DAY;

                case "week":
                    return WEEK;

                case "month":
                    return MONTH;

                default:
                    return DAY;
            }
        }

        public string to_string ()
        {
            switch (this)
            {
                case DAY:
                    return "day";

                case WEEK:
                    return "week";

                case MONTH:
                    return "month";

                default:
                    assert_not_reached ();
            }
        }

        public string get_label ()
        {
            switch (this)
            {
                case DAY:
                    return _("Day");

                case WEEK:
                    return _("Week");

                case MONTH:
                    return _("Month");

                default:
                    assert_not_reached ();
            }
        }

        public GLib.Date normalize_date (GLib.Date date)
        {
            var normalized_date = date.copy ();

            if (!normalized_date.valid ()) {
                return normalized_date;
            }

            switch (this)
            {
                case DAY:
                    break;

                case WEEK:
                    var first_day_of_week = Ft.Locale.get_first_day_of_week ();
                    var offset = (int) date.get_weekday () - (int) first_day_of_week;

                    if (offset < 0) {
                        offset += 7;
                    }

                    normalized_date.subtract_days (offset);
                    break;

                case MONTH:
                    normalized_date.set_day (1);
                    break;

                default:
                    assert_not_reached ();
            }

            return normalized_date;
        }
    }


    public enum NavigationDirection
    {
        FORWARD,
        BACKWARD
    }


    public class StatsViewModel : GLib.Object
    {
        [CCode (notify = false)]
        public Ft.Timeframe timeframe {
            get {
                return this._timeframe;
            }
            set {
                if (this._timeframe == value) {
                    return;
                }

                this._timeframe = value;

                this.notify_property ("timeframe");
            }
        }

        [CCode (notify = false)]
        public GLib.Date date {
            get {
                return this._date;
            }
            set {
                if (!value.valid ()) {
                    return;
                }

                if (this._date.valid () && this._date.compare (value) == 0) {
                    return;
                }

                this._date = value.copy ();

                this.validate_user_selected_date ();
                this.notify_property ("date");
            }
        }

        [CCode (notify = false)]
        public GLib.Date min_date {
            get {
                return this._min_date;
            }
            private set {
                if (this._min_date.valid () && this._min_date.compare (value) == 0) {
                    return;
                }

                this._min_date = value;
                this.notify_property ("min-date");
            }
        }

        [CCode (notify = false)]
        public GLib.Date max_date {
            get {
                return this._max_date;
            }
            private set {
                if (this._max_date.valid () && this._max_date.compare (value) == 0) {
                    return;
                }

                this._max_date = value;
                this.notify_property ("max-date");
            }
        }

        private Ft.Timeframe        _timeframe = Ft.Timeframe.DAY;
        private GLib.Date           _date;
        private GLib.Date           _min_date;
        private GLib.Date           _max_date;
        private GLib.Date           user_selected_date;
        private Gom.Repository?     repository = null;
        private Ft.StatsManager?    stats_manager = null;
        private Ft.SleepMonitor?    sleep_monitor = null;
        private GLib.Cancellable?   navigation_cancellable = null;
        private ulong               woke_up_id = 0;
        private ulong               entry_saved_id = 0;

        construct
        {
            this.repository      = Ft.Database.get_repository ();
            this.stats_manager   = new Ft.StatsManager ();
            this.sleep_monitor   = new Ft.SleepMonitor ();

            var today = this.stats_manager.get_today ();

            this.user_selected_date = today.copy ();
            this._max_date          = today.copy ();
            this._date              = today.copy ();

            this.fetch_min_date.begin (
                (obj, res) => {
                    this.min_date = this.fetch_min_date.end (res);
                });

            this.entry_saved_id = this.stats_manager.entry_saved.connect ((entry) => {
                this.update_date_range ();
            });

            this.woke_up_id = this.sleep_monitor.woke_up.connect (() => {
                this.update_date_range ();
            });
        }

        private void validate_user_selected_date ()
        {
            if (!this.user_selected_date.valid ()) {
                return;
            }

            var is_valid = true;

            switch (this._timeframe)
            {
                case Ft.Timeframe.DAY:
                    is_valid = this.user_selected_date.compare (this._date) == 0;
                    break;

                case Ft.Timeframe.WEEK:
                    var week_start = this._date.copy ();
                    var week_end = this._date.copy ();
                    week_end.add_days (6U);

                    is_valid = this.user_selected_date.compare (week_start) >= 0 &&
                               this.user_selected_date.compare (week_end) <= 0;
                    break;

                case Ft.Timeframe.MONTH:
                    is_valid = this.user_selected_date.get_month () == this._date.get_month () &&
                               this.user_selected_date.get_year () == this._date.get_year ();
                    break;

                default:
                    assert_not_reached ();
            }

            if (!is_valid) {
                this.user_selected_date = GLib.Date ();
            }
        }

        public void select_date (GLib.Date date)
        {
            this.user_selected_date = date.copy ();
            this.date = this._timeframe.normalize_date (date);
        }

        public void select_timeframe (Ft.Timeframe timeframe)
        {
            this.timeframe = timeframe;
        }

        public void select (GLib.Date          date,
                            Ft.Timeframe timeframe)
        {
            this.user_selected_date = date.copy ();

            date = timeframe.normalize_date (date);

            var date_changed = this._date.valid ()
                    ? this._date.compare (date) != 0
                    : date.valid ();
            var timeframe_changed = this._timeframe != timeframe;

            this._timeframe = timeframe;
            this._date = date;

            if (timeframe_changed) {
                this.notify_property ("timeframe");
            }

            if (date_changed) {
                this.notify_property ("date");
            }
        }

        public GLib.Date get_selection_date ()
        {
            return this.user_selected_date.valid ()
                    ? this.user_selected_date.copy ()
                    : this._date.copy ();
        }

        public void update_date_range ()
        {
            this.max_date = this.stats_manager.get_today ();

            if (!this.min_date.valid ()) {
                this.min_date = this.fetch_min_date_sync ();
            }
        }

        private async GLib.Date fetch_min_date ()
        {
            var min_date = GLib.Date ();

            if (this.repository == null) {
                return min_date;
            }

            var sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
            sorting.add (typeof (Ft.AggregatedStatsEntry), "date", Gom.SortingMode.ASCENDING);

            try {
                var results = yield this.repository.find_sorted_async (
                        typeof (Ft.AggregatedStatsEntry),
                        null,
                        sorting);

                if (results.count > 0)
                {
                    yield results.fetch_async (0U, 1U);

                    var entry = (Ft.AggregatedStatsEntry?) results.get_index (0);

                    if (entry != null && entry.date != null) {
                        return Ft.Database.parse_date (entry.date);
                    }
                }
            }
            catch (GLib.Error error) {
                GLib.critical ("Error while fetching minimal stats date: %s", error.message);
            }

            return min_date;
        }

        private GLib.Date fetch_min_date_sync ()
        {
            var min_date = GLib.Date ();

            if (this.repository == null) {
                return min_date;
            }

            var sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));
            sorting.add (typeof (Ft.AggregatedStatsEntry), "date", Gom.SortingMode.ASCENDING);

            try {
                var results = this.repository.find_sorted_sync (
                        typeof (Ft.AggregatedStatsEntry),
                        null,
                        sorting);

                if (results.count > 0)
                {
                    results.fetch_sync (0U, 1U);

                    var entry = (Ft.AggregatedStatsEntry?) results.get_index (0);

                    if (entry != null && entry.date != null) {
                        return Ft.Database.parse_date (entry.date);
                    }
                }
            }
            catch (GLib.Error error) {
                GLib.critical ("Error while fetching minimal stats date: %s", error.message);
            }

            return min_date;
        }

        private async GLib.Date fetch_closest_date (GLib.Date           date,
                                                    NavigationDirection direction)
        {
            if (this.repository == null) {
                return date;
            }

            var date_value = GLib.Value (typeof (string));
            date_value.set_string (Ft.Database.serialize_date (date));

            var category_value = GLib.Value (typeof (string));
            category_value.set_string ("pomodoro");

            var duration_value = GLib.Value (typeof (int64));
            duration_value.set_int64 (Ft.Interval.MINUTE);

            Gom.Filter date_filter;
            var sorting = (Gom.Sorting) GLib.Object.@new (typeof (Gom.Sorting));

            if (direction == NavigationDirection.FORWARD) {
                date_filter = new Gom.Filter.gte (
                        typeof (Ft.AggregatedStatsEntry), "date", date_value);
                sorting.add (
                        typeof (Ft.AggregatedStatsEntry), "date", Gom.SortingMode.ASCENDING);
            }
            else {
                date_filter = new Gom.Filter.lte (
                        typeof (Ft.AggregatedStatsEntry), "date", date_value);
                sorting.add (
                        typeof (Ft.AggregatedStatsEntry), "date", Gom.SortingMode.DESCENDING);
            }

            var category_filter = new Gom.Filter.eq (
                    typeof (Ft.AggregatedStatsEntry), "category", category_value);

            var duration_filter = new Gom.Filter.gte (
                    typeof (Ft.AggregatedStatsEntry), "duration", duration_value);

            var filter = new Gom.Filter.and (
                    new Gom.Filter.and (date_filter, category_filter),
                    duration_filter);

            try {
                var results = yield this.repository.find_sorted_async (
                        typeof (Ft.AggregatedStatsEntry),
                        filter,
                        sorting);

                if (results.count == 0) {
                    return direction == NavigationDirection.FORWARD
                            ? this._max_date
                            : this._min_date;
                }

                yield results.fetch_async (0U, 1U);

                var entry = (Ft.AggregatedStatsEntry?) results.get_index (0);

                return entry != null
                        ? Ft.Database.parse_date (entry.date)
                        : date;
            }
            catch (GLib.Error error)
            {
                GLib.warning ("Error fetching closest date: %s", error.message);

                return date;
            }
        }

        public async void navigate (NavigationDirection direction,
                                    GLib.Cancellable    cancellable)
        {
            var current_date = this._date.copy ();
            var date = this._date.copy ();
            var timeframe = this._timeframe;

            if (direction == NavigationDirection.FORWARD)
            {
                switch (timeframe)
                {
                    case Ft.Timeframe.DAY:
                        date.add_days (1);
                        break;

                    case Ft.Timeframe.WEEK:
                        date.add_days (7);
                        break;

                    case Ft.Timeframe.MONTH:
                        date.add_months (1);
                        break;

                    default:
                        assert_not_reached ();
                }
            }
            else {
                date.subtract_days (1);
            }

            var closest_date = yield this.fetch_closest_date (date, direction);
            var skipped = 0U;

            if (!closest_date.valid () || cancellable.is_cancelled ()) {
                return;
            }

            date = timeframe.normalize_date (closest_date);

            switch (this._timeframe)
            {
                case Ft.Timeframe.DAY:
                    skipped = (uint) (current_date.days_between (date).abs ());
                    break;

                case Ft.Timeframe.WEEK:
                    skipped = (uint) ((current_date.days_between (date).abs ()) / 7);
                    break;

                case Ft.Timeframe.MONTH:
                    var skipped_int =
                            ((int) date.get_year () - (int) current_date.get_year ()) * 12 +
                            ((int) date.get_month () - (int) current_date.get_month ());
                    skipped = (uint) (skipped_int.abs ());
                    break;

                default:
                    assert_not_reached ();
            }

            this.user_selected_date = date.copy ();
            this.date = date.copy ();

            if (skipped > 1U) {
                this.navigated (direction, date, skipped - 1U);
            }
            else {
                this.navigated (direction, date, 0U);
            }
        }

        public override void dispose ()
        {
            if (this.woke_up_id != 0) {
                this.sleep_monitor.disconnect (this.woke_up_id);
                this.woke_up_id = 0;
            }

            if (this.entry_saved_id != 0) {
                this.stats_manager.disconnect (this.entry_saved_id);
                this.entry_saved_id = 0;
            }

            this.repository = null;
            this.stats_manager = null;
            this.sleep_monitor = null;
            this.navigation_cancellable = null;

            base.dispose ();
        }

        public signal void navigated (Ft.NavigationDirection direction,
                                      GLib.Date              date,
                                      uint                   skipped);
    }

    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/main/stats/stats-view.ui")]
    public class StatsView : Adw.BreakpointBin
    {
        private const uint PAGES_HISTORY_LIMIT = 2;
        private const uint TOAST_DISMISS_TIMEOUT = 2;

        public int64 daily_interval {
            get; set; default = Ft.Interval.HOUR;
        }

        [GtkChild]
        private unowned Gtk.Stack stack;
        [GtkChild]
        private unowned Gtk.Label title_label;
        [GtkChild]
        private unowned Gtk.Label subtitle_label;
        [GtkChild]
        private unowned Ft.StatsDatePopover date_popover;
        [GtkChild]
        private unowned Gtk.Button up_button;
        [GtkChild]
        private unowned Gtk.Stack pages;

        private Ft.StatsViewModel?                  model = null;
        private GLib.SimpleAction?                  previous_action = null;
        private GLib.SimpleAction?                  next_action = null;
        private GLib.SimpleAction?                  today_action = null;
        private GLib.SimpleAction?                  up_action = null;
        private GLib.SimpleAction?                  timeframe_action = null;
        private GLib.Queue<unowned Ft.StatsPage>    pages_history = null;
        private GLib.Cancellable?                   navigation_cancellable = null;
        private Adw.Toast?                          last_toast = null;
        private int64                               last_user_active_time = Ft.Timestamp.UNDEFINED;
        private uint                                update_page_idle_id = 0U;
        private uint                                timeout_id = 0U;

        static construct
        {
            set_css_name ("statsview");

            // TODO: move these keybindings to window
            //       currently they work only if view is in focus
            add_binding_action (Gdk.Key.Left,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.previous",
                                null);
            add_binding_action (Gdk.Key.Right,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.next",
                                null);
            add_binding_action (Gdk.Key.Page_Down,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.previous",
                                null);
            add_binding_action (Gdk.Key.Page_Up,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.next",
                                null);
            add_binding_action (Gdk.Key.Home,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.today",
                                null);
            add_binding_action (Gdk.Key.t,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.today",
                                null);
            add_binding_action (Gdk.Key.d,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.set-timeframe",
                                "s",
                                "day");
            add_binding_action (Gdk.Key.w,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.set-timeframe",
                                "s",
                                "week");
            add_binding_action (Gdk.Key.m,
                                Gdk.ModifierType.NO_MODIFIER_MASK,
                                "stats.set-timeframe",
                                "s",
                                "month");
        }

        construct
        {
            this.model         = new Ft.StatsViewModel ();
            this.pages_history = new GLib.Queue<unowned Ft.StatsPage> ();

            this.initialize_action_group ();

            this.model.bind_property (
                    "timeframe",
                    this.date_popover,
                    "timeframe",
                    GLib.BindingFlags.SYNC_CREATE);
            this.model.bind_property (
                    "date",
                    this.date_popover,
                    "date",
                    GLib.BindingFlags.SYNC_CREATE);
            this.model.bind_property (
                    "min-date",
                    this.date_popover,
                    "min-date",
                    GLib.BindingFlags.SYNC_CREATE);
            this.model.bind_property (
                    "max-date",
                    this.date_popover,
                    "max-date",
                    GLib.BindingFlags.SYNC_CREATE);

            this.stack.visible = false;

            this.model.notify["timeframe"].connect ((pspec) => {
                this.queue_update_page ();
            });
            this.model.notify["date"].connect ((pspec) => {
                this.queue_update_page ();
            });
            this.model.notify["min-date"].connect ((pspec) => {
                this.update_actions ();
                this.update_placeholder ();

                this.stack.visible = true;
            });
            this.model.notify["max-date"].connect ((pspec) => {
                this.update_actions ();
                this.update_title ();

                if (this.get_mapped () && this.is_user_idle ()) {
                    this.navigate_to_today ();
                }
            });

            this.model.navigated.connect (
                (direction, date, skipped) => {
                    var last_page = this.pages_history.peek_nth (1U);
                    var transition_type = direction == NavigationDirection.FORWARD
                            ? Gtk.StackTransitionType.SLIDE_LEFT
                            : Gtk.StackTransitionType.SLIDE_RIGHT;

                    if (last_page == null || last_page.date.compare (date) != 0)
                    {
                        if (this.last_toast != null) {
                            this.last_toast.dismiss ();
                        }

                        if (skipped > 0U) {
                            this.notify_skipped_pages (skipped);
                        }
                    }

                    if (this.update_page_idle_id != 0) {
                        this.remove_tick_callback (this.update_page_idle_id);
                        this.update_page_idle_id = 0;
                    }

                    this.update_page (transition_type);
                });
        }

        private string build_page_name (Ft.Timeframe timeframe,
                                        GLib.Date          date)
        {
            return "%s:%s".printf (timeframe.to_string (),
                                   Ft.DateUtils.format_date (date, "%d-%m-%Y"));
        }

        private Ft.StatsPage? create_page (Ft.Timeframe timeframe,
                                                 GLib.Date          date)
        {
            Ft.StatsPage? page;

            switch (timeframe)
            {
                case Ft.Timeframe.DAY:
                    page = new Ft.StatsDayPage (date);
                    this.bind_property (
                            "daily-interval",
                            page,
                            "interval",
                            GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
                    break;

                case Ft.Timeframe.WEEK:
                    page = new Ft.StatsWeekPage (date);
                    break;

                case Ft.Timeframe.MONTH:
                    page = new Ft.StatsMonthPage (date);
                    break;

                default:
                    assert_not_reached ();
            }

            page.valign = Gtk.Align.START;

            return page;
        }

        private Ft.StatsPage? get_page (string name)
        {
            return this.pages.get_child_by_name (name) as Ft.StatsPage;
        }

        private Ft.StatsPage get_or_create_page (Ft.Timeframe timeframe,
                                                       GLib.Date          date)
        {
            var page_name = this.build_page_name (timeframe, date);
            var page = this.get_page (page_name);

            if (page == null) {
                page = this.create_page (timeframe, date);

                this.pages.add_named ((Gtk.Widget) page, page_name);
            }

            return page;
        }

        private void update_page (Gtk.StackTransitionType transition)
        {
            if (this.stack.visible_child_name != "content") {
                return;  // showing placeholder
            }

            if (!this.get_mapped ()) {
                return;
            }

            var page      = this.get_or_create_page (this.model.timeframe, this.model.date);
            var page_name = this.pages.get_page (page).name;

            this.pages_history.remove (page);
            this.pages_history.push_head (page);

            while (this.pages_history.length > PAGES_HISTORY_LIMIT)
            {
                var last_page = this.pages_history.pop_tail ();

                this.pages.remove (last_page);
            }

            this.pages.set_visible_child_full (page_name, transition);

            this.update_title ();
            this.update_actions ();
            this.mark_user_active ();
        }

        private void queue_update_page ()
        {
            if (this.update_page_idle_id != 0) {
                return;
            }

            this.update_page_idle_id = this.add_tick_callback (
                () => {
                    this.update_page_idle_id = 0;
                    this.update_page (Gtk.StackTransitionType.CROSSFADE);

                    return GLib.Source.REMOVE;
                });
        }

        private void clear_pages ()
        {
            while (this.pages_history.length > 0)
            {
                var last_page = this.pages_history.pop_tail ();

                this.pages.remove (last_page);
            }
        }

        private void notify_skipped_pages (uint count)
        {
            string message;

            switch (this.model.timeframe)
            {
                case Ft.Timeframe.DAY:
                    message = ngettext ("Skipped %u day",
                                        "Skipped %u days",
                                        count).printf (count);
                    break;

                case Ft.Timeframe.WEEK:
                    message = ngettext ("Skipped %u week",
                                        "Skipped %u weeks",
                                        count).printf (count);
                    break;

                case Ft.Timeframe.MONTH:
                    message = ngettext ("Skipped %u month",
                                        "Skipped %u months",
                                        count).printf (count);
                    break;

                default:
                    assert_not_reached ();
            }

            var toast = new Adw.Toast (message);
            toast.use_markup = false;
            toast.priority = Adw.ToastPriority.NORMAL;
            toast.timeout = TOAST_DISMISS_TIMEOUT;
            toast.dismissed.connect (() => { this.last_toast = null; });

            var window = this.get_root () as Ft.Window;
            if (window == null) {
                GLib.warning ("Unable to show a toast '%s'", message);
                return;
            }

            window.add_toast (toast);

            this.last_toast = toast;
        }

        private void navigate_to_today ()
        {
            this.model.select_date (this.model.max_date);
        }

        private void navigate_up ()
        {
            var timeframe = this.model.timeframe;
            var date = this.model.get_selection_date ();

            switch (timeframe)
            {
                case Ft.Timeframe.DAY:
                    timeframe = Ft.Timeframe.WEEK;
                    break;

                case Ft.Timeframe.WEEK:
                    timeframe = Ft.Timeframe.MONTH;
                    break;

                case Ft.Timeframe.MONTH:
                    return;

                default:
                    assert_not_reached ();
            }

            this.model.select (date, timeframe);
        }

        private void activate_previous (GLib.SimpleAction action,
                                        GLib.Variant?     parameter)
        {
            if (this.navigation_cancellable != null) {
                this.navigation_cancellable.cancel ();
            }

            this.navigation_cancellable = new GLib.Cancellable ();
            this.model.navigate.begin (NavigationDirection.BACKWARD, this.navigation_cancellable);
        }

        private void activate_next (GLib.SimpleAction action,
                                    GLib.Variant?     parameter)
        {
            if (this.navigation_cancellable != null) {
                this.navigation_cancellable.cancel ();
            }

            this.navigation_cancellable = new GLib.Cancellable ();
            this.model.navigate.begin (NavigationDirection.FORWARD, this.navigation_cancellable);
        }

        private void activate_today (GLib.SimpleAction action,
                                     GLib.Variant?     parameter)
        {
            this.navigate_to_today ();
        }

        private void activate_up ()
        {
            this.navigate_up ();
        }

        private void activate_timeframe (GLib.SimpleAction action,
                                         GLib.Variant?     parameter)
        {
            this.model.select_timeframe (Ft.Timeframe.from_string (parameter.get_string ()));
        }

        private void activate_set_timeframe (GLib.SimpleAction action,
                                             GLib.Variant?     parameter)
        {
            if (parameter != null) {
                this.timeframe_action.activate (parameter);
            }
        }

        private void activate_select_day_action (GLib.SimpleAction action,
                                                 GLib.Variant?     parameter)
        {
            if (parameter == null) {
                return;
            }

            var date = Ft.DateUtils.date_from_variant (parameter);

            if (date.valid ()) {
                this.model.select (date, Ft.Timeframe.DAY);
            }
        }

        private void initialize_action_group ()
        {
            var previous_action = new GLib.SimpleAction ("previous", null);
            previous_action.activate.connect (this.activate_previous);

            var next_action = new GLib.SimpleAction ("next", null);
            next_action.activate.connect (this.activate_next);

            var today_action = new GLib.SimpleAction ("today", null);
            today_action.activate.connect (this.activate_today);

            var up_action = new GLib.SimpleAction ("up", null);
            up_action.bind_property ("enabled",
                                     this.up_button,
                                     "visible",
                                     GLib.BindingFlags.SYNC_CREATE);
            up_action.activate.connect (this.activate_up);

            var timeframe_action = new GLib.SimpleAction.stateful (
                    "timeframe",
                    GLib.VariantType.STRING,
                    new GLib.Variant.string (this.model.timeframe.to_string ()));
            timeframe_action.activate.connect (this.activate_timeframe);

            var set_timeframe_action = new GLib.SimpleAction (
                    "set-timeframe",
                    GLib.VariantType.STRING);
            set_timeframe_action.activate.connect (this.activate_set_timeframe);

            var select_day_action = new GLib.SimpleAction (
                    "select-day",
                    GLib.VariantType.TUPLE);
            select_day_action.activate.connect (this.activate_select_day_action);

            var action_group = new GLib.SimpleActionGroup ();
            action_group.add_action (previous_action);
            action_group.add_action (next_action);
            action_group.add_action (today_action);
            action_group.add_action (up_action);
            action_group.add_action (timeframe_action);
            action_group.add_action (set_timeframe_action);
            action_group.add_action (select_day_action);

            this.previous_action = previous_action;
            this.next_action = next_action;
            this.today_action = today_action;
            this.up_action = up_action;
            this.timeframe_action = timeframe_action;

            this.insert_action_group ("stats", action_group);
        }

        private bool is_user_idle ()
        {
            var now = Ft.Timestamp.from_now ();

            return Ft.Timestamp.is_defined (this.last_user_active_time)
                    ? now - this.last_user_active_time > Ft.Interval.HOUR
                    : false;
        }

        private void mark_user_active ()
        {
            this.last_user_active_time = Ft.Timestamp.from_now ();
        }

        private void update_title ()
        {
            string title;
            string subtitle;

            var timeframe = this.model.timeframe;
            var date      = this.model.date;
            var today     = timeframe.normalize_date (this.model.max_date);

            switch (timeframe)
            {
                case Ft.Timeframe.DAY:
                    subtitle = capitalize_words (Ft.DateUtils.format_date (date, "%A"));

                    if (date.compare (today) == 0) {
                        title = _("Today");
                        subtitle += capitalize_words (
                                Ft.DateUtils.format_date (date, ", %e %B").replace (" ", ""));
                    }
                    else if (date.days_between (today) == 1) {
                        title = _("Yesterday");
                        subtitle += capitalize_words (
                                Ft.DateUtils.format_date (date, ", %e %B").replace (" ", ""));
                    }
                    else if (date.get_year () == today.get_year ()) {
                        title = capitalize_words (
                                Ft.DateUtils.format_date (date, "%e %B").replace (" ", ""));
                    }
                    else {
                        title = capitalize_words (
                                Ft.DateUtils.format_date (date, "%e %B %Y").replace (" ", ""));
                    }

                    break;

                case Ft.Timeframe.WEEK:
                    var week_start_date = date.copy ();
                    var week_end_date = week_start_date.copy ();
                    week_end_date.add_days (6U);

                    if (week_start_date.compare (today) == 0) {
                        title = _("This week");
                    }
                    else {
                        var first_day_of_week = Ft.Locale.get_first_day_of_week ();
                        var first_week_date = GLib.Date ();
                        first_week_date.set_dmy (1, 1, week_end_date.get_year ());

                        var week_number_offset = 1U - (
                                first_day_of_week == GLib.DateWeekday.MONDAY
                                    ? first_week_date.get_monday_week_of_year ()
                                    : first_week_date.get_sunday_week_of_year ()
                                );
                        var week_number = week_number_offset + (
                                first_day_of_week == GLib.DateWeekday.MONDAY
                                    ? week_end_date.get_monday_week_of_year ()
                                    : week_end_date.get_sunday_week_of_year ()
                                );
                        var year = (uint) week_end_date.get_year ();

                        title = week_end_date.get_year () == today.get_year ()
                                ? _("Week %u").printf (week_number)
                                : _("Week %u of %u").printf (week_number, year);
                    }

                    var week_start_format = "%e";
                    var week_end_format = "%e %B";

                    if (week_start_date.get_month () != week_end_date.get_month ()) {
                        week_start_format += " %B";
                    }

                    if (week_end_date.get_year () != today.get_year ()) {
                        week_end_format += " %Y";
                    }

                    subtitle = capitalize_words ("%s – %s".printf (
                        Ft.DateUtils.format_date (week_start_date, week_start_format).replace (" ", ""),
                        Ft.DateUtils.format_date (week_end_date, week_end_format).replace (" ", "")));
                    break;

                case Ft.Timeframe.MONTH:
                    title = capitalize_words (
                            Ft.DateUtils.get_month_name (date.get_month ()));

                    if (date.get_year () != today.get_year ()) {
                        title += Ft.DateUtils.format_date (date, " %Y");
                    }

                    subtitle = "";
                    break;

                default:
                    assert_not_reached ();
            }

            this.title_label.label = title;
            this.subtitle_label.label = subtitle;
            this.subtitle_label.visible = subtitle != "";
        }

        private void update_actions ()
        {
            var timeframe = this.model.timeframe;
            var date      = this.model.date;
            var min_date  = timeframe.normalize_date (this.model.min_date);
            var max_date  = timeframe.normalize_date (this.model.max_date);

            this.previous_action.set_enabled (min_date.valid () && date.compare (min_date) > 0);
            this.next_action.set_enabled (max_date.valid () && date.compare (max_date) < 0);
            this.today_action.set_enabled (this.next_action.get_enabled ());
            this.up_action.set_enabled (timeframe != Ft.Timeframe.MONTH);

            this.timeframe_action.set_state (new GLib.Variant.string (timeframe.to_string ()));
        }

        private void schedule_navigate_to_today ()
        {
            if (this.timeout_id != 0) {
                return;
            }

            // Check date on full hour
			var now = new GLib.DateTime.now_local ();
			var seconds = 3600 - (now.get_minute () * 60 + now.get_second ());

            this.timeout_id = GLib.Timeout.add_seconds (
                seconds + 1,
                () => {
                    this.timeout_id = 0;

                    this.model.update_date_range ();
                    this.schedule_navigate_to_today ();

                    if (this.is_user_idle ()) {
                        this.navigate_to_today ();
                    }

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.timeout_id, "Ft.StatsView.navigate_to_today");
        }

        private void update_placeholder ()
        {
            if (this.model.min_date.valid ()) {
                this.stack.set_visible_child_full ("content", Gtk.StackTransitionType.NONE);
                this.update_page (Gtk.StackTransitionType.NONE);
            }
            else {
                this.stack.set_visible_child_full ("placeholder", Gtk.StackTransitionType.NONE);
                this.clear_pages ();
            }
        }

        [GtkCallback]
        private void on_timeframe_selected (Ft.StatsDatePopover date_popover,
                                            Ft.Timeframe        timeframe)
        {
            this.model.select_timeframe (timeframe);

            GLib.Signal.stop_emission_by_name (date_popover, "timeframe-selected");
        }

        [GtkCallback]
        private void on_date_selected (Ft.StatsDatePopover date_popover,
                                       GLib.Date                 date)
        {
            this.model.select_date (date);

            GLib.Signal.stop_emission_by_name (date_popover, "date-selected");
        }

        public override void map ()
        {
            this.model.update_date_range ();

            base.map ();

            if (this.model.min_date.valid ())
            {
                this.update_placeholder ();

                if (this.is_user_idle ()) {
                    this.navigate_to_today ();
                }
                else {
                    this.mark_user_active ();
                }
            }

            this.schedule_navigate_to_today ();
        }

        public override void unmap ()
        {
            base.unmap ();

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }
        }

        public override void dispose ()
        {
            if (this.update_page_idle_id != 0) {
                this.remove_tick_callback (this.update_page_idle_id);
                this.update_page_idle_id = 0;
            }

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.clear_pages ();

            this.previous_action = null;
            this.next_action = null;
            this.today_action = null;
            this.up_action = null;
            this.timeframe_action = null;
            this.pages_history = null;
            this.navigation_cancellable = null;
            this.last_toast = null;

            base.dispose ();
        }
    }
}
