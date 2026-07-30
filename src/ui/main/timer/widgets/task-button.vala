/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft
{
    /**
     * A button displaying the task time is tracked against.
     *
     * Clicking it opens a popover with a text entry and recently used tasks.
     */
    public class TaskButton : Adw.Bin
    {
        private const int MAX_TASK_NAME_LENGTH = 100;

        private Ft.SessionManager?  session_manager = null;
        private GLib.Settings?      settings = null;
        private Gtk.MenuButton?     menubutton = null;
        private Gtk.Label?          task_label = null;
        private Gtk.Entry?          task_entry = null;
        private Gtk.Popover?        popover = null;
        private Gtk.Box?            recent_box = null;
        private Gtk.ListBox?        recent_listbox = null;
        private Gtk.Button?         clear_button = null;
        private ulong               notify_current_task_id = 0;

        static construct
        {
            set_css_name ("taskbutton");
        }

        construct
        {
            this.session_manager = Ft.SessionManager.get_default ();
            this.settings = Ft.get_settings ();

            this.task_entry = new Gtk.Entry ();
            this.task_entry.placeholder_text = _("What are you working on?");
            this.task_entry.input_hints = Gtk.InputHints.NO_SPELLCHECK;
            this.task_entry.max_length = MAX_TASK_NAME_LENGTH;
            this.task_entry.width_chars = 24;
            this.task_entry.activate.connect (this.on_task_entry_activate);

            this.recent_listbox = new Gtk.ListBox ();
            this.recent_listbox.selection_mode = Gtk.SelectionMode.NONE;
            this.recent_listbox.add_css_class ("boxed-list");
            this.recent_listbox.row_activated.connect (this.on_recent_row_activated);

            var recent_label = new Gtk.Label (_("Recent"));
            recent_label.halign = Gtk.Align.START;
            recent_label.add_css_class ("caption-heading");
            recent_label.add_css_class ("dim-label");

            this.recent_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            this.recent_box.append (recent_label);
            this.recent_box.append (this.recent_listbox);

            this.clear_button = new Gtk.Button.with_label (_("Clear Task"));
            this.clear_button.halign = Gtk.Align.START;
            this.clear_button.add_css_class ("flat");
            this.clear_button.clicked.connect (this.on_clear_button_clicked);

            var popover_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            popover_box.append (this.task_entry);
            popover_box.append (this.recent_box);
            popover_box.append (this.clear_button);

            this.popover = new Gtk.Popover ();
            this.popover.child = popover_box;
            this.popover.map.connect (this.on_popover_map);

            this.task_label = new Gtk.Label (null);
            this.task_label.ellipsize = Pango.EllipsizeMode.END;
            this.task_label.max_width_chars = 30;
            this.task_label.xalign = 0.0f;

            var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            button_box.append (new Gtk.Image.from_icon_name ("document-edit-symbolic"));
            button_box.append (this.task_label);

            this.menubutton = new Gtk.MenuButton ();
            this.menubutton.child = button_box;
            this.menubutton.popover = this.popover;
            this.menubutton.has_frame = false;
            this.menubutton.halign = Gtk.Align.START;
            this.menubutton.tooltip_text = _("Set the task you're working on");

            this.child = this.menubutton;

            this.notify_current_task_id = this.session_manager.notify["current-task"].connect (
                    this.on_notify_current_task);

            this.update_task_label ();
        }

        private void set_task (string task)
        {
            this.session_manager.current_task = task;
            this.popover.popdown ();
        }

        private void update_task_label ()
        {
            var current_task = this.session_manager.current_task;

            if (current_task != "") {
                this.task_label.label = current_task;
                this.task_label.remove_css_class ("dim-label");
            }
            else {
                this.task_label.label = _("Set a task…");
                this.task_label.add_css_class ("dim-label");
            }
        }

        private void update_recent_listbox ()
        {
            Gtk.Widget? row;

            while ((row = this.recent_listbox.get_first_child ()) != null) {
                this.recent_listbox.remove (row);
            }

            var task_history = this.settings.get_strv ("task-history");

            foreach (unowned var task in task_history)
            {
                if (task == "") {
                    continue;
                }

                var label = new Gtk.Label (task);
                label.ellipsize = Pango.EllipsizeMode.END;
                label.max_width_chars = 30;
                label.xalign = 0.0f;
                label.margin_top = 8;
                label.margin_bottom = 8;
                label.margin_start = 10;
                label.margin_end = 10;

                this.recent_listbox.append (label);
            }

            this.recent_box.visible = task_history.length > 0;
        }

        private void on_popover_map ()
        {
            var current_task = this.session_manager.current_task;

            this.update_recent_listbox ();

            this.task_entry.text = current_task;
            this.task_entry.set_position (-1);
            this.clear_button.visible = current_task != "";
        }

        private void on_task_entry_activate ()
        {
            this.set_task (this.task_entry.text);
        }

        private void on_recent_row_activated (Gtk.ListBoxRow row)
        {
            var label = row.child as Gtk.Label;

            if (label != null) {
                this.set_task (label.label);
            }
        }

        private void on_clear_button_clicked ()
        {
            this.set_task ("");
        }

        private void on_notify_current_task ()
        {
            this.update_task_label ();
        }

        public override void dispose ()
        {
            if (this.notify_current_task_id != 0) {
                this.session_manager.disconnect (this.notify_current_task_id);
                this.notify_current_task_id = 0;
            }

            this.session_manager = null;
            this.settings = null;
            this.menubutton = null;
            this.task_label = null;
            this.task_entry = null;
            this.popover = null;
            this.recent_box = null;
            this.recent_listbox = null;
            this.clear_button = null;

            base.dispose ();
        }
    }
}
