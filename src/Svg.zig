const Svg = @This();

const std = @import("std");
const mem = std.mem;

const Allocator = mem.Allocator;

pub const Element = struct {
    const Tag = enum {
        raw,
        group,
        path,
        line,
        rect,
        text,
    };

    pub const Raw = struct {
        const base_tag: Svg.Element.Tag = .raw;

        base: Svg.Element,
        tag: []const u8,
        attrs: std.ArrayListUnmanaged([]const u8) = .{},
        children: std.ArrayListUnmanaged(*Svg.Element) = .{},

        pub fn new(allocator: *Allocator, tag: []const u8) !*Raw {
            const self = try allocator.create(Raw);
            self.* = .{
                .base = .{ .tag = .raw },
                .tag = tag,
            };
            return self;
        }

        pub fn deinit(self: *Raw, allocator: *Allocator) void {
            self.attrs.deinit(allocator);
            for (self.children.items) |child| {
                child.deinit(allocator);
            }
            self.children.deinit(allocator);
        }

        pub fn render(self: Raw, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("<{s} ", .{self.tag});
            for (self.attrs.items) |attr| {
                try writer.print("{s} ", .{attr});
            }
            try writer.writeAll(">");
            for (self.children.items) |child| {
                try child.render(writer);
            }
            try writer.print("</{s}>", .{self.tag});
        }
    };

    pub const Group = struct {
        const base_tag: Svg.Element.Tag = .group;

        base: Svg.Element,
        children: std.ArrayListUnmanaged(*Svg.Element) = .{},

        pub fn new(allocator: *Allocator) !*Group {
            const self = try allocator.create(Group);
            self.* = .{
                .base = .{ .tag = .group },
            };
            return self;
        }

        pub fn deinit(self: *Group, allocator: *Allocator) void {
            for (self.children.items) |child| {
                child.deinit(allocator);
            }
            self.children.deinit(allocator);
        }

        pub fn render(self: Group, writer: anytype) @TypeOf(writer).Error!void {
            try writer.writeAll("<g ");
            try self.base.renderImpl(writer);
            try writer.writeAll(">");
            for (self.children.items) |child| {
                try child.render(writer);
            }
            try writer.writeAll("</g>");
        }
    };

    pub const Path = struct {
        const base_tag: Svg.Element.Tag = .path;

        base: Svg.Element,
        x1: ?usize,
        y1: ?usize,
        x2: ?usize,
        y2: ?usize,
        d: std.ArrayListUnmanaged(u8) = .{},

        pub fn new(allocator: *Allocator, opts: struct {
            x1: ?usize = null,
            y1: ?usize = null,
            x2: ?usize = null,
            y2: ?usize = null,
            d: ?[]const u8 = null,
        }) !*Path {
            const self = try allocator.create(Path);
            self.* = .{
                .base = .{ .tag = .path },
                .x1 = opts.x1,
                .y1 = opts.y1,
                .x2 = opts.x2,
                .y2 = opts.y2,
            };
            if (opts.d) |d| {
                try self.d.appendSlice(allocator, d);
            }
            return self;
        }

        pub fn moveTo(self: *Path, allocator: *Allocator, x: usize, y: usize) !void {
            const d = try std.fmt.allocPrint(allocator, "M {d} {d} ", .{ x, y });
            defer allocator.free(d);
            try self.d.appendSlice(allocator, d);
        }

        pub fn lineTo(self: *Path, allocator: *Allocator, x: usize, y: usize) !void {
            const d = try std.fmt.allocPrint(allocator, "L {d} {d} ", .{ x, y });
            defer allocator.free(d);
            try self.d.appendSlice(allocator, d);
        }

        pub fn deinit(self: *Path, allocator: *Allocator) void {
            self.d.deinit(allocator);
        }

        pub fn render(self: Path, writer: anytype) @TypeOf(writer).Error!void {
            try writer.print("<path d='{s}' ", .{self.d.items});
            if (self.x1) |x1| {
                try writer.print("x1={d} ", .{x1});
            }
            if (self.y1) |y1| {
                try writer.print("y1={d} ", .{y1});
            }
            if (self.x2) |x2| {
                try writer.print("x2={d} ", .{x2});
            }
            if (self.y2) |y2| {
                try writer.print("y2={d} ", .{y2});
            }
            try self.base.renderImpl(writer);
            try writer.writeAll("/>");
        }
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
            try self.base.renderImpl(writer);
            try writer.writeAll("/>");
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
            try self.base.renderImpl(writer);
            try writer.writeAll("/>");
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
            try self.base.renderImpl(writer);
            if (self.contents) |contents| {
                try writer.print(">{s}</text>", .{contents});
            } else {
                try writer.writeAll("/>");
            }
        }
    };

    tag: Tag,
    id: ?[]const u8 = null,
    css_classes: ?[]const u8 = null,
    onclick: ?[]const u8 = null,

    pub fn deinit(base: *Element, allocator: *Allocator) void {
        switch (base.tag) {
            .raw => @fieldParentPtr(Raw, "base", base).deinit(allocator),
            .group => @fieldParentPtr(Group, "base", base).deinit(allocator),
            .path => @fieldParentPtr(Path, "base", base).deinit(allocator),
            else => {},
        }
    }

    pub fn render(base: *Element, writer: anytype) @TypeOf(writer).Error!void {
        return switch (base.tag) {
            .raw => @fieldParentPtr(Raw, "base", base).render(writer),
            .group => @fieldParentPtr(Group, "base", base).render(writer),
            .path => @fieldParentPtr(Path, "base", base).render(writer),
            .line => @fieldParentPtr(Line, "base", base).render(writer),
            .rect => @fieldParentPtr(Rect, "base", base).render(writer),
            .text => @fieldParentPtr(Text, "base", base).render(writer),
        };
    }

    fn renderImpl(base: *const Element, writer: anytype) @TypeOf(writer).Error!void {
        if (base.id) |id| {
            try writer.print("id='{s}' ", .{id});
        }
        if (base.css_classes) |classes| {
            try writer.print("class='{s}' ", .{classes});
        }
        if (base.onclick) |onclick| {
            try writer.print("onclick='{s}' ", .{onclick});
        }
    }

    pub fn cast(base: *Element, comptime T: type) ?*T {
        if (T.base_tag != base.tag) return null;
        return @fieldParentPtr(T, "base", base);
    }
};

id: ?[]const u8 = null,
height: usize,
width: usize,
children: std.ArrayListUnmanaged(*Element) = .{},
css_styles: std.ArrayListUnmanaged([]const u8) = .{},

pub fn deinit(self: *Svg, allocator: *Allocator) void {
    for (self.children.items) |child| {
        child.deinit(allocator);
    }
    self.children.deinit(allocator);
    self.css_styles.deinit(allocator);
}

pub fn render(self: Svg, writer: anytype) @TypeOf(writer).Error!void {
    try writer.print("<svg height='{d}' width='{d}' ", .{ self.height, self.width });
    if (self.css_styles.items.len > 0) {
        try writer.writeAll("style=\"");
        for (self.css_styles.items) |css| {
            try writer.writeAll(css);
        }
        try writer.writeAll("\"");
    }
    if (self.id) |id| {
        try writer.print("id='{s}' ", .{id});
    }
    try writer.writeAll(">");
    for (self.children.items) |child| {
        try child.render(writer);
    }
    try writer.writeAll("</svg>");
}
