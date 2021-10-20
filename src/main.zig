const std = @import("std");
const log = std.log.scoped(.snapshot);
const mem = std.mem;

const Allocator = mem.Allocator;
const Svg = @import("Svg.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &general_purpose_allocator.allocator;

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

    try writer.writeAll("<html>\n");
    try writer.writeAll("<head></head>\n");
    try writer.writeAll("<body>\n");
    try writer.print("<style>{s}</style>\n", .{css_styles});

    for (snapshots) |snapshot| {
        // address to y mapping
        var mapping = std.ArrayList(struct { y: usize, address: u64, nodes: std.ArrayList(Snapshot.Node) }).init(arena);
        var lookup_table = std.AutoArrayHashMap(u64, usize).init(arena);
        for (snapshot.nodes) |node| {
            const res = try lookup_table.getOrPut(node.address);
            if (!res.found_existing) {
                const index = mapping.items.len;
                res.value_ptr.* = index;
                const new = try mapping.addOne();
                const last_y = if (index == 0) 0 else mapping.items[index - 1].y;
                new.* = .{
                    .y = last_y + unit_height,
                    .address = node.address,
                    .nodes = std.ArrayList(Snapshot.Node).init(arena),
                };
            }
            try mapping.items[res.value_ptr.*].nodes.append(node);
        }

        try writer.writeAll("<div class='snapshot-div'>\n");

        var svg = Svg{
            .width = 600,
            .height = 0,
        };

        for (mapping.items) |entry| {
            log.warn("y = {d}, address = {x}, nnodes = {d}", .{ entry.y, entry.address, entry.nodes.items.len });

            // TODO create an svg group?
            const box = try Svg.Element.Rect.new(arena);
            try svg.children.append(arena, &box.base);
            try box.base.css.append(arena, "rect");
            box.x = 200;
            box.y = entry.y;
            box.width = svg.width - 300;
            box.height = unit_height;
            const addr = try Svg.Element.Text.new(arena);
            try svg.children.append(arena, &addr.base);
            addr.x = svg.width - 100 + 5;
            addr.y = box.y + 12;
            addr.contents = try std.fmt.allocPrint(arena, "{x}", .{entry.address});

            // var tags = std.AutoHashMap(Snapshot.Node.Tag, void).init(arena);
            // for (entry.nodes.items) |node| {
            //     _ = try tags.getOrPut(node.tag);
            // }

            // for (entry.nodes.items) |node| {
            //     log.warn("    {s} => {s}", .{ node.tag, node.payload.name });

            //     switch (node.tag) {
            //         .section_start => {
            //             const svg_label = try svg_snap.newChild(arena);
            //             svg_label.tag = .text;
            //             svg_label.x = 10;
            //             svg_label.y = svg_rect.y + 15;
            //             svg_label.contents = node.payload.name;
            //         },
            //         .atom_start => {
            //             const svg_label = try svg_snap.newChild(arena);
            //             svg_label.tag = .text;
            //             svg_label.x = svg_rect.x + 10;
            //             svg_label.y = svg_rect.y + 15;
            //             svg_label.contents = node.payload.name;
            //         },
            //         .relocation => {
            //             const svg_arrow = try svg_snap.newChild(arena);
            //             svg_arrow.tag = .line;

            //             if (tags.contains(.atom_start)) continue;
            //             const svg_label = try svg_snap.newChild(arena);
            //             svg_label.tag = .text;
            //             svg_label.x = svg_rect.x + 10;
            //             svg_label.y = svg_rect.y + 15;
            //             svg_label.contents = try std.fmt.allocPrint(arena, "{x}", .{node.payload.target});
            //         },
            //         else => {},
            //     }
            // }

            svg.height += unit_height;
        }

        try svg.render(writer);
    }

    try writer.writeAll("</div>\n");
    try writer.writeAll("</body>\n");
    try writer.writeAll("</html>\n");
}

fn usageAndExit(arg0: []const u8) noreturn {
    std.debug.warn("Usage: {s} <input_json_file>\n", .{arg0});
    std.process.exit(1);
}
