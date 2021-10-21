const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.snapshot);
const mem = std.mem;

const Allocator = mem.Allocator;
const Svg = @import("Svg.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &general_purpose_allocator.allocator;

var id: usize = 0;

const Snapshot = struct {
    const Node = struct {
        const Tag = enum {
            section_start,
            section_end,
            atom_start,
            atom_end,
            relocation,
        };
        const Payload = struct {
            name: []const u8,
            aliases: [][]const u8,
            is_global: bool,
            target: u64,
        };
        address: u64,
        tag: Tag,
        payload: Payload,
    };
    timestamp: i128,
    nodes: []Node,
};

const svg_width: usize = 600;
const unit_height: usize = 20;
const css_styles = @embedFile("styles.css");
const js_helpers = @embedFile("script.js");

fn usageAndExit(arg0: []const u8) noreturn {
    std.debug.warn("Usage: {s} <input_json_file>\n", .{arg0});
    std.process.exit(1);
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    const arena = &arena_allocator.allocator;
    const args = try std.process.argsAlloc(arena);

    if (args.len == 1) {
        std.debug.warn("not enough arguments\n", .{});
        usageAndExit(args[0]);
    }
    if (args.len > 2) {
        std.debug.warn("too many arguments\n", .{});
        usageAndExit(args[0]);
    }

    const first_arg = args[1];
    const file = try std.fs.cwd().openFile(first_arg, .{});
    defer file.close();
    const stat = try file.stat();
    const contents = try file.readToEndAlloc(arena, stat.size);
    const opts = std.json.ParseOptions{
        .allocator = arena,
    };
    const snapshots = try std.json.parse([]Snapshot, &std.json.TokenStream.init(contents), opts);
    defer std.json.parseFree([]Snapshot, snapshots, opts);

    const out_file = try std.fs.cwd().createFile("snapshots.html", .{
        .truncate = true,
        .read = true,
    });
    defer out_file.close();

    const writer = out_file.writer();

    try writer.writeAll("<html>");
    try writer.writeAll("<head>");
    try writer.print("<script>{s}</script>", .{js_helpers});
    try writer.writeAll("</head>");
    try writer.writeAll("<body>");
    try writer.print("<style>{s}</style>", .{css_styles});

    for (snapshots) |snapshot| {
        try writer.writeAll("<div class='snapshot-div'>");
        var svg = Svg{ .width = 600, .height = 0 };
        var parser = Parser{ .arena = arena, .nodes = snapshot.nodes };
        var x: usize = 10;
        var y: usize = 10;
        var parsed = std.ArrayList(*ParsedNode).init(arena);
        while (try parser.parse()) |parsed_node| {
            try parsed.append(parsed_node);
            try parsed_node.toSvg(arena, .{
                .nodes = snapshot.nodes,
                .svg = &svg,
                .x = &x,
                .y = &y,
            });
        }
        try svg.render(writer);
    }

    try writer.writeAll("</div>");
    try writer.writeAll("</body>");
    try writer.writeAll("</html>");
}

const ParsedNode = struct {
    tag: enum {
        section,
        atom,
        reloc,
    },
    start: usize,
    end: usize,
    children: std.ArrayListUnmanaged(*ParsedNode) = .{},

    fn deinit(node: *ParsedNode, allocator: *Allocator) void {
        for (node.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        node.children.deinit(allocator);
    }

    fn toSvg(node: *ParsedNode, arena: *Allocator, ctx: struct {
        nodes: []Snapshot.Node,
        svg: *Svg,
        group: ?*Svg.Element.Group = null,
        x: *usize,
        y: *usize,
    }) anyerror!void {
        var x = ctx.x.*;
        var y = ctx.y.*;

        switch (node.tag) {
            .section => {
                const group = try Svg.Element.Group.new(arena);
                try ctx.svg.children.append(arena, &group.base);

                const inner_group = try Svg.Element.Group.new(arena);
                try group.children.append(arena, &inner_group.base);

                const label_text = ctx.nodes[node.start].payload.name;
                const label = try Svg.Element.Text.new(arena, .{
                    .x = x,
                    .y = y + 15,
                    .contents = label_text,
                });
                try inner_group.children.append(arena, &label.base);

                const top = try Svg.Element.Path.new(arena, .{});
                try top.moveTo(arena, x, y);
                try top.lineTo(arena, ctx.svg.width - 100, y);
                top.base.css_classes = "dotted-line";
                try inner_group.children.append(arena, &top.base);

                const address = try Svg.Element.Text.new(arena, .{
                    .x = ctx.svg.width - 100,
                    .y = y + 15,
                    .contents = try std.fmt.allocPrint(arena, "{x}", .{ctx.nodes[node.start].address}),
                });
                try inner_group.children.append(arena, &address.base);

                y += unit_height;

                for (node.children.items) |child| {
                    try child.toSvg(arena, .{
                        .nodes = ctx.nodes,
                        .svg = ctx.svg,
                        .group = group,
                        .x = ctx.x,
                        .y = &y,
                    });
                }

                y += unit_height;
            },
            .atom => blk: {
                if (node.children.items.len > 0 and node.children.items[0].tag == .atom) {
                    // This atom delimits contents of a section from an object file
                    // TODO draw an enclosing box for the contained atoms.
                    for (node.children.items) |child| {
                        try child.toSvg(arena, .{
                            .nodes = ctx.nodes,
                            .svg = ctx.svg,
                            .group = ctx.group,
                            .x = ctx.x,
                            .y = &y,
                        });
                    }
                    break :blk;
                }

                const group = try Svg.Element.Group.new(arena);
                try ctx.group.?.children.append(arena, &group.base);

                const label = try Svg.Element.Text.new(arena, .{
                    .x = x + 210,
                    .y = y + 15,
                    .contents = ctx.nodes[node.start].payload.name,
                });
                try group.children.append(arena, &label.base);

                const box = try Svg.Element.Rect.new(arena, .{
                    .x = x + 200,
                    .y = y,
                    .width = 200,
                    .height = unit_height,
                });
                if (ctx.nodes[node.start].payload.is_global) {
                    box.base.css_classes = "symbol global";
                } else {
                    box.base.css_classes = "symbol local";
                }
                try group.children.append(arena, &box.base);

                y += box.height;

                if (node.children.items.len > 0) {
                    const reloc_group = try Svg.Element.Group.new(arena);
                    reloc_group.base.css_classes = "hidden";
                    reloc_group.base.id = try std.fmt.allocPrint(arena, "reloc-group-{d}", .{id});
                    id += 1;
                    try group.children.append(arena, &reloc_group.base);

                    box.base.onclick = try std.fmt.allocPrint(arena, "translate(\"{s}\", 0, {d})", .{
                        reloc_group.base.id, node.children.items.len * unit_height,
                    });

                    for (node.children.items) |child| {
                        try child.toSvg(arena, .{
                            .nodes = ctx.nodes,
                            .svg = ctx.svg,
                            .group = reloc_group,
                            .x = ctx.x,
                            .y = &y,
                        });
                    }

                    y -= node.children.items.len * unit_height;
                }
            },
            .reloc => {
                const address = try Svg.Element.Text.new(arena, .{
                    .x = x + 410,
                    .y = y + 15,
                    .contents = try std.fmt.allocPrint(arena, "{x}", .{ctx.nodes[node.start].address}),
                });
                try ctx.group.?.children.append(arena, &address.base);

                const box_width = 200;
                const label = try Svg.Element.Text.new(arena, .{
                    .x = x + 200 + @divExact(box_width, 2) - 35,
                    .y = y + 15,
                    .contents = "relocation",
                });
                try ctx.group.?.children.append(arena, &label.base);

                const box = try Svg.Element.Rect.new(arena, .{
                    .x = x + box_width,
                    .y = y,
                    .width = 200,
                    .height = unit_height,
                });
                try ctx.group.?.children.append(arena, &box.base);

                y += box.height;
            },
        }

        ctx.svg.height += y - ctx.y.*;
        ctx.y.* = y;
    }
};

const Parser = struct {
    arena: *Allocator,
    nodes: []Snapshot.Node,
    count: usize = 0,

    fn parse(parser: *Parser) !?*ParsedNode {
        const nn = parser.next() orelse return null;
        return switch (nn.tag) {
            .section_end, .atom_end, .relocation => unreachable,
            .section_start => parser.parseSection(),
            .atom_start => parser.parseAtom(),
        };
    }

    fn parseSection(parser: *Parser) anyerror!*ParsedNode {
        const node = try parser.arena.create(ParsedNode);
        node.* = .{
            .tag = .section,
            .start = parser.count - 1,
            .end = undefined,
        };
        while (parser.next()) |nn| {
            switch (nn.tag) {
                .section_start, .atom_end, .relocation => unreachable,
                .atom_start => {
                    const child = try parser.parseAtom();
                    try node.children.append(parser.arena, child);
                },
                .section_end => {
                    node.end = parser.count - 1;
                    break;
                },
            }
        }
        return node;
    }

    fn parseAtom(parser: *Parser) anyerror!*ParsedNode {
        const node = try parser.arena.create(ParsedNode);
        node.* = .{
            .tag = .atom,
            .start = parser.count - 1,
            .end = undefined,
        };
        while (parser.next()) |nn| {
            switch (nn.tag) {
                .section_start, .section_end => unreachable,
                .atom_start => {
                    const child = try parser.parseAtom();
                    try node.children.append(parser.arena, child);
                },
                .atom_end => {
                    node.end = parser.count - 1;
                    break;
                },
                .relocation => {
                    const child = try parser.parseReloc();
                    try node.children.append(parser.arena, child);
                },
            }
        }
        return node;
    }

    fn parseReloc(parser: *Parser) anyerror!*ParsedNode {
        const node = try parser.arena.create(ParsedNode);
        node.* = .{
            .tag = .reloc,
            .start = parser.count - 1,
            .end = parser.count - 1,
        };
        return node;
    }

    fn next(parser: *Parser) ?Snapshot.Node {
        if (parser.count >= parser.nodes.len) return null;
        const node = parser.nodes[parser.count];
        parser.count += 1;
        return node;
    }
};
