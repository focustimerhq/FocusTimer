/*
 * Copyright (c) 2013-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/main/stats/stats-month-page.ui")]
    public class StatsMonthPage : Adw.Bin, Ft.StatsPage
    {
        private const int DAYS_PER_WEEK = 7;

        public GLib.Date date { get; construct; }

        [GtkChild]
        private unowned Ft.BubbleChart bubble_chart;
        [GtkChild]
        private unowned Ft.StatsCard pomodoro_card;
        [GtkChild]
        private unowned Ft.StatsCard breaks_card;
        [GtkChild]
        private unowned Ft.StatsCard interruptions_card;
        [GtkChild]
        private unowned Ft.StatsCard break_ratio_card;
        [GtkChild]
        private unowned Ft.TaskBreakdown task_breakdown;

        private Ft.StatsManager? stats_manager;
        private GLib.Date        display_start_date;
        private GLib.Date        display_end_date;

        construct
        {
            this.stats_manager = new Ft.StatsManager ();
            this.stats_manager.entry_saved.connect (this.on_entry_saved);
            this.stats_manager.entry_deleted.connect (this.on_entry_deleted);

            this.bubble_chart.category = Ft.StatsCategory.POMODORO;

            this.bubble_chart.set_category_label (
                    Ft.StatsCategory.POMODORO, _("Pomodoro"));
            this.bubble_chart.set_category_unit (
                    Ft.StatsCategory.POMODORO, Ft.Unit.INTERVAL);

            this.bubble_chart.set_category_label (
                    Ft.StatsCategory.BREAK, _("Breaks"));
            this.bubble_chart.set_category_unit (
                    Ft.StatsCategory.BREAK, Ft.Unit.INTERVAL);

            this.bubble_chart.set_category_label (
                    Ft.StatsCategory.INTERRUPTION, _("Interruptions"));
            this.bubble_chart.set_category_unit (
                    Ft.StatsCategory.INTERRUPTION, Ft.Unit.AMOUNT);

            var month = this.date.get_month ();
            var year = this.date.get_year ();

            var month_start_date = GLib.Date ();
            month_start_date.set_dmy (1, month, year);

            var month_end_date = GLib.Date ();
            month_end_date.set_dmy (GLib.Date.get_days_in_month (month, year), month, year);

            this.display_start_date = Ft.Timeframe.WEEK.normalize_date (month_start_date);
            this.display_end_date   = Ft.Timeframe.WEEK.normalize_date (month_end_date);
            this.display_end_date.add_days (6U);

            this.task_breakdown.set_range (month_start_date, month_end_date);

            this.populate.begin (
                (obj, res) => {
                    this.populate.end (res);
                });
        }

        public StatsMonthPage (GLib.Date date)
        {
            GLib.Object (
                date: date
            );
        }

        private bool transform_date (GLib.Date date,
                                     out uint  row,
                                     out uint  column)
        {
            var position = this.display_start_date.days_between (date);

            if (position >= 0) {
                column = position % DAYS_PER_WEEK;
                row    = position / DAYS_PER_WEEK;

                return true;
            }
            else {
                column = 0;
                row = 0;

                return false;
            }
        }

        private GLib.Date transform_position (uint row,
                                              uint column)
        {
            var date = this.display_start_date.copy ();
            date.add_days (DAYS_PER_WEEK * row + column);

            return date;
        }

        private void reset ()
        {
            this.bubble_chart.fill (0.0);
            this.pomodoro_card.value = 0.0;
            this.breaks_card.value = 0.0;
            this.interruptions_card.value = 0.0;
            this.break_ratio_card.value = double.NAN;
        }

        private void update_category_colors ()
        {
            var foreground_color = this.bubble_chart.get_color ();
            var pomodoro_color = Ft.get_chart_primary_color (foreground_color);
            var break_color = Ft.get_chart_secondary_color (foreground_color);

            this.bubble_chart.set_category_color (Ft.StatsCategory.POMODORO, pomodoro_color);
            this.bubble_chart.set_category_color (Ft.StatsCategory.BREAK, break_color);
        }

        private void update_bubble_chart_labels ()
        {
            var year_start_date = GLib.Date ();
            year_start_date.set_dmy (1, 1, this.date.get_year ());

            var date = this.display_start_date.copy ();
            var first_day_of_week = Ft.Locale.get_first_day_of_week ();
            var week_number_offset = 1U - (
                    first_day_of_week == GLib.DateWeekday.MONDAY
                        ? year_start_date.get_monday_week_of_year ()
                        : year_start_date.get_sunday_week_of_year ()
                    );
            var row = 0;
            var column = 0;

            while (date.compare (this.display_end_date) <= 0)
            {
                var tooltip_label = capitalize_words (
                        Ft.DateUtils.format_date (date, "%e %B"));

                this.bubble_chart.set_bubble_tooltip_label (row, column, tooltip_label);

                if (row == 0)
                {
                    var weekday_name = capitalize_words (
                        Ft.DateUtils.format_date (date, "%a"));

                    this.bubble_chart.set_column_label (column, weekday_name);
                }

                if (column == 0)
                {
                    var week_end_date = date.copy ();
                    week_end_date.add_days (6U);

                    var week_number = (
                        first_day_of_week == GLib.DateWeekday.MONDAY
                            ? week_end_date.get_monday_week_of_year ()
                            : week_end_date.get_sunday_week_of_year ()
                        ) + week_number_offset;

                    this.bubble_chart.set_row_label (row, @"$(week_number)");
                }

                if (date.get_month () != this.date.get_month ()) {
                    this.bubble_chart.set_bubble_inverted (row, column, true);
                }

                date.add_days (1U);
                column++;

                if (column >= DAYS_PER_WEEK) {
                    column = 0;
                    row++;
                }
            }
        }

        private async Gom.ResourceGroup? fetch_aggregated_entries ()
        {
            var repository = Ft.Database.get_repository ();

            var start_date_value = GLib.Value (typeof (string));
            start_date_value.set_string (Ft.Database.serialize_date (this.display_start_date));

            var end_date_value = GLib.Value (typeof (string));
            end_date_value.set_string (Ft.Database.serialize_date (this.display_end_date));

            var start_date_filter = new Gom.Filter.gte (
                    typeof (Ft.AggregatedStatsEntry),
                    "date",
                    start_date_value);
            var end_date_filter = new Gom.Filter.lte (
                    typeof (Ft.AggregatedStatsEntry),
                    "date",
                    end_date_value);
            var date_filter = new Gom.Filter.and (start_date_filter, end_date_filter);

            try {
                var aggregated_entries = yield repository.find_async (
                        typeof (Ft.AggregatedStatsEntry),
                        date_filter);
                yield aggregated_entries.fetch_async (0U, aggregated_entries.count);

                return aggregated_entries;
            }
            catch (GLib.Error error) {
                GLib.critical ("Error while fetching weekly stats: %s", error.message);

                return null;
            }
        }

        private void process_aggregated_entry (Ft.AggregatedStatsEntry entry)
        {
            var entry_category = Ft.StatsCategory.from_string (entry.category);
            var entry_date     = Ft.Database.parse_date (entry.date);
            var entry_duration = entry.duration;

            // Validate if entry is relevant
            if (entry_category == Ft.StatsCategory.INVALID) {
                return;
            }

            // Update bubble chart
            var category_index = (uint) entry_category;
            uint row, column;

            if (!this.transform_date (entry_date, out row, out column)) {
                return;
            }

            var bucket_value = entry_category != Ft.StatsCategory.INTERRUPTION
                    ? Ft.Interval.to_seconds (entry_duration)
                    : (double) entry.count;

            this.bubble_chart.add_value (row,
                                         column,
                                         category_index,
                                         bucket_value);

            // Update cards
            if (entry_date.get_month () == this.date.get_month ())
            {
                switch (entry_category)
                {
                    case Ft.StatsCategory.POMODORO:
                        this.pomodoro_card.value += bucket_value;
                        break;

                    case Ft.StatsCategory.BREAK:
                        this.breaks_card.value += bucket_value;
                        break;

                    case Ft.StatsCategory.INTERRUPTION:
                        this.interruptions_card.value += bucket_value;
                        break;

                    default:
                        // no matching card in UI
                        break;
                }

                var total = this.pomodoro_card.value + this.breaks_card.value;

                this.break_ratio_card.value = total >= 3600.0
                        ? this.breaks_card.value / total
                        : double.NAN;
            }
        }

        private void process_entry (Ft.StatsEntry entry,
                                    int           sign = 1)
                                    requires (sign == 1 || sign == -1)
        {
            var entry_category = Ft.StatsCategory.from_string (entry.category);
            var entry_date     = Ft.Database.parse_date (entry.date);
            var entry_duration = entry.duration;

            // Validate if entry is relevant
            if (entry_category == Ft.StatsCategory.INVALID) {
                return;
            }

            // Validate date range
            if (entry_date.compare (this.display_start_date) < 0 ||
                entry_date.compare (this.display_end_date) > 0)
            {
                return;
            }

            // Update bubble chart
            uint row, column;

            if (!this.transform_date (entry_date, out row, out column)) {
                return;
            }

            var bucket_value = entry_category != Ft.StatsCategory.INTERRUPTION
                    ? Ft.Interval.to_seconds (sign * entry_duration)
                    : (double) sign;

            this.bubble_chart.add_value (row,
                                         column,
                                         (uint) entry_category,
                                         bucket_value);

            // Update cards
            if (entry_date.get_month () != this.date.get_month ()) {
                return;
            }

            switch (entry_category)
            {
                case Ft.StatsCategory.POMODORO:
                    this.pomodoro_card.value += bucket_value;
                    break;

                case Ft.StatsCategory.BREAK:
                    this.breaks_card.value += bucket_value;
                    break;

                case Ft.StatsCategory.INTERRUPTION:
                    this.interruptions_card.value += bucket_value;
                    break;

                default:
                    // no matching card in UI
                    break;
            }

            var total = this.pomodoro_card.value + this.breaks_card.value;

            this.break_ratio_card.value = total >= 3600.0
                    ? this.breaks_card.value / total
                    : double.NAN;
        }

        private async void populate ()
        {
            var aggregated_entries = yield this.fetch_aggregated_entries ();

            this.update_bubble_chart_labels ();

            this.reset ();

            for (var index = 0U; index < aggregated_entries.count; index++) {
                this.process_aggregated_entry (
                        (Ft.AggregatedStatsEntry) aggregated_entries.get_index (index));
            }
        }

        private void on_entry_saved (Ft.StatsEntry entry)
        {
            this.process_entry (entry, 1);
        }

        private void on_entry_deleted (Ft.StatsEntry entry)
        {
            this.process_entry (entry, -1);
        }

        [GtkCallback]
        private void on_bubble_activated (uint row,
                                          uint column)
        {
            var date = this.transform_position (row, column);

            this.activate_action_variant (
                    "stats.select-day",
                    Ft.DateUtils.date_to_variant (date));
        }

        public override void css_changed (Gtk.CssStyleChange change)
        {
            base.css_changed (change);

            this.update_category_colors ();
        }

        public override void dispose ()
        {
            if (this.stats_manager != null) {
                this.stats_manager.entry_saved.disconnect (this.on_entry_saved);
                this.stats_manager.entry_deleted.disconnect (this.on_entry_deleted);
                this.stats_manager = null;
            }

            base.dispose ();
        }
    }
}
