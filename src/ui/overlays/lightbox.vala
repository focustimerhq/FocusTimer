/*
 * Copyright (c) 2023-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    /**
     * Some compositors (like mutter) unredirect compositing for fullscreened windows, which
     * prevents the window from being transparent. In this case, we can't fade-in/out the
     * window and blur-effect won't work either.
     */
    private bool have_fullscreen_transparency ()
    {
        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;

            default:
                return true;
        }
    }


    /**
     * GTK applies `ext_background_effect_manager_v1` when using a `backdrop-filter` on a
     * semi-transparent window. Check if the compositor advertises the protocol.
     */
    private bool have_background_effect ()
    {
        #if HAVE_GDK_WAYLAND
        if (Gtk.check_version (4, 23, 3) != null) {
            return false;
        }

        var display = Gdk.Display.get_default () as Gdk.Wayland.Display;

        return display != null
                ? display.query_registry ("ext_background_effect_manager_v1")
                : false;
        #else
        return false;
        #endif
    }


    /**
     * A primary monitor used to be defined in X11. Nowadays a primary monitor might be chosen
     * by the compositor. It's unlikely that we will integrate properly with all compositors.
     */
    private unowned Gdk.Monitor? get_primary_monitor (Gdk.Display? display = null)
    {
        if (display == null) {
            display = Gdk.Display.get_default ();
        }

        unowned Gdk.Monitor? primary_monitor = null;
        var primary_monitor_area = 0;
        var monitors = display?.get_monitors ();

        if (monitors == null) {
            return null;
        }

        for (var index = 0; index < monitors.get_n_items (); index++)
        {
            var monitor = (Gdk.Monitor?) monitors.get_item (index);
            var monitor_area = monitor.valid ? monitor.width_mm * monitor.height_mm : 0;

            if (monitor_area > primary_monitor_area) {
                primary_monitor = monitor;
                primary_monitor_area = monitor_area;
            }
        }

        // Fall back to using the first valid monitor.
        if (primary_monitor == null)
        {
            for (var index = 0; index < monitors.get_n_items (); index++)
            {
                var monitor = (Gdk.Monitor?) monitors.get_item (index);

                if (monitor.valid) {
                    primary_monitor = monitor;
                    break;
                }
            }
        }

        return primary_monitor;
    }


    private Gdk.Rectangle get_display_geometry (Gdk.Display? display = null)
    {
        if (display == null) {
            display = Gdk.Display.get_default ();
        }

        var display_geometry = Gdk.Rectangle () {
            x = 0,
            y = 0,
            width = 0,
            height = 0,
        };
        var monitors = display?.get_monitors ();

        if (monitors == null) {
            return display_geometry;
        }

        for (var index = 0; index < monitors.get_n_items (); index++)
        {
            var monitor = (Gdk.Monitor?) monitors.get_item (index);

            if (monitor == null) {
                continue;
            }

            if (index == 0) {
                display_geometry = monitor.get_geometry ();
            }
            else {
                display_geometry.union (monitor.get_geometry (), out display_geometry);
            }
        }

        return display_geometry;
    }


    /**
     * Layout manager that positions window contents within the bounds of a monitor.
     *
     * It's necessary for handling `Gdk.FullscreenMode.ALL_MONITORS`.
     */
    private class MonitorConstrainedLayoutManager : Gtk.LayoutManager
    {
        public Gdk.Monitor? monitor {
            get {
                return this._monitor;
            }
            set {
                this._monitor = value;

                this.layout_changed ();
            }
        }

        private Gdk.Monitor? _monitor = null;

        public MonitorConstrainedLayoutManager (Gdk.Monitor? monitor = null)
        {
            this.monitor = monitor;
        }

        public override Gtk.SizeRequestMode get_request_mode (Gtk.Widget widget)
        {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure (Gtk.Widget      widget,
                                      Gtk.Orientation orientation,
                                      int             for_size,
                                      out int         minimum,
                                      out int         natural,
                                      out int         minimum_baseline,
                                      out int         natural_baseline)
        {
            if (this._monitor != null)
            {
                minimum = natural = orientation == Gtk.Orientation.HORIZONTAL
                        ? this._monitor.geometry.width
                        : this._monitor.geometry.height;
            }
            else {
                minimum = natural = 0;
            }

            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public override void allocate (Gtk.Widget widget,
                                       int        width,
                                       int        height,
                                       int        baseline)
        {
            var allocation = Gtk.Allocation () {
                x = 0,
                y = 0,
                width = width,
                height = height
            };

            if (this._monitor != null)
            {
                var monitor_geometry = this._monitor.get_geometry ();
                allocation.x = monitor_geometry.x;
                allocation.y = monitor_geometry.y;
                allocation.width = monitor_geometry.width;
                allocation.height = monitor_geometry.height;
            }

            var child = widget.get_first_child ();

            while (child != null)
            {
                if (!child.should_layout ()) {
                    continue;
                }

                child.allocate_size (allocation, -1);
                child = child.get_next_sibling ();
            }
        }
    }


    private errordomain LightboxError
    {
        NO_MONITORS,
    }


    /**
     * Helper class for handling overlays on multiple screens.
     */
    public class LightboxGroup : GLib.InitiallyUnowned
    {
        private const uint DEACTIVATE_TIMEOUT_MS = 250;

        private GLib.Type                       lightbox_type;
        private GLib.GenericSet<Ft.Lightbox>?   lightboxes = null;
        private Gtk.WindowGroup?                window_group = null;
        private GLib.ListModel?                 monitors = null;
        private ulong                           monitors_changed_id = 0;
        private uint                            updating_count = 0;
        private uint                            update_idle_id = 0;
        private uint                            deactivate_timeout_id = 0;
        private bool                            closing = false;
        private unowned Ft.Lightbox?            primary_lightbox = null;
        private GLib.SourceFunc?                open_callback = null;

        public LightboxGroup (GLib.Type lightbox_type)
        {
            this.lightbox_type = lightbox_type;
            this.lightboxes = new GLib.GenericSet<Ft.Lightbox> (GLib.direct_hash, GLib.direct_equal);
        }

        private unowned Ft.Lightbox? get_first_lightbox ()
        {
            unowned Ft.Lightbox? first_lightbox = null;

            this.lightboxes.@foreach (
                (lightbox) => {
                    if (lightbox != null) {
                        first_lightbox = lightbox;
                    }
                });

            return first_lightbox;
        }

        private unowned Ft.Lightbox? get_active_lightbox ()
        {
            unowned Ft.Lightbox? active_lightbox = null;

            this.lightboxes.@foreach (
                (lightbox) => {
                    if (active_lightbox == null && lightbox != null && lightbox.is_active) {
                        active_lightbox = lightbox;
                    }
                });

            return active_lightbox;
        }

        private unowned Ft.Lightbox? get_primary_lightbox ()
        {
            return this.primary_lightbox != null
                    ? this.primary_lightbox
                    : this.get_first_lightbox ();
        }

        private Ft.Lightbox create_lightbox (Gdk.Monitor? monitor_request)
        {
            var monitor_request_value = GLib.Value (typeof (Gdk.Monitor?));
            monitor_request_value.set_object (monitor_request);

            var show_contents_value = GLib.Value (typeof (bool));
            show_contents_value.set_boolean (false);

            var lightbox = (Ft.Lightbox) GLib.Object.new_with_properties (
                                        this.lightbox_type,
                                        { "monitor-request", "show-contents" },
                                        { monitor_request_value, show_contents_value });
            lightbox.notify["monitor"].connect (this.on_lightbox_queue_update);
            lightbox.notify["all-monitors-mode"].connect (this.on_lightbox_notify_all_monitors_mode);
            lightbox.notify["fullscreened"].connect (this.on_lightbox_notify_fullscreened);
            lightbox.notify["is-active"].connect (this.on_lightbox_notify_is_active);
            lightbox.close_request.connect (this.on_lightbox_close_request);

            var lightbox_widget = (Gtk.Widget) lightbox;
            lightbox_widget.unrealize.connect (this.on_lightbox_unrealize);

            this.window_group.add_window (lightbox);
            this.lightboxes.add (lightbox);

            if (this.primary_lightbox == null) {
                this.primary_lightbox = lightbox;
            }

            lightbox.present ();

            return lightbox;
        }

        private void destroy_lightbox (Ft.Lightbox lightbox)
        {
            lightbox.notify["monitor"].disconnect (this.on_lightbox_queue_update);
            lightbox.notify["all-monitors-mode"].disconnect (this.on_lightbox_notify_all_monitors_mode);
            lightbox.notify["fullscreened"].disconnect (this.on_lightbox_notify_fullscreened);
            lightbox.notify["is-active"].disconnect (this.on_lightbox_notify_is_active);
            lightbox.close_request.disconnect (this.on_lightbox_close_request);

            var lightbox_widget = (Gtk.Widget) lightbox;
            lightbox_widget.unrealize.disconnect (this.on_lightbox_unrealize);

            this.lightboxes.remove (lightbox);

            if (this.primary_lightbox == lightbox) {
                this.primary_lightbox = null;
            }

            lightbox.close ();
        }

        private void update_lightboxes ()
        {
            if (this.lightboxes.length == 0)
            {
                this.create_lightbox (null);
                return;
            }

            if (this.get_active_lightbox () == null)
            {
                // Spawning windows per monitor is unreliable while none of the windows
                // is active (e.g. in GNOME Shell overview). Keep only the primary window.
                var primary_lightbox = this.get_primary_lightbox ();

                this.lightboxes.get_values ().@foreach (
                    (lightbox) => {
                        if (lightbox != primary_lightbox) {
                            this.destroy_lightbox (lightbox);
                        }
                    });

                return;
            }

            if (this.lightboxes.length == 1)
            {
                var lightbox = this.get_first_lightbox ();

                if (lightbox.all_monitors_mode ||
                    !lightbox.fullscreened ||
                    lightbox.monitor == null)
                {
                    // Wait until the compositor has placed this window.
                    return;
                }
            }

            var paired_monitors = new GLib.GenericSet<unowned Gdk.Monitor> (
                                        GLib.direct_hash, GLib.direct_equal);
            var paired_lightboxes = new GLib.GenericSet<unowned Ft.Lightbox> (
                                        GLib.direct_hash, GLib.direct_equal);

            this.lightboxes.@foreach (
                (lightbox) => {
                    var lightbox_monitor = lightbox.monitor;

                    // Keep the requested monitor. The compositor can report the
                    // focused output for a new window while leaving the overview;
                    // adopting that output makes the next update destroy the
                    // window and open another one.
                    if (lightbox.monitor_request == null && lightbox_monitor != null) {
                        lightbox.monitor_request = lightbox_monitor;
                    }

                    var claimed_monitor = lightbox.monitor_request;

                    if (claimed_monitor != null &&
                        !paired_monitors.contains (claimed_monitor) &&
                        !paired_lightboxes.contains (lightbox))
                    {
                        paired_monitors.add (claimed_monitor);
                        paired_lightboxes.add (lightbox);
                    }
                });

            var primary_lightbox = this.get_primary_lightbox ();

            this.lightboxes.get_values ().@foreach (
                (lightbox) => {
                    if (lightbox != primary_lightbox &&
                        !paired_lightboxes.contains (lightbox))
                    {
                        this.destroy_lightbox (lightbox);
                    }
                });

            // Spawn windows on unused monitors.
            for (var index = 0U; index < this.monitors.get_n_items (); index++)
            {
                var monitor = (Gdk.Monitor?) this.monitors.get_item (index);

                if (monitor != null && monitor.valid && !paired_monitors.contains (monitor))
                {
                    var lightbox = this.create_lightbox (monitor);
                    paired_monitors.add (monitor);
                    paired_lightboxes.add (lightbox);
                }
            }

            if (paired_monitors.length != paired_lightboxes.length) {
                GLib.warning ("Mismatch between number of windows (%u) and monitors (%u).",
                              paired_lightboxes.length, paired_monitors.length);
            }
        }

        private void update ()
        {
            if (this.closing || this.updating_count > 0 || this.monitors == null) {
                return;
            }

            if (this.update_idle_id != 0) {
                GLib.Source.remove (this.update_idle_id);
                this.update_idle_id = 0;
            }

            this.updating_count++;
            this.update_lightboxes ();
            this.updating_count--;
        }

        private void queue_update ()
        {
            if (this.closing || this.update_idle_id != 0) {
                return;
            }

            this.update_idle_id = GLib.Idle.add (
                () => {
                    this.update_idle_id = 0;
                    this.update ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.update_idle_id, "Ft.LightboxGroup.update");
        }

        private void on_monitors_changed (GLib.ListModel model,
                                          uint           position,
                                          uint           removed,
                                          uint           added)
        {
            // Lightboxes would try to allocate with previous size before monitors changed.
            this.lightboxes.@foreach (
                (lightbox) => {
                    lightbox.queue_resize ();
                });

            this.queue_update ();
        }

        private void on_lightbox_queue_update (GLib.Object    object,
                                               GLib.ParamSpec pspec)
        {
            this.queue_update ();
        }

        private void on_lightbox_notify_all_monitors_mode (GLib.Object    object,
                                                           GLib.ParamSpec pspec)
        {
            unowned var lightbox = (Ft.Lightbox) object;

            if (!lightbox.all_monitors_mode) {
                this.queue_update ();
            }
        }

        private void on_lightbox_notify_fullscreened (GLib.Object    object,
                                                      GLib.ParamSpec pspec)
        {
            unowned var lightbox = (Ft.Lightbox) object;

            if (lightbox.fullscreened) {
                this.queue_update ();
            }
        }

        private void on_lightbox_notify_is_active (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            unowned var lightbox = (Ft.Lightbox) object;

            if (lightbox.is_active)
            {
                // Cancel pending teardown. Open windows on other monitors.
                if (this.deactivate_timeout_id != 0) {
                    GLib.Source.remove (this.deactivate_timeout_id);
                    this.deactivate_timeout_id = 0;
                }

                this.queue_update ();
            }
            else if (this.get_active_lightbox () == null && this.deactivate_timeout_id == 0)
            {
                // Delay closing extra windows: focus moves between our own windows
                // while they steal focus on present().
                this.deactivate_timeout_id = GLib.Timeout.add (
                    DEACTIVATE_TIMEOUT_MS,
                    () => {
                        this.deactivate_timeout_id = 0;
                        this.update ();

                        return GLib.Source.REMOVE;
                    });
                GLib.Source.set_name_by_id (this.deactivate_timeout_id,
                                            "Ft.LightboxGroup.deactivate");
            }
        }

        private bool on_lightbox_close_request (Gtk.Window window)
        {
            if (this.updating_count == 0) {
                this.close ();
            }

            return false;
        }

        private void on_lightbox_unrealize (Gtk.Widget widget)
        {
            this.destroy_lightbox ((Ft.Lightbox) widget);
        }

        public async void open (GLib.Cancellable? cancellable = null) throws GLib.Error
                                requires (this.open_callback == null)
        {
            if (this.monitors == null) {
                this.monitors = Gdk.Display.get_default ()?.get_monitors ();
            }

            if (this.monitors == null) {
                throw new Ft.LightboxError.NO_MONITORS ("Could not list monitors.");
            }

            if (this.monitors_changed_id == 0) {
                this.monitors_changed_id = this.monitors.items_changed.connect (this.on_monitors_changed);
            }

            this.window_group = new Gtk.WindowGroup ();

            this.update ();

            this.open_callback = this.open.callback;

            if (cancellable != null) {
                cancellable.cancelled.connect (this.close);
            }

            yield;

            this.open_callback = null;

            if (this.monitors_changed_id != 0) {
                this.monitors.disconnect (this.monitors_changed_id);
                this.monitors_changed_id = 0;
            }

            this.lightboxes.get_values ().@foreach (
                (lightbox) => {
                    lightbox.close ();
                });
        }

        private void close ()
        {
            if (this.open_callback == null) {
                return;
            }

            this.closing = true;

            if (this.update_idle_id != 0) {
                GLib.Source.remove (this.update_idle_id);
                this.update_idle_id = 0;
            }

            if (this.deactivate_timeout_id != 0) {
                GLib.Source.remove (this.deactivate_timeout_id);
                this.deactivate_timeout_id = 0;
            }

            this.open_callback ();
        }

        public override void dispose ()
        {
            if (this.update_idle_id != 0) {
                GLib.Source.remove (this.update_idle_id);
                this.update_idle_id = 0;
            }

            if (this.deactivate_timeout_id != 0) {
                GLib.Source.remove (this.deactivate_timeout_id);
                this.deactivate_timeout_id = 0;
            }

            if (this.monitors_changed_id != 0) {
                this.monitors.disconnect (this.monitors_changed_id);
                this.monitors_changed_id = 0;
            }

            if (this.lightboxes != null) {
                this.lightboxes.remove_all ();
                this.lightboxes = null;
            }

            this.window_group = null;
            this.monitors = null;
            this.primary_lightbox = null;

            base.dispose ();
        }
    }


    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/overlays/lightbox.ui")]
    public class Lightbox : Gtk.Window, Gtk.Buildable
    {
        private const uint FADE_IN_TIME = 350;
        private const uint FADE_OUT_TIME = 300;
        private const uint FULLSCREEN_LOST_TIMEOUT = 250;

        public Gdk.Monitor? monitor_request
        {
            get {
                return this._monitor_request;
            }
            set {
                this._monitor_request = value;
            }
        }

        public Gdk.Monitor? monitor
        {
            get {
                return this._monitor;
            }
        }

        public Gtk.Widget? contents
        {
            get {
                return this.container.child;
            }
            set {
                var previous_child = this.container.child;

                if (previous_child != null) {
                    previous_child.remove_css_class ("contents");
                }

                this.container.child = value;

                if (value != null) {
                    value.add_css_class ("contents");
                }
            }
        }

        public bool all_monitors_mode
        {
            get {
                return this._all_monitors_mode;
            }
        }

        public bool show_contents
        {
            get {
                return this.container.visible;
            }
            set {
                this.container.visible = value;
            }
        }

        [GtkChild]
        private unowned Adw.Bin container;

        private Gdk.Monitor?                 _monitor_request = null;
        private Gdk.Monitor?                 _monitor = null;
        private GLib.GenericSet<Gdk.Monitor> monitors = null;

        private bool                         _all_monitors_mode = false;
        private bool                         closing = false;
        private uint                         fullscreen_lost_id = 0;
        private Adw.TimedAnimation?          fade_in_animation = null;
        private Adw.TimedAnimation?          fade_out_animation = null;

        private static uint next_id = 0;
        internal uint id = 0;

        static construct
        {
            set_css_name ("lightbox");
            set_auto_startup_notification (false);
        }

        construct
        {
            this.id = next_id;
            next_id++;

            this.monitors = new GLib.GenericSet<Gdk.Monitor> (GLib.direct_hash, GLib.direct_equal);

            this.notify["fullscreened"].connect (this.on_notify_fullscreened);

            var settings = Ft.get_settings ();

            if (settings.get_boolean ("blur-effect") &&
                have_fullscreen_transparency () &&
                have_background_effect ())
            {
                this.remove_css_class ("background");
                this.add_css_class ("blur-effect");
            }
        }

        private void update_monitor ()
        {
            unowned Gdk.Monitor? monitor;

            var layout_manager = (Ft.MonitorConstrainedLayoutManager) this.container.layout_manager;
            var display = this.get_display ();
            var surface = this.get_surface ();
            var surface_monitor = surface != null
                    ? display?.get_monitor_at_surface (surface)
                    : null;
            var primary_monitor = get_primary_monitor (display);

            if (this._all_monitors_mode)
            {
                if (this.monitors.contains (primary_monitor)) {
                    monitor = primary_monitor;
                    layout_manager.monitor = primary_monitor;
                }
                else {
                    monitor = surface_monitor;
                    layout_manager.monitor = surface_monitor;
                }

                this.show_contents = true;
            }
            else {
                monitor = surface_monitor;
                layout_manager.monitor = null;
                this.show_contents = monitor == primary_monitor;
            }

            if (this._monitor != monitor)
            {
                if (this._monitor != null) {
                    this._monitor.notify["valid"].disconnect (this.on_monitor_notify_valid);
                }

                this._monitor = monitor;

                if (this._monitor != null) {
                    this._monitor.notify["valid"].connect (this.on_monitor_notify_valid);
                }

                this.notify_property ("monitor");
            }
        }

        private void remove_invalid_monitors ()
         {
            this.monitors.get_values ().@foreach (
                (monitor) => {
                    if (!monitor.valid) {
                        this.monitors.remove (monitor);
                    }
                });
        }

        private void on_notify_fullscreened (GLib.Object    object,
                                             GLib.ParamSpec pspec)
        {
            if (this.closing) {
                return;
            }

            if (this.fullscreened)
            {
                if (this.fullscreen_lost_id != 0) {
                    GLib.Source.remove (this.fullscreen_lost_id);
                    this.fullscreen_lost_id = 0;
                }

                return;
            }

            // The compositor can clear `fullscreen` for a moment while placing the window.
            // Close only if it sticks.
            if (this.fullscreen_lost_id != 0) {
                return;
            }

            this.fullscreen_lost_id = GLib.Timeout.add (
                FULLSCREEN_LOST_TIMEOUT,
                () => {
                    this.fullscreen_lost_id = 0;

                    if (!this.closing && !this.fullscreened) {
                        GLib.debug ("Failed to make lightbox fullscreen. Closing...");
                        this.close ();
                    }

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.fullscreen_lost_id,
                                        "Ft.Lightbox.fullscreen-lost");
        }

        private void on_monitor_notify_valid (GLib.Object    object,
                                              GLib.ParamSpec pspec)
        {
            if (!monitor.valid) {
                this.queue_allocate();
            }
        }

        private void on_enter_monitor (Gdk.Monitor? monitor)
        {
            if (monitor != null)
            {
                this.monitors.add (monitor);

                this.queue_allocate();
            }

            this.remove_invalid_monitors ();
        }

        private void on_leave_monitor (Gdk.Monitor? monitor)
        {
            if (monitor != null)
            {
                this.monitors.remove (monitor);

                this.queue_allocate();
            }

            this.remove_invalid_monitors ();
        }

        [GtkCallback]
        private bool on_key_pressed (Gtk.EventControllerKey event_controller,
                                     uint                   keyval,
                                     uint                   keycode,
                                     Gdk.ModifierType       state)
        {
            switch (keyval)
            {
                case Gdk.Key.Escape:
                    this.close ();
                    return true;
            }

            return false;
        }

        private bool resolve_all_monitors_mode (int width,
                                                int height)
        {
            if (this._monitor_request != null) {
                return false;
            }

            var display = this.get_display ();
            var display_geometry = get_display_geometry (display);
            var monitors = display.get_monitors ();
            var monitors_count = monitors.get_n_items ();

            if (monitors_count == 0) {
                return false;
            }

            if (monitors_count == 1) {
                return true;
            }

            for (var index = 0; index < monitors.get_n_items (); index++)
            {
                var monitor = (Gdk.Monitor?) monitors.get_item (index);

                if (monitor.valid && !this.monitors.contains (monitor)) {
                    return false;
                }
            }

            return width >= display_geometry.width &&
                   height >= display_geometry.height;
        }

        /**
         * We don't have access to compositor coordinates.
         */
        private void update_all_monitors_mode (int width,
                                               int height)
        {
            var all_monitors_mode = this.resolve_all_monitors_mode (width, height);

            if (this._all_monitors_mode != all_monitors_mode) {
                this._all_monitors_mode = all_monitors_mode;
                this.notify_property ("all-monitors-mode");
            }
        }

        public new void close ()
        {
            this.closing = true;

            if (this.fade_out_animation != null) {
                return;
            }

            var animate = have_fullscreen_transparency ();
            if (!animate || !this.get_mapped ()) {
                base.close ();
                return;
            }

            var opacity_from = this.opacity;

            if (this.fade_in_animation != null) {
                this.fade_in_animation.skip ();
                this.opacity = opacity_from;
            }

            var target = new Adw.PropertyAnimationTarget (this, "opacity");

            this.fade_out_animation = new Adw.TimedAnimation (this,
                                                              opacity_from,
                                                              0.0,
                                                              FADE_OUT_TIME,
                                                              target);
            this.fade_out_animation.set_easing (Adw.Easing.EASE_IN_OUT_CUBIC);
            this.fade_out_animation.done.connect (
                () => {
                    base.close ();
                    this.fade_out_animation = null;
                });
            this.fade_out_animation.play ();
        }

        public override Gtk.SizeRequestMode get_request_mode ()
        {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure (Gtk.Orientation orientation,
                                      int             for_size,
                                      out int         minimum,
                                      out int         natural,
                                      out int         minimum_baseline,
                                      out int         natural_baseline)
        {
            var monitor = this._monitor != null ? this._monitor : this._monitor_request;

            if (this._monitor_request == null && this.monitors.length > 1)
            {
                var display_geometry = get_display_geometry (this.get_display ());

                minimum = natural = orientation == Gtk.Orientation.HORIZONTAL
                        ? display_geometry.width
                        : display_geometry.height;
            }
            else if (monitor != null && this.monitors.length == 1)
            {
                var monitor_geometry = monitor.geometry;

                minimum = natural = orientation == Gtk.Orientation.HORIZONTAL
                        ? monitor_geometry.width
                        : monitor_geometry.height;
            }
            else {
                base.measure (orientation,
                              for_size,
                              out minimum,
                              out natural,
                              out minimum_baseline,
                              out natural_baseline);
            }

            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public override void size_allocate (int width,
                                            int height,
                                            int baseline)
        {
            if (this.monitors.length > 0)
            {
                this.update_all_monitors_mode (width, height);
                this.update_monitor ();

                // Remind the compositor to do full-screen on all monitors.
                var toplevel = (Gdk.Toplevel) this.get_surface ();

                if (this._all_monitors_mode) {
                    toplevel.fullscreen_mode = Gdk.FullscreenMode.ALL_MONITORS;
                    this.fullscreen ();
                }
                else if (this._monitor_request != null &&
                         this._monitor != this._monitor_request) {
                    // Keep requesting the target output until the compositor
                    // places the window there.
                    toplevel.fullscreen_mode = Gdk.FullscreenMode.CURRENT_MONITOR;
                    this.fullscreen_on_monitor (this._monitor_request);
                }
                else if (this._monitor != null) {
                    toplevel.fullscreen_mode = Gdk.FullscreenMode.CURRENT_MONITOR;
                    this.fullscreen_on_monitor (this._monitor);
                }
                else {
                    toplevel.fullscreen_mode = Gdk.FullscreenMode.CURRENT_MONITOR;
                    this.fullscreen ();
                }
            }

            base.size_allocate (width,
                                height,
                                baseline);
        }

        // public override void realize ()
        // {
        //     base.realize ();
        //
        //     var surface = this.get_surface ();
        //     var display = surface?.get_display ();
        //
        //     #if HAVE_GDK_X11
        //     if (display is Gdk.X11.Display)
        //     {
        //         var x11_surface = surface as Gdk.X11.Surface;
        //
        //         x11_surface.set_skip_pager_hint (true);
        //         x11_surface.set_skip_taskbar_hint (true);
        //     }
        //     #endif
        // }

        public override void map ()
        {
            var toplevel = (Gdk.Toplevel) this.get_surface ();
            toplevel.enter_monitor.connect (this.on_enter_monitor);
            toplevel.leave_monitor.connect (this.on_leave_monitor);

            if (this._monitor_request == null) {
                // Request opening window on all monitors. If it fails, open additional windows later.
                toplevel.fullscreen_mode = Gdk.FullscreenMode.ALL_MONITORS;

                this.fullscreen ();
            }
            else {
                this.fullscreen_on_monitor (this._monitor_request);
            }

            var animate = have_fullscreen_transparency ();
            if (animate) {
                this.opacity = 0.0;
            }

            base.map ();

            if (animate)
            {
                var target = new Adw.PropertyAnimationTarget (this, "opacity");

                this.fade_in_animation = new Adw.TimedAnimation (this,
                                                                 0.0,
                                                                 1.0,
                                                                 FADE_IN_TIME,
                                                                 target);
                this.fade_in_animation.set_easing (Adw.Easing.EASE_OUT_QUAD);
                this.fade_in_animation.done.connect (
                    () => {
                        this.fade_in_animation = null;
                    });
                this.fade_in_animation.play ();
            }
        }

        public override void unmap ()
        {
            var toplevel = (Gdk.Toplevel) this.get_surface ();
            toplevel.enter_monitor.disconnect (this.on_enter_monitor);
            toplevel.leave_monitor.disconnect (this.on_leave_monitor);

            base.unmap ();
        }

        public override void dispose ()
        {
            if (this.fullscreen_lost_id != 0) {
                GLib.Source.remove (this.fullscreen_lost_id);
                this.fullscreen_lost_id = 0;
            }

            if (this._monitor != null) {
                this._monitor.notify["valid"].disconnect (this.on_monitor_notify_valid);
            }

            if (this.monitors != null) {
                this.monitors.remove_all ();
                this.monitors = null;
            }

            this.notify["fullscreened"].disconnect (this.on_notify_fullscreened);

            this.fade_in_animation = null;
            this.fade_out_animation = null;
            this._monitor_request = null;
            this._monitor = null;

            base.dispose ();
        }
    }
}
