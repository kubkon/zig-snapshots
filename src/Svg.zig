const Svg = @This();

const std = @import("std");
const mem = std.mem;

const Allocator = mem.Allocator;

pub const Element = struct {
    const Tag = enum {
        group,
        path,
        line,
        rect,
        text,
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
        d: std.ArrayListUnmanaged(u8) = .{},

        pub fn new(allocator: *Allocator, opts: struct {
            d: ?[]const u8 = null,
        }) !*Path {
            const self = try allocator.create(Path);
            self.* = .{
                .base = .{ .tag = .path },
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
            .group => @fieldParentPtr(Group, "base", base).deinit(allocator),
            else => {},
        }
    }

    pub fn render(base: *Element, writer: anytype) @TypeOf(writer).Error!void {
        return switch (base.tag) {
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
    try writer.print("<svg height='{d}' width='{d}'>", .{ self.height, self.width });
    for (self.children.items) |child| {
        try child.render(writer);
    }
    try writer.writeAll("</svg>");
}
