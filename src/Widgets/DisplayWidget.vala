/*-
 * Copyright 2014–2021 elementary, Inc.
 *           2014–2018 Corentin Noël <corentin@elementary.io>
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
 */

public struct Display.Resolution {
    int width;
    int height;
    int aspect;
    bool is_preferred;
    bool is_current;
}

public class Display.DisplayWidget : Gtk.EventBox {
    public signal void set_as_primary ();
    public signal void move_display (double diff_x, double diff_y);
    public signal void end_grab (int delta_x, int delta_y);
    public signal void check_position ();
    public signal void configuration_changed ();
    public signal void active_changed ();

    public Display.VirtualMonitor virtual_monitor { get; construct; }

    public double window_ratio { get; private set; default = 1.0; }
    public int delta_x { get; set; default = 0; }
    public int delta_y { get; set; default = 0; }
    public bool only_display { get; set; default = false; }

    private double start_x = 0;
    private double start_y = 0;
    private bool holding = false;

    public DisplayWindow display_window { get; private set; }
    public Gtk.Button primary_image { get; private set; }
    public Gtk.MenuButton toggle_settings { get; private set; }

    private Gtk.Switch use_switch;

    private Gtk.ComboBox resolution_combobox;
    private Gtk.TreeStore resolution_tree_store;

    private Gtk.ComboBox rotation_combobox;
    private Gtk.ListStore rotation_list_store;

    private Gtk.ComboBox refresh_combobox;
    private Gtk.ListStore refresh_list_store;

    private int real_width = 0;
    private int real_height = 0;

    private enum ResolutionColumns {
        NAME,
        WIDTH,
        HEIGHT,
        TOTAL
    }

    private enum RotationColumns {
        NAME,
        VALUE,
        TOTAL
    }

    private enum RefreshColumns {
        NAME,
        VALUE,
        TOTAL
    }

    public DisplayWidget (Display.VirtualMonitor virtual_monitor) {
        Object (virtual_monitor: virtual_monitor);
    }

    construct {
        events |= Gdk.EventMask.BUTTON_PRESS_MASK;
        events |= Gdk.EventMask.BUTTON_RELEASE_MASK;
        events |= Gdk.EventMask.POINTER_MOTION_MASK;

        display_window = new DisplayWindow (virtual_monitor) {
            attached_to = this
        };

        virtual_monitor.get_current_mode_size (out real_width, out real_height);

        primary_image = new Gtk.Button.from_icon_name ("non-starred-symbolic", Gtk.IconSize.MENU) {
            halign = Gtk.Align.START,
            valign = Gtk.Align.START,
            margin = 6
        };
        primary_image.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
        primary_image.clicked.connect (() => set_as_primary ());

        var virtual_monitor_name = virtual_monitor.get_display_name ();
        var label = new Gtk.Label (virtual_monitor_name) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            expand = true
        };

        var use_label = new Gtk.Label (_("Use this display:")) {
            halign = Gtk.Align.END
        };

        use_switch = new Gtk.Switch () {
            halign = Gtk.Align.START
        };

        virtual_monitor.bind_property ("is-active", use_switch, "active", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);

        var resolution_label = new Gtk.Label (_("Resolution:")) {
            halign = Gtk.Align.END
        };

        resolution_tree_store = new Gtk.TreeStore (ResolutionColumns.TOTAL, typeof (string), typeof (int), typeof (int));
        resolution_combobox = new Gtk.ComboBox.with_model (resolution_tree_store);

        var text_renderer = new Gtk.CellRendererText ();
        resolution_combobox.pack_start (text_renderer, true);
        resolution_combobox.add_attribute (text_renderer, "text", ResolutionColumns.NAME);

        var rotation_label = new Gtk.Label (_("Screen Rotation:")) {
            halign = Gtk.Align.END
        };

        rotation_list_store = new Gtk.ListStore (RotationColumns.TOTAL, typeof (string), typeof (int));
        rotation_combobox = new Gtk.ComboBox.with_model (rotation_list_store);

        text_renderer = new Gtk.CellRendererText ();
        rotation_combobox.pack_start (text_renderer, true);
        rotation_combobox.add_attribute (text_renderer, "text", RotationColumns.NAME);

        var refresh_label = new Gtk.Label (_("Refresh Rate:")) {
            halign = Gtk.Align.END
        };

        refresh_list_store = new Gtk.ListStore (RefreshColumns.TOTAL, typeof (string), typeof (Display.MonitorMode));
        refresh_combobox = new Gtk.ComboBox.with_model (refresh_list_store);

        text_renderer = new Gtk.CellRendererText ();
        refresh_combobox.pack_start (text_renderer, true);
        refresh_combobox.add_attribute (text_renderer, "text", RefreshColumns.NAME);

        for (int i = 0; i <= DisplayTransform.FLIPPED_ROTATION_270; i++) {
            Gtk.TreeIter iter;
            rotation_list_store.append (out iter);
            rotation_list_store.set (iter, RotationColumns.NAME, ((DisplayTransform) i).to_string (), RotationColumns.VALUE, i);
        }

        // Build resolution menu
        // First, get list of unique resolutions from available modes.
        Resolution[] resolutions = {};
        Resolution[] recommended_resolutions = {};
        Resolution[] other_resolutions = {};
        int max_width = -1;
        int max_height = -1;
        uint usable_resolutions = 0;
        int current_width, current_height;
        virtual_monitor.get_current_mode_size (out current_width, out current_height);
        var resolution_set = new Gee.TreeSet<Display.MonitorMode> (Display.MonitorMode.resolution_compare_func);
        foreach (var mode in virtual_monitor.get_available_modes ()) {
            resolution_set.add (mode); // Ensures resolutions unique and sorted
        }

        foreach (var mode in resolution_set) {
            var mode_width = mode.width;
            var mode_height = mode.height;
            if (mode.is_preferred) {
                max_width = int.max (max_width, mode_width);
                max_height = int.max (max_height, mode_height);
            }

            Resolution res = {mode_width, mode_height, mode_width * 10 / mode_height, mode.is_preferred, mode.is_current};
            resolutions += res;
        }

        var native_ratio = max_width * 10 / max_height;
         // Split resolutions into recommended and other
         foreach (var resolution in resolutions) {
             // Reject all resolutions incompatible with elementary desktop
             if (resolution.width < 1024 || resolution.height < 768) {
                continue;
            }

            if (resolution.is_preferred || resolution.is_current || resolution.aspect == native_ratio) {
                recommended_resolutions += resolution;
            } else {
                other_resolutions += resolution;
            }

            usable_resolutions++;
        }

        foreach (var resolution in recommended_resolutions) {
            Gtk.TreeIter iter;
            resolution_tree_store.append (out iter, null);
            resolution_tree_store.set (iter,
                ResolutionColumns.NAME, MonitorMode.get_resolution_string (resolution.width, resolution.height, false),
                ResolutionColumns.WIDTH, resolution.width,
                ResolutionColumns.HEIGHT, resolution.height
            );
        }

        if (other_resolutions.length > 0) {
            Gtk.TreeIter iter;
            Gtk.TreeIter parent_iter;
            resolution_tree_store.append (out parent_iter, null);
            resolution_tree_store.set (parent_iter, ResolutionColumns.NAME, _("Other…"),
                ResolutionColumns.WIDTH, -1,
                ResolutionColumns.HEIGHT, -1
            );

            foreach (var resolution in other_resolutions) {
                resolution_tree_store.append (out iter, parent_iter);
                resolution_tree_store.set (iter,
                    ResolutionColumns.NAME, Display.MonitorMode.get_resolution_string (resolution.width, resolution.height, true),
                    ResolutionColumns.WIDTH, resolution.width,
                    ResolutionColumns.HEIGHT, resolution.height
                );
            }
        }

        if (!set_active_resolution_from_current_mode ()) {
            resolution_combobox.set_active (0);
        }

        resolution_combobox.sensitive = usable_resolutions > 1;

        populate_refresh_rates ();

        var popover_grid = new Gtk.Grid () {
            column_spacing = 12,
            row_spacing = 6,
            margin = 12
        };
        popover_grid.attach (use_label, 0, 0);
        popover_grid.attach (use_switch, 1, 0);
        popover_grid.attach (resolution_label, 0, 1);
        popover_grid.attach (resolution_combobox, 1, 1);
        popover_grid.attach (rotation_label, 0, 2);
        popover_grid.attach (rotation_combobox, 1, 2);
        popover_grid.attach (refresh_label, 0, 3);
        popover_grid.attach (refresh_combobox, 1, 3);
        popover_grid.show_all ();

        var popover = new Gtk.Popover (toggle_settings) {
            position = Gtk.PositionType.BOTTOM
        };
        popover.add (popover_grid);

        toggle_settings = new Gtk.MenuButton () {
            halign = Gtk.Align.END,
            valign = Gtk.Align.START,
            image = new Gtk.Image.from_icon_name ("open-menu-symbolic", Gtk.IconSize.MENU),
            margin = 6,
            popover = popover,
            tooltip_text = _("Configure display")
        };
        toggle_settings.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);

        var grid = new Gtk.Grid ();
        grid.attach (primary_image, 0, 0);
        grid.attach (toggle_settings, 2, 0);
        grid.attach (label, 0, 0, 3, 2);

        set_primary (virtual_monitor.primary);
        add (grid);

        destroy.connect (() => display_window.destroy ());

        use_switch.bind_property ("active", resolution_combobox, "sensitive");
        use_switch.bind_property ("active", rotation_combobox, "sensitive");
        use_switch.bind_property ("active", refresh_combobox, "sensitive");

        use_switch.notify["active"].connect (() => {
            if (rotation_combobox.active == -1) rotation_combobox.set_active (0);
            if (resolution_combobox.active == -1) resolution_combobox.set_active (0);
            if (refresh_combobox.active == -1) refresh_combobox.set_active (0);

            if (use_switch.active) {
                get_style_context ().remove_class ("disabled");
            } else {
                get_style_context ().add_class ("disabled");
            }

            configuration_changed ();
            active_changed ();
        });

        if (!virtual_monitor.is_active) {
            get_style_context ().add_class ("disabled");
        }

        resolution_combobox.changed.connect (() => {
            int active_width, active_height;
            Gtk.TreeIter iter;
            if (resolution_combobox.get_active_iter (out iter)) {
                resolution_tree_store.get (iter,
                    ResolutionColumns.WIDTH, out active_width,
                    ResolutionColumns.HEIGHT, out active_height
                );
            } else {
                return;
            }

            set_geometry (virtual_monitor.x, virtual_monitor.y, active_width, active_height);
            var new_mode = virtual_monitor.get_mode_for_resolution (active_width, active_height);
            if (new_mode == null) {
                return;
            }

            virtual_monitor.set_current_mode (new_mode);
            rotation_combobox.set_active (0);
            populate_refresh_rates ();
            configuration_changed ();
            check_position ();
        });

        rotation_combobox.changed.connect (() => {
            Value val;
            Gtk.TreeIter iter;
            rotation_combobox.get_active_iter (out iter);
            rotation_list_store.get_value (iter, RotationColumns.VALUE, out val);

            var transform = (DisplayTransform)((int)val);
            virtual_monitor.transform = transform;

            switch (transform) {
                case DisplayTransform.NORMAL:
                    virtual_monitor.get_current_mode_size (out real_width, out real_height);
                    label.angle = 0;
                    label.label = virtual_monitor_name;
                    break;
                case DisplayTransform.ROTATION_90:
                    virtual_monitor.get_current_mode_size (out real_height, out real_width);
                    label.angle = 270;
                    label.label = virtual_monitor_name;
                    break;
                case DisplayTransform.ROTATION_180:
                    virtual_monitor.get_current_mode_size (out real_width, out real_height);
                    label.angle = 180;
                    label.label = virtual_monitor_name;
                    break;
                case DisplayTransform.ROTATION_270:
                    virtual_monitor.get_current_mode_size (out real_height, out real_width);
                    label.angle = 90;
                    label.label = virtual_monitor_name;
                    break;
                case DisplayTransform.FLIPPED:
                    virtual_monitor.get_current_mode_size (out real_width, out real_height);
                    label.angle = 0;
                    label.label = virtual_monitor_name.reverse (); //mirroring simulation, because we can't really mirror the text
                    break;
                case DisplayTransform.FLIPPED_ROTATION_90:
                    virtual_monitor.get_current_mode_size (out real_height, out real_width);
                    label.angle = 270;
                    label.label = virtual_monitor_name.reverse ();
                    break;
                case DisplayTransform.FLIPPED_ROTATION_180:
                    virtual_monitor.get_current_mode_size (out real_width, out real_height);
                    label.angle = 180;
                    label.label = virtual_monitor_name.reverse ();
                    break;
                case DisplayTransform.FLIPPED_ROTATION_270:
                    virtual_monitor.get_current_mode_size (out real_height, out real_width);
                    label.angle = 90;
                    label.label = virtual_monitor_name.reverse ();
                    break;
            }

            configuration_changed ();
            check_position ();
        });

        refresh_combobox.changed.connect (() => {
            Value val;
            Gtk.TreeIter iter;
            if (refresh_combobox.get_active_iter (out iter)) {
                refresh_list_store.get_value (iter, RefreshColumns.VALUE, out val);
                Display.MonitorMode new_mode = (Display.MonitorMode) val;
                virtual_monitor.set_current_mode (new_mode);
                rotation_combobox.set_active (0);
                configuration_changed ();
                check_position ();
            }
        });

        rotation_combobox.set_active ((int) virtual_monitor.transform);
        on_vm_transform_changed ();

        virtual_monitor.modes_changed.connect (on_monitor_modes_changed);
        virtual_monitor.notify["transform"].connect (on_vm_transform_changed);

        configuration_changed ();
        check_position ();
    }

    private void populate_refresh_rates () {
        refresh_list_store.clear ();

        Gtk.TreeIter iter;
        int added = 0;
        if (resolution_combobox.get_active_iter (out iter)) {
            int active_width, active_height;
            if (resolution_combobox.get_active_iter (out iter)) {
                resolution_tree_store.get (iter,
                    ResolutionColumns.WIDTH, out active_width,
                    ResolutionColumns.HEIGHT, out active_height
                );
            } else {
                return;
            }

            double[] frequencies = {};
            bool refresh_set = false;
            foreach (var mode in virtual_monitor.get_available_modes ()) {
                if (mode.width != active_width || mode.height != active_height) {
                    continue;
                }

                if (mode.frequency in frequencies) {
                    continue;
                }

                bool freq_already_added = false;
                foreach (var freq in frequencies) {
                    if ((mode.frequency - freq).abs () < 1) {
                        freq_already_added = true;
                        break;
                    }
                }

                if (freq_already_added) {
                    continue;
                }

                frequencies += mode.frequency;

                var freq_name = _("%g Hz").printf (Math.roundf ((float)mode.frequency));
                refresh_list_store.append (out iter);
                refresh_list_store.set (iter, ResolutionColumns.NAME, freq_name, RefreshColumns.VALUE, mode);
                added++;
                if (mode.is_current) {
                    refresh_combobox.set_active_iter (iter);
                    refresh_set = true;
                }
            }

            if (!refresh_set) {
                refresh_combobox.set_active (0);
            }
        }

        refresh_combobox.sensitive = added > 1;
    }

    private void on_monitor_modes_changed () {
        set_active_resolution_from_current_mode ();
    }

    private bool set_active_resolution_from_current_mode () {
        bool result = false;
        foreach (var mode in virtual_monitor.get_available_modes ()) {
            if (!mode.is_current) {
                continue;
            }

            resolution_tree_store.@foreach ((model, path, iter) => {
                int width, height;
                resolution_tree_store.get (iter,
                    ResolutionColumns.WIDTH, out width,
                    ResolutionColumns.HEIGHT, out height
                );
                if (mode.width == width && mode.height == height) {
                    resolution_combobox.set_active_iter (iter);
                    result = true;
                    return true;
                }

                return false;
            });
        }

        return result;
    }

    private void on_vm_transform_changed () {
        var transform = virtual_monitor.transform;
        rotation_list_store.@foreach ((model, path, iter) => {
            Value val;
            rotation_list_store.get_value (iter, RotationColumns.VALUE, out val);

            var iter_transform = (DisplayTransform)((int)val);
            if (iter_transform == transform) {
                rotation_combobox.set_active_iter (iter);
                return true;
            }

            return false;
        });
    }

    public override bool button_press_event (Gdk.EventButton event) {
        if (only_display) {
            return false;
        }

        start_x = event.x_root;
        start_y = event.y_root;
        holding = true;
        return false;
    }

    public override bool button_release_event (Gdk.EventButton event) {
        holding = false;
        if ((delta_x == 0 && delta_y == 0) || only_display) {
            return false;
        }

        var old_delta_x = delta_x;
        var old_delta_y = delta_y;
        delta_x = 0;
        delta_y = 0;
        end_grab (old_delta_x, old_delta_y);
        return false;
    }

    public override bool motion_notify_event (Gdk.EventMotion event) {
        if (holding && !only_display) {
            move_display (event.x_root - start_x, event.y_root - start_y);
        }

        return false;
    }

    public void set_primary (bool is_primary) {
        if (is_primary) {
            ((Gtk.Image) primary_image.image).icon_name = "starred-symbolic";
            primary_image.tooltip_text = _("Is the primary display");
        } else {
            ((Gtk.Image) primary_image.image).icon_name = "non-starred-symbolic";
            primary_image.tooltip_text = _("Set as primary display");
        }

        use_switch.sensitive = !is_primary;
    }

    public override void get_preferred_width (out int minimum_width, out int natural_width) {
        minimum_width = (int)(real_width * window_ratio);
        natural_width = minimum_width;
    }

    public override void get_preferred_height (out int minimum_height, out int natural_height) {
        minimum_height = (int)(real_height * window_ratio);
        natural_height = minimum_height;
    }

    public void get_geometry (out int x, out int y, out int width, out int height) {
        x = virtual_monitor.x;
        y = virtual_monitor.y;
        width = real_width;
        height = real_height;
    }

    public void set_geometry (int x, int y, int width, int height) {
        virtual_monitor.x = x;
        virtual_monitor.y = y;
        real_width = width;
        real_height = height;
    }

    public bool equals (DisplayWidget sibling) {
        return virtual_monitor.id == sibling.virtual_monitor.id;
    }
}
