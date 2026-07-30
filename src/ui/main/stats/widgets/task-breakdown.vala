/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    /**
     * A "Tasks" section listing time spent per task within a date range.
     *
     * Used by the day / week / month stats pages. The widget hides itself
     * when there are no named tasks in the range.
     */
    public class TaskBreakdown : Gtk.Box
    {
        private Ft.StatsManager?    stats_manager = null;
        private Gtk.ListBox?        listbox = null;
        private string              first_date_string = "";
        private string              last_date_string = "";
        private uint                update_timeout_id = 0U;

        construct
        {
            this.orientation = Gtk.Orientation.VERTICAL;
            this.spacing = 6;
            this.visible = false;
            this.margin_bottom = 12;

            var heading = new Gtk.Label (_("Tasks"));
            heading.halign = Gtk.Align.START;
            heading.xalign = 0.0f;
            heading.add_css_class ("heading");

            this.listbox = new Gtk.ListBox ();
            this.listbox.selection_mode = Gtk.SelectionMode.NONE;
            this.listbox.add_css_class ("boxed-list");

            this.append (heading);
            this.append (this.listbox);

            this.stats_manager = new Ft.StatsManager ();
            this.stats_manager.entry_saved.connect (this.on_entry_changed);
            this.stats_manager.entry_deleted.connect (this.on_entry_changed);
        }

        public void set_range (GLib.Date first_date,
                               GLib.Date last_date)
        {
            this.first_date_string = Ft.Database.serialize_date (first_date);
            this.last_date_string = Ft.Database.serialize_date (last_date);

            this.populate.begin (
                (obj, res) => {
                    this.populate.end (res);
                });
        }

        private async Gom.ResourceGroup? fetch_entries ()
        {
            var repository = Ft.Database.get_repository ();

            var first_date_value = GLib.Value (typeof (string));
            first_date_value.set_string (this.first_date_string);

            var last_date_value = GLib.Value (typeof (string));
            last_date_value.set_string (this.last_date_string);

            var category_value = GLib.Value (typeof (string));
            category_value.set_string ("pomodoro");

            var first_date_filter = new Gom.Filter.gte (
                    typeof (Ft.StatsEntry),
                    "date",
                    first_date_value);
            var last_date_filter = new Gom.Filter.lte (
                    typeof (Ft.StatsEntry),
                    "date",
                    last_date_value);
            var category_filter = new Gom.Filter.eq (
                    typeof (Ft.StatsEntry),
                    "category",
                    category_value);
            var filter = new Gom.Filter.and (
                    new Gom.Filter.and (first_date_filter, last_date_filter),
                    category_filter);

            try {
                var entries = yield repository.find_async (typeof (Ft.StatsEntry),
                                                           filter);
                yield entries.fetch_async (0U, entries.count);

                return entries;
            }
            catch (GLib.Error error) {
                GLib.critical ("Error while fetching task stats: %s", error.message);

                return null;
            }
        }

        private void remove_all_rows ()
        {
            Gtk.Widget? row;

            while ((row = this.listbox.get_first_child ()) != null) {
                this.listbox.remove (row);
            }
        }

        private void append_task_row (string task,
                                      int64  duration,
                                      double fraction)
        {
            var name_label = new Gtk.Label (task != "" ? task : _("No task"));
            name_label.xalign = 0.0f;
            name_label.ellipsize = Pango.EllipsizeMode.END;

            if (task == "") {
                name_label.add_css_class ("dim-label");
            }

            var fraction_bar = new Gtk.ProgressBar ();
            fraction_bar.fraction = fraction.clamp (0.0, 1.0);
            fraction_bar.hexpand = true;
            fraction_bar.valign = Gtk.Align.CENTER;

            var name_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            name_box.hexpand = true;
            name_box.valign = Gtk.Align.CENTER;
            name_box.append (name_label);
            name_box.append (fraction_bar);

            var duration_label = new Gtk.Label (Ft.Interval.format_short (duration));
            duration_label.valign = Gtk.Align.CENTER;
            duration_label.add_css_class ("dim-label");
            duration_label.add_css_class ("numeric");

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 12;
            box.margin_end = 12;
            box.append (name_box);
            box.append (duration_label);

            var row = new Gtk.ListBoxRow ();
            row.activatable = false;
            row.child = box;

            this.listbox.append (row);
        }

        private async void populate ()
        {
            if (this.first_date_string == "" || this.last_date_string == "") {
                return;
            }

            var entries = yield this.fetch_entries ();

            this.remove_all_rows ();

            string[] task_names = {};
            int64[]  task_durations = {};

            var entries_count = entries != null ? entries.count : 0U;

            for (var index = 0U; index < entries_count; index++)
            {
                var entry = (Ft.StatsEntry) entries.get_index (index);

                if (entry.duration <= 0) {
                    continue;
                }

                var task = entry.task ?? "";
                var task_index = -1;

                for (var i = 0; i < task_names.length; i++)
                {
                    if (task_names[i] == task) {
                        task_index = i;
                        break;
                    }
                }

                if (task_index >= 0) {
                    task_durations[task_index] += entry.duration;
                }
                else {
                    task_names += task;
                    task_durations += entry.duration;
                }
            }

            // Show named tasks sorted by time spent. The "No task" bucket goes last.
            var has_named_tasks = false;

            foreach (unowned var task_name in task_names)
            {
                if (task_name != "") {
                    has_named_tasks = true;
                    break;
                }
            }

            if (has_named_tasks)
            {
                int64 total_duration = 0;

                foreach (var task_duration in task_durations) {
                    total_duration += task_duration;
                }

                var remaining = task_names.length;

                while (remaining > 0)
                {
                    var best_index = -1;

                    for (var i = 0; i < task_names.length; i++)
                    {
                        if (task_durations[i] < 0) {
                            continue;  // already added
                        }

                        if (best_index == -1 ||
                            task_names[best_index] == "" ||
                            (task_names[i] != "" &&
                             task_durations[i] > task_durations[best_index]))
                        {
                            best_index = i;
                        }
                    }

                    this.append_task_row (task_names[best_index],
                                          task_durations[best_index],
                                          (double) task_durations[best_index] /
                                          (double) total_duration);
                    task_durations[best_index] = -1;
                    remaining--;
                }
            }

            this.visible = has_named_tasks;
        }

        private void queue_update ()
        {
            if (this.update_timeout_id != 0) {
                return;
            }

            this.update_timeout_id = GLib.Timeout.add (
                500,
                () => {
                    this.update_timeout_id = 0;

                    this.populate.begin (
                        (obj, res) => {
                            this.populate.end (res);
                        });

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.update_timeout_id,
                                        "Ft.TaskBreakdown.queue_update");
        }

        private void on_entry_changed (Ft.StatsEntry entry)
        {
            if (entry.date == null ||
                this.first_date_string == "" ||
                this.last_date_string == "")
            {
                return;
            }

            // Dates are YYYY-MM-DD, so lexicographic order is chronological.
            if (entry.date >= this.first_date_string &&
                entry.date <= this.last_date_string)
            {
                this.queue_update ();
            }
        }

        public override void dispose ()
        {
            if (this.update_timeout_id != 0) {
                GLib.Source.remove (this.update_timeout_id);
                this.update_timeout_id = 0;
            }

            if (this.stats_manager != null) {
                this.stats_manager.entry_saved.disconnect (this.on_entry_changed);
                this.stats_manager.entry_deleted.disconnect (this.on_entry_changed);
                this.stats_manager = null;
            }

            this.listbox = null;

            base.dispose ();
        }
    }
}
