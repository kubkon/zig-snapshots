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
        var updated = false;
        for (snapshot.nodes) |node| {
            const res = try lookup_table.getOrPut(node.address);
            if (!res.found_existing) {
                updated = false;
                const index = mapping.items.len;
                res.value_ptr.* = index;
                const new = try mapping.addOne();
                const last_y = if (index > 0)
                    mapping.items[index - 1].y
                else
                    0;
                new.* = .{
                    .y = last_y + unit_height,
                    .address = node.address,
                    .nodes = std.ArrayList(Snapshot.Node).init(arena),
                };
            }
            switch (node.tag) {
                .section_start => if (!updated) {
                    mapping.items[res.value_ptr.*].y += 2 * unit_height;
                    updated = true;
                },
                .atom_start => if (!updated) {
                    mapping.items[res.value_ptr.*].y += unit_height;
                    updated = true;
                },
                else => {},
            }
            try mapping.items[res.value_ptr.*].nodes.append(node);
        }

        try writer.writeAll("<div class='snapshot-div'>\n");

        var svg = Svg{
            .width = 600,
            .height = 0,
        };

        var done = false;
        for (mapping.items) |entry| {
            log.warn("y = {d}, address = {x}, nnodes = {d}", .{ entry.y, entry.address, entry.nodes.items.len });

            if (entry.nodes.items.len == 1) {
                switch (entry.nodes.items[0].tag) {
                    .section_end, .atom_end => continue,
                    else => {},
                }
            }

            // TODO create an svg group?
            const box = try Svg.Element.Rect.new(arena, .{
                .x = 200,
                .y = entry.y,
                .width = svg.width - 300,
                .height = unit_height,
            });
            try svg.children.append(arena, &box.base);
            try box.base.css.append(arena, "rect");

            const addr = try Svg.Element.Text.new(arena, .{
                .x = svg.width - 100 + 5,
                .y = box.y + 12,
                .contents = try std.fmt.allocPrint(arena, "{x}", .{entry.address}),
            });
            try svg.children.append(arena, &addr.base);

            outer: for (entry.nodes.items) |node, i| {
                switch (node.tag) {
                    .section_start => {
                        const label = try Svg.Element.Text.new(arena, .{
                            .x = 10,
                            .y = box.y + 12,
                            .contents = node.payload.name,
                        });
                        try svg.children.append(arena, &label.base);
                    },
                    .atom_start => {
                        var next: usize = i + 1;
                        while (next < entry.nodes.items.len) : (next += 1) {
                            if (entry.nodes.items[next].tag == .atom_start) continue :outer;
                        }
                        if (node.payload.name.len == 0) continue :outer;
                        const name = try Svg.Element.Text.new(arena, .{
                            .x = box.x + 10,
                            .y = box.y + 15,
                            .contents = node.payload.name,
                        });
                        try svg.children.append(arena, &name.base);
                    },
                    .relocation => {
                        if (done) continue;
                        const y2 = blk: {
                            const target_i = lookup_table.get(node.payload.target) orelse continue;
                            const target = mapping.items[target_i];
                            break :blk target.y;
                        };
                        const arrow = try Svg.Element.Line.new(arena, .{
                            .x1 = box.x,
                            .y1 = box.y,
                            .x2 = box.x + 20,
                            .y2 = y2,
                        });
                        try arrow.base.css.append(arena, "arrow");
                        try svg.children.append(arena, &arrow.base);
                        done = true;
                    },
                    else => {},
                }
            }
        }

        var i: isize = @intCast(isize, svg.children.items.len) - 1;
        while (i >= 0) : (i -= 1) {
            const child = svg.children.items[@intCast(usize, i)];
            if (child.cast(Svg.Element.Rect)) |rect| {
                svg.height = rect.y + rect.height;
                break;
            }
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
