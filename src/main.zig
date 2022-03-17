const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.zig_snapshots);
const mem = std.mem;

const Allocator = mem.Allocator;
const Svg = @import("Svg.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

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
    log.warn("Usage: {s} <input_json_file>", .{arg0});
    std.process.exit(1);
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_allocator.allocator();
    const args = try std.process.argsAlloc(arena);

    if (args.len == 1) {
        log.warn("not enough arguments", .{});
        usageAndExit(args[0]);
    }
    if (args.len > 2) {
        log.warn("too many arguments", .{});
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

    if (snapshots.len == 0) {
        log.warn("empty snapshots array found", .{});
        return;
    }

    var svgs = std.ArrayList(Svg).init(arena);
    var max_height: usize = 0;
    var onclicks = std.StringHashMap(std.ArrayList(OnClickEvent)).init(arena);

    for (snapshots) |snapshot, snap_i| {
        var svg = Svg{
            .id = try std.fmt.allocPrint(arena, "svg-{d}", .{snap_i}),
            .width = 600,
            .height = 0,
        };

        const defs = try Svg.Element.Raw.new(arena, "defs");
        try svg.children.append(arena, &defs.base);
        const marker = try Svg.Element.Raw.new(arena, "marker");
        try marker.attrs.append(arena, "id='arrowhead'");
        try marker.attrs.append(arena, "markerWidth='10'");
        try marker.attrs.append(arena, "markerHeight='7'");
        try marker.attrs.append(arena, "refX='0'");
        try marker.attrs.append(arena, "refY='3.5'");
        try marker.attrs.append(arena, "orient='auto'");
        try defs.children.append(arena, &marker.base);
        const polygon = try Svg.Element.Raw.new(arena, "polygon");
        try polygon.attrs.append(arena, "points='0 0, 10 3.5, 0 7'");
        try marker.children.append(arena, &polygon.base);

        var parser = Parser{ .arena = arena, .nodes = snapshot.nodes };
        var x: usize = 10;
        var y: usize = 10;
        var lookup = std.AutoHashMap(u64, LookupEntry).init(arena);
        var relocs = std.ArrayList(RelocPair).init(arena);

        while (try parser.parse()) |parsed_node| {
            try parsed_node.toSvg(arena, .{
                .nodes = snapshot.nodes,
                .svg = &svg,
                .x = &x,
                .y = &y,
                .lookup = &lookup,
                .relocs = &relocs,
                .onclicks = &onclicks,
            });
        }

        for (relocs.items) |rel| {
            const target = lookup.get(rel.target) orelse {
                // TODO css_classes clearly ought to be a dynamically sized array
                rel.label.base.css_classes = if (rel.label.base.css_classes) |css|
                    try std.fmt.allocPrint(arena, "{s} italics-font", .{css})
                else
                    "italics-font";
                rel.label.contents = "dyld bound";
                continue;
            };
            const target_el = target.el;
            // TODO Svg.Element.Text should be able to store and render tspan children
            rel.label.contents = try std.fmt.allocPrint(arena, "<tspan x='{d}' dy='{d}'>{s}</tspan><tspan x='{d}' dy='{d}'>  @ {x}</tspan>", .{
                rel.label.x,
                0,
                target.name,
                rel.label.x,
                unit_height,
                rel.target,
            });
            const source_el = rel.box;

            const x1 = source_el.x + source_el.width;
            const y1 = source_el.y + @divFloor(source_el.height, 2);
            const x2 = target_el.x + target_el.width;
            const y2 = target_el.y + @divFloor(target_el.height, 2);

            const arrow = try Svg.Element.Path.new(arena, .{
                .x1 = x1,
                .y1 = y1,
                .x2 = x2,
                .y2 = y2,
            });
            try rel.group.children.append(arena, &arrow.base);
        }

        max_height = std.math.max(max_height, svg.height);
        try svgs.append(svg);
    }
    {
        var it = onclicks.valueIterator();
        while (it.next()) |arr| {
            var js = std.ArrayList(u8).init(arena);
            for (arr.items) |evt| {
                const js_func = try std.fmt.allocPrint(arena, "onClick(\"{s}\", \"{s}\", \"{s}\", {d}, {d});", .{
                    evt.el.base.id.?,
                    evt.group.base.id.?,
                    evt.svg_id,
                    evt.x,
                    evt.y,
                });
                try js.appendSlice(js_func);
            }
            const final = try std.fmt.allocPrint(arena, "(function() {{ {s} }})();", .{js.items});
            for (arr.items) |evt| {
                evt.el.base.onclick = final;
            }
        }
    }

    const out_file = try std.fs.cwd().createFile("snapshots.html", .{
        .truncate = true,
        .read = true,
    });
    defer out_file.close();
    const writer = out_file.writer();
    try writer.writeAll("<html>");
    try writer.writeAll("<head>");
    try writer.print("<style>{s}</style>", .{css_styles});
    try writer.print("<script>{s}</script>", .{js_helpers});
    try writer.writeAll("</head>");
    try writer.writeAll("<body>");

    // TODO why is this even necessary?
    var next_btn = std.ArrayList(u8).init(arena);
    if (svgs.items.len <= 2) {
        try next_btn.appendSlice("disabled");
    }
    try writer.print(
        \\<div>
        \\  <span><button id='btn-prev' onclick='onClickPrev()' disabled>Previous</button></span>
        \\  <span><button id='btn-next' onclick='onClickNext()' {s}>Next</button></span>
        \\</div>
    , .{
        next_btn.items,
    });
    try writer.writeAll("<div class='snapshot-div'>");

    try writer.writeAll("<span id='diff-lhs'>");
    svgs.items[0].height = max_height;
    try svgs.items[0].render(writer);
    try writer.writeAll("</span>");

    if (svgs.items.len > 1) {
        try writer.writeAll("<span id='diff-rhs'>");
        svgs.items[1].height = max_height;
        try svgs.items[1].render(writer);
        try writer.writeAll("</span>");
    }

    for (svgs.items) |*svg| {
        try svg.css_styles.append(arena, "visibility:hidden;");
        svg.height = max_height;
        try svg.render(writer);
    }

    try writer.writeAll("</div>");
    try writer.writeAll("</body>");
    try writer.writeAll("</html>");
}

const LookupEntry = struct {
    el: *Svg.Element.Rect,
    name: []const u8,
};

const OnClickEvent = struct {
    el: *Svg.Element.Rect,
    group: *Svg.Element.Group,
    svg_id: []const u8,
    x: usize,
    y: usize,
};

const RelocPair = struct {
    target: u64,
    label: *Svg.Element.Text,
    box: *Svg.Element.Rect,
    group: *Svg.Element.Group,
};

const ParsedNode = struct {
    tag: enum {
        section,
        atom,
        reloc,
    },
    start: usize,
    end: usize,
    children: std.ArrayListUnmanaged(*ParsedNode) = .{},

    fn deinit(node: *ParsedNode, allocator: Allocator) void {
        for (node.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        node.children.deinit(allocator);
    }

    fn toSvg(node: *ParsedNode, arena: Allocator, ctx: struct {
        nodes: []Snapshot.Node,
        svg: *Svg,
        group: ?*Svg.Element.Group = null,
        sect_name: ?[]const u8 = null,
        x: *usize,
        y: *usize,
        lookup: *std.AutoHashMap(u64, LookupEntry),
        relocs: *std.ArrayList(RelocPair),
        onclicks: *std.StringHashMap(std.ArrayList(OnClickEvent)),
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
                        .sect_name = label_text,
                        .x = ctx.x,
                        .y = &y,
                        .lookup = ctx.lookup,
                        .relocs = ctx.relocs,
                        .onclicks = ctx.onclicks,
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
                            .sect_name = ctx.sect_name,
                            .x = ctx.x,
                            .y = &y,
                            .lookup = ctx.lookup,
                            .relocs = ctx.relocs,
                            .onclicks = ctx.onclicks,
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
                const name = if (ctx.nodes[node.start].payload.name.len == 0)
                    ctx.sect_name.?
                else
                    ctx.nodes[node.start].payload.name;
                try ctx.lookup.putNoClobber(ctx.nodes[node.start].address, .{
                    .el = box,
                    .name = name,
                });

                y += box.height;

                if (node.children.items.len > 0) {
                    const reloc_group = try Svg.Element.Group.new(arena);
                    reloc_group.base.css_classes = "hidden";
                    reloc_group.base.id = try std.fmt.allocPrint(arena, "reloc-group-{d}", .{id});
                    id += 1;
                    try group.children.append(arena, &reloc_group.base);

                    const address = try Svg.Element.Text.new(arena, .{
                        .x = box.x + box.width + 10,
                        .y = box.y + 15,
                        .contents = try std.fmt.allocPrint(arena, "{x}", .{ctx.nodes[node.start].address}),
                    });
                    address.base.css_classes = "bold-font";
                    try reloc_group.children.append(arena, &address.base);

                    box.base.id = try std.fmt.allocPrint(arena, "symbol-{d}", .{id});
                    id += 1;

                    if (ctx.nodes[node.start].payload.name.len == 0) {
                        // Noname means we can't really optimise for diff exploration between snapshots
                        box.base.onclick = try std.fmt.allocPrint(arena, "onClick(\"{s}\", \"{s}\", \"{s}\", 0, {d})", .{
                            box.base.id.?,
                            reloc_group.base.id.?,
                            ctx.svg.id.?,
                            node.children.items.len * 2 * unit_height, // TODO this should be read from the reloc box rather than hardcoded
                        });
                    } else {
                        const res = try ctx.onclicks.getOrPut(ctx.nodes[node.start].payload.name);
                        if (!res.found_existing) {
                            res.value_ptr.* = std.ArrayList(OnClickEvent).init(arena);
                        }
                        try res.value_ptr.append(.{
                            .el = box,
                            .group = reloc_group,
                            .svg_id = ctx.svg.id.?,
                            .x = 0,
                            .y = node.children.items.len * 2 * unit_height, // TODO this should be read from the reloc box rather than hardcoded
                        });
                    }

                    for (node.children.items) |child| {
                        try child.toSvg(arena, .{
                            .nodes = ctx.nodes,
                            .svg = ctx.svg,
                            .group = reloc_group,
                            .sect_name = ctx.sect_name,
                            .x = ctx.x,
                            .y = &y,
                            .lookup = ctx.lookup,
                            .relocs = ctx.relocs,
                            .onclicks = ctx.onclicks,
                        });
                    }

                    y -= node.children.items.len * 2 * unit_height;
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
                    .x = x + 215,
                    .y = y + 15,
                    .contents = undefined,
                });
                try ctx.group.?.children.append(arena, &label.base);

                const box = try Svg.Element.Rect.new(arena, .{
                    .x = x + box_width,
                    .y = y,
                    .width = 200,
                    .height = unit_height * 2,
                });
                try ctx.group.?.children.append(arena, &box.base);
                try ctx.relocs.append(.{
                    .target = ctx.nodes[node.start].payload.target,
                    .label = label,
                    .box = box,
                    .group = ctx.group.?,
                });

                y += box.height;
            },
        }

        ctx.svg.height += y - ctx.y.*;
        ctx.y.* = y;
    }
};

const Parser = struct {
    arena: Allocator,
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
