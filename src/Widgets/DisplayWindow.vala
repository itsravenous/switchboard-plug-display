/*-
 * Copyright 2014-2021 elementary, Inc.
 *
 * This software is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this software; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

public class Display.DisplayWindow : Hdy.Window {
    public Display.VirtualMonitor virtual_monitor { get; construct; }

    private const int SPACING = 12;

    public DisplayWindow (Display.VirtualMonitor virtual_monitor) {
        Object (virtual_monitor: virtual_monitor);
    }

    construct {
        var label = new Gtk.Label (virtual_monitor.get_display_name ()) {
            margin = 12
        };

        add (label);

        input_shape_combine_region (null);
        accept_focus = false;
        decorated = false;
        resizable = false;
        deletable = false;
        can_focus = false;
        skip_taskbar_hint = true;
        skip_pager_hint = true;
        type_hint = Gdk.WindowTypeHint.TOOLTIP;
        set_keep_above (true);

        stick ();

        var scale_factor = get_style_context ().get_scale ();
        move (
            (int) (virtual_monitor.current_x / scale_factor) + SPACING,
            (int) (virtual_monitor.current_y / scale_factor) + SPACING
        );
    }
}
