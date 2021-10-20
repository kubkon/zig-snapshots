const Svg = @This();

const std = @import("std");
const mem = std.mem;

const Allocator = mem.Allocator;

pub const Element = struct {
    const Tag = enum {
        line,
        rect,
        text,
    };

    pub const Line = struct {
        const base_tag: Svg.Element.Tag = .line;

        base: Svg.Element,
        x1: usize,
        y1: usize,
        x2: usize,
        y2: usize,

        pub fn new(allocator: *Allocator, opts: struct {
            x1: usize = 0,
            y1: usize = 0,
            x2: usize = 0,
            y2: usize = 0,
        }) !*Line {
            const self = try allocator.create(Line);
            self.* = .{
                .base = .{ .tag = .line },
                .x1 = opts.x1,
                .y1 = opts.y1,
                .x2 = opts.x2,
                .y2 = opts.y2,
            };
            return self;
        }

        pub fn render(self: Line, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("<line x1='{d}' y1='{d}' x2='{d}' y2='{d}' ", .{
                self.x1,
                self.y1,
                self.x2,
                self.y2,
            });
            if (self.base.css.items.len > 0) {
                try writer.writeAll("class='");
                for (self.base.css.items) |class| {
                    try writer.print("{s} ", .{class});
                }
                try writer.writeAll("'");
            }
            try writer.writeAll("/>\n");
        }
    };

    pub const Rect = struct {
        const base_tag: Svg.Element.Tag = .rect;

        base: Svg.Element,
        x: usize,
        y: usize,
        width: usize,
        height: usize,

        pub fn new(allocator: *Allocator, opts: struct {
            x: usize = 0,
            y: usize = 0,
            width: usize = 0,
            height: usize = 0,
        }) !*Rect {
            const self = try allocator.create(Rect);
            self.* = .{
                .base = .{ .tag = .rect },
                .x = opts.x,
                .y = opts.y,
                .width = opts.width,
                .height = opts.height,
            };
            return self;
        }

        pub fn render(self: Rect, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("<rect x='{d}' y='{d}' width='{d}' height='{d}' ", .{
                self.x,
                self.y,
                self.width,
                self.height,
            });
            if (self.base.css.items.len > 0) {
                try writer.writeAll("class='");
                for (self.base.css.items) |class| {
                    try writer.print("{s} ", .{class});
                }
                try writer.writeAll("'");
            }
            try writer.writeAll("/>\n");
        }
    };

    pub const Text = struct {
        const base_tag: Svg.Element.Tag = .text;

        base: Svg.Element,
        x: usize,
        y: usize,
        contents: ?[]const u8,

        pub fn new(allocator: *Allocator, opts: struct {
            x: usize = 0,
            y: usize = 0,
            contents: ?[]const u8 = null,
        }) !*Text {
            const self = try allocator.create(Text);
            self.* = .{
                .base = .{ .tag = .text },
                .x = opts.x,
                .y = opts.y,
                .contents = opts.contents,
            };
            return self;
        }

        pub fn render(self: Text, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("<text x='{d}' y='{d}' ", .{ self.x, self.y });
            if (self.base.css.items.len > 0) {
                try writer.writeAll("class='");
                for (self.base.css.items) |class| {
                    try writer.print("{s} ", .{class});
                }
                try writer.writeAll("' ");
            }
            if (self.contents) |contents| {
                try writer.print(">{s}</text>\n", .{contents});
            } else {
                try writer.writeAll("/>\n");
            }
        }
    };

    tag: Tag,
    css: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(base: *Element, allocator: *Allocator) void {
        base.css.deinit(allocator);
    }

    pub fn render(base: *Element, writer: anytype) @TypeOf(writer).Error!void {
        return switch (base.tag) {
            .line => @fieldParentPtr(Line, "base", base).render(writer),
            .rect => @fieldParentPtr(Rect, "base", base).render(writer),
            .text => @fieldParentPtr(Text, "base", base).render(writer),
        };
    }

    pub fn cast(base: *Element, comptime T: type) ?*T {
        if (T.base_tag != base.tag) return null;
        return @fieldParentPtr(T, "base", base);
    }
};

height: usize,
width: usize,
children: std.ArrayListUnmanaged(*Element) = .{},

pub fn deinit(self: *Svg, allocator: *Allocator) void {
    for (self.children.items) |child| {
        child.deinit(allocator);
    }
    self.children.deinit(allocator);
}

pub fn render(self: Svg, writer: anytype) @TypeOf(writer).Error!void {
    try writer.print("<svg height='{d}' width='{d}'>\n", .{ self.height, self.width });
    for (self.children.items) |child| {
        try child.render(writer);
    }
    try writer.writeAll("</svg>\n");
}
