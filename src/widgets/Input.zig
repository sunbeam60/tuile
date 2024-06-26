const std = @import("std");
const internal = @import("../internal.zig");
const Widget = @import("Widget.zig");
const Vec2 = @import("../Vec2.zig");
const Rect = @import("../Rect.zig");
const events = @import("../events.zig");
const Frame = @import("../render/Frame.zig");
const FocusHandler = @import("FocusHandler.zig");
const LayoutProperties = @import("LayoutProperties.zig");
const Constraints = @import("Constraints.zig");
const display = @import("../display.zig");
const callbacks = @import("callbacks.zig");

pub const Config = struct {
    /// A unique identifier of the widget to be used in `Tuile.findById` and `Widget.findById`.
    id: ?[]const u8 = null,

    /// Text to be used as a placeholder when the input is empty.
    placeholder: []const u8 = "",

    /// Input will call this when its value changes.
    on_value_changed: ?callbacks.Callback([]const u8) = null,

    /// Layout properties of the widget, see `LayoutProperties`.
    layout: LayoutProperties = .{},
};

const Input = @This();

pub usingnamespace Widget.Leaf.Mixin(Input);
pub usingnamespace Widget.Base.Mixin(Input, .widget_base);

widget_base: Widget.Base,

placeholder: []const u8,

on_value_changed: ?callbacks.Callback([]const u8),

value: std.ArrayListUnmanaged(u8),

focus_handler: FocusHandler = .{},

layout_properties: LayoutProperties,

cursor: u32 = 0,

view_start: usize = 0,

pub fn create(config: Config) !*Input {
    const self = try internal.allocator.create(Input);
    self.* = Input{
        .widget_base = try Widget.Base.init(config.id),
        .on_value_changed = config.on_value_changed,
        .placeholder = try internal.allocator.dupe(u8, config.placeholder),
        .value = std.ArrayListUnmanaged(u8){},
        .layout_properties = config.layout,
    };
    return self;
}

pub fn destroy(self: *Input) void {
    self.widget_base.deinit();
    self.value.deinit(internal.allocator);
    internal.allocator.free(self.placeholder);
    internal.allocator.destroy(self);
}

pub fn widget(self: *Input) Widget {
    return Widget.init(self);
}

pub fn setPlaceholder(self: *Input, text: []const u8) !void {
    internal.allocator.free(self.placeholder);
    self.placeholder = try internal.allocator.dupe(u8, text);
}

pub fn setValue(self: *Input, value: []const u8) !void {
    self.value.deinit(internal.allocator);
    self.value = std.ArrayListUnmanaged(u8){};
    try self.value.appendSlice(internal.allocator, value);
    self.cursor = value.len;
}

pub fn render(self: *Input, area: Rect, frame: Frame, theme: display.Theme) !void {
    if (area.height() < 1) {
        return;
    }
    frame.setStyle(area, .{ .bg = theme.interactive, .add_effect = .{ .underline = true } });
    self.focus_handler.render(area, frame, theme);

    const render_placeholder = self.value.items.len == 0;
    if (render_placeholder) frame.setStyle(area, .{ .fg = theme.text_secondary });

    const text_to_render = self.currentText();
    const visible = text_to_render[self.view_start..];
    _ = try frame.writeSymbols(area.min, visible, area.width());

    if (self.focus_handler.focused) {
        var cursor_pos = area.min;
        cursor_pos.x += @intCast(self.cursor - self.view_start);
        if (cursor_pos.x >= area.max.x) {
            cursor_pos.x = area.max.x - 1;
        }
        const end_area = Rect{
            .min = cursor_pos,
            .max = cursor_pos.add(.{ .x = 1, .y = 1 }),
        };
        frame.setStyle(end_area, .{
            .bg = theme.solid,
        });
    }
}

pub fn layout(self: *Input, constraints: Constraints) !Vec2 {
    if (self.cursor < self.view_start) {
        self.view_start = self.cursor;
    } else {
        // +1 is for the cursor itself
        const max_width = std.math.clamp(self.layout_properties.max_width, constraints.min_width, constraints.max_width);
        const visible = self.cursor - self.view_start + 1;
        if (visible > max_width) {
            self.view_start += visible - max_width;
        }
    }

    const visible = self.visibleText();
    // +1 for the cursor
    const len = try std.unicode.utf8CountCodepoints(visible) + 1;

    var size = Vec2{
        .x = @intCast(len),
        .y = 1,
    };

    const self_constraints = Constraints.fromProps(self.layout_properties);
    size = self_constraints.apply(size);
    size = constraints.apply(size);
    return size;
}

pub fn handleEvent(self: *Input, event: events.Event) !events.EventResult {
    if (self.focus_handler.handleEvent(event) == .consumed) {
        return .consumed;
    }

    switch (event) {
        .key, .shift_key => |key| switch (key) {
            .Left => {
                self.cursor -|= 1;
                return .consumed;
            },
            .Right => {
                if (self.cursor < self.value.items.len) {
                    self.cursor += 1;
                }
                return .consumed;
            },
            .Backspace => {
                if (self.cursor > 0) {
                    _ = self.value.orderedRemove(self.cursor - 1);
                    if (self.on_value_changed) |cb| cb.call(self.value.items);
                }
                self.cursor -|= 1;
                return .consumed;
            },
            .Delete => {
                if (self.cursor < self.value.items.len) {
                    _ = self.value.orderedRemove(self.cursor);
                    if (self.on_value_changed) |cb| cb.call(self.value.items);
                }
                return .consumed;
            },
            else => {},
        },

        .char => |char| {
            try self.value.insert(internal.allocator, self.cursor, char);
            if (self.on_value_changed) |cb| cb.call(self.value.items);
            self.cursor += 1;
            return .consumed;
        },
        else => {},
    }
    return .ignored;
}

fn currentText(self: *Input) []const u8 {
    const show_placeholder = self.value.items.len == 0;
    return if (show_placeholder) self.placeholder else self.value.items;
}

fn visibleText(self: *Input) []const u8 {
    return self.currentText()[self.view_start..];
}

pub fn layoutProps(self: *Input) LayoutProperties {
    return self.layout_properties;
}
