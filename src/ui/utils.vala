/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    internal Gdk.RGBA blend_colors (Gdk.RGBA background_color,
                                    Gdk.RGBA foreground_color)
    {
        var alpha = foreground_color.alpha;

        return Gdk.RGBA () {
            red   = (1.0f - alpha) * background_color.red   + alpha * foreground_color.red,
            green = (1.0f - alpha) * background_color.green + alpha * foreground_color.green,
            blue  = (1.0f - alpha) * background_color.blue  + alpha * foreground_color.blue,
            alpha = background_color.alpha + (1.0f - background_color.alpha) * alpha,
        };
    }


    /**
     * Calculate relative luminance of a color according to WCAG 2.0
     * https://www.w3.org/TR/WCAG20/#relativeluminancedef
     */
    internal float get_color_luminance (Gdk.RGBA color)
    {
        var r = color.red <= 0.03928f ? color.red / 12.92f : (float) Math.pow ((color.red + 0.055f) / 1.055f, 2.4);
        var g = color.green <= 0.03928f ? color.green / 12.92f : (float) Math.pow ((color.green + 0.055f) / 1.055f, 2.4);
        var b = color.blue <= 0.03928f ? color.blue / 12.92f : (float) Math.pow ((color.blue + 0.055f) / 1.055f, 2.4);

        return 0.2126f * r + 0.7152f * g + 0.0722f * b;
    }


    /**
     * Deduce background color from foreground color based on luminance.
     *
     * If foreground is dark (luminance < 0.5), assume light background (98% luminance).
     * If foreground is bright, assume darker background (20% luminance).
     */
    internal Gdk.RGBA get_background_color (Gdk.RGBA foreground_color)
    {
        var foreground_luminance = get_color_luminance (foreground_color);
        var background_luminance = foreground_luminance < 0.5f ? 0.98f : 0.20f;

        return Gdk.RGBA () {
            red   = background_luminance,
            green = background_luminance,
            blue  = background_luminance,
            alpha = 1.0f
        };
    }


    /**
     * Compute primary color for charts from a foreground color.
     * The primary color is basically a foreground color with no alpha.
     */
    internal Gdk.RGBA get_chart_primary_color (Gdk.RGBA foreground_color)
    {
        var background_color = get_background_color (foreground_color);

        return blend_colors (background_color, foreground_color);
    }


    /**
     * Compute secondary color for charts from a foreground color.
     */
    internal Gdk.RGBA get_chart_secondary_color (Gdk.RGBA foreground_color)
    {
        var secondary_color = get_chart_primary_color (foreground_color);
        secondary_color.alpha *= 0.2f;

        return secondary_color;
    }


    public unowned Gtk.Widget? get_child_by_buildable_id (Gtk.Widget widget,
                                                          string     buildable_id)
    {
        unowned var child = widget.get_first_child ();

        while (child != null)
        {
            if (child.get_buildable_id () == buildable_id) {
                return child;
            }

            unowned var nested_child = get_child_by_buildable_id (child, buildable_id);
            if (nested_child != null) {
                return nested_child;
            }

            child = child.get_next_sibling ();
        }

        return null;
    }


    internal string capitalize_words (string text)
    {
        var string_builder = new GLib.StringBuilder ();
        var capitalize_next = true;
        int index = 0;
        unichar chr;

        while (text.get_next_char (ref index, out chr))
        {
            if (chr == ' ') {
                string_builder.append_unichar (chr);
                capitalize_next = true;
            }
            else if (capitalize_next && chr.islower ()) {
                string_builder.append_unichar (chr.toupper ());
                capitalize_next = false;
            }
            else {
                string_builder.append_unichar (chr);
                capitalize_next = false;
            }
        }

        return string_builder.str;
    }


    /**
     * Function to get xdg-desktop-portal compatible window ID
     *
     * https://flatpak.github.io/xdg-desktop-portal/docs/window-identifiers.html
     */
    internal async string get_window_identifier (Gtk.Window? window)
    {
        var surface = window?.get_surface ();
        var display = surface?.get_display ();

        #if HAVE_GDK_WAYLAND
        if (display is Gdk.Wayland.Display)
        {
            var wayland_toplevel = surface as Gdk.Wayland.Toplevel;
            string? handle = null;

            if (wayland_toplevel != null)
            {
                var wait_for_handle = wayland_toplevel.export_handle (
                    (_toplevel, _handle) => {
                        handle = _handle;
                        get_window_identifier.callback ();
                    });
                if (wait_for_handle) {
                    yield;
                }

                return handle != null
                        ? @"wayland:$(handle)"
                        : "";
            }
        }
        #endif

        // TODO: test this
        #if HAVE_GDK_X11
        if (display is Gdk.X11.Display)
        {
            var x11_surface = surface as Gdk.X11.Surface;

            if (x11_surface != null) {
                var xid = (int) x11_surface.get_xid ();

                return @"x11:$(xid)";
            }
        }
        #endif

        return "";
    }


    internal inline Gtk.Orientation get_opposite_orientation (Gtk.Orientation orientation)
    {
        return orientation == Gtk.Orientation.HORIZONTAL
                ? Gtk.Orientation.VERTICAL
                : Gtk.Orientation.HORIZONTAL;
    }


    internal void normalize_rectangle (ref Gdk.Rectangle rect)
    {
        if (rect.width < 0) {
            rect.x += rect.width;
            rect.width = rect.width.abs ();
        }

        if (rect.height < 0) {
            rect.y += rect.height;
            rect.height = rect.height.abs ();
        }
    }
}
