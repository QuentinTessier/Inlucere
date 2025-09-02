const std = @import("std");
pub const Resource = @import("frame_graph_resource.zig");
pub const Pass = @import("frame_graph_pass.zig");

pub const FrameGraph = @This();

id_counter: u16,

virt_images: std.MultiArrayList(struct {
    id: Resource.Image.ID,
    base: Resource.Base,
    desc: Resource.Image.Description,
    generation: Resource.Generation,
}),
virt_id_to_img: std.AutoHashMapUnmanaged(Resource.Image.ID, usize),

virt_buffers: std.MultiArrayList(struct {
    id: Resource.Buffer.ID,
    base: Resource.Base,
    desc: Resource.Buffer.Description,
    generation: Resource.Generation,
}),
virt_id_to_buf: std.AutoHashMapUnmanaged(Resource.Buffer.ID, usize),

passes: std.AutoArrayHashMapUnmanaged(Pass.ID, *Pass),

pub fn init() FrameGraph {
    return FrameGraph{
        .id_counter = 1,
        .virt_images = .empty,
        .virt_id_to_img = .empty,
        .virt_buffers = .empty,
        .virt_id_to_buf = .empty,
        .passes = .empty,
    };
}

pub fn deinit(self: *FrameGraph, allocator: std.mem.Allocator) void {
    self.virt_images.deinit(allocator);
    self.virt_id_to_img.deinit(allocator);

    self.virt_buffers.deinit(allocator);
    self.virt_id_to_buf.deinit(allocator);

    for (@as([]*Pass, self.passes.values())) |pass| {
        allocator.free(pass.name);
        pass.images.deinit(allocator);
        pass.buffers.deinit(allocator);
        allocator.destroy(pass);
    }
    self.passes.deinit(allocator);
}

fn next_image_id(self: *FrameGraph) Resource.Image.ID {
    const id: Resource.Image.ID = .{
        .handle = self.id_counter,
    };
    self.id_counter += 1;
    return id;
}

fn next_buffer_id(self: *FrameGraph) Resource.Buffer.ID {
    const id: Resource.Buffer.ID = .{
        .handle = self.id_counter,
    };
    self.id_counter += 1;
    return id;
}

fn next_pass_id(self: *FrameGraph) Pass.ID {
    const id: Pass.ID = .{
        .handle = self.id_counter,
    };
    self.id_counter += 1;
    return id;
}

pub fn declare_image(self: *FrameGraph, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Image.Description) !Resource.Image.ID {
    const id = self.next_image_id();

    const index = try self.virt_images.addOne(allocator);
    self.virt_images.items(.id)[index] = id;
    self.virt_images.items(.base)[index] = Resource.Base{
        .debug_name = debug_name,
        .imported = false,
        .lifetime = undefined,
    };
    self.virt_images.items(.desc)[index] = desc;
    self.virt_images.items(.generation)[index] = .default;

    try self.virt_id_to_img.put(allocator, id, index);
    return id;
}

pub fn declare_buffer(self: *FrameGraph, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Buffer.Description) !Resource.Buffer.ID {
    const id = self.next_buffer_id();

    const index = try self.virt_buffers.addOne(allocator);
    self.virt_buffers.items(.id)[index] = id;
    self.virt_buffers.items(.base)[index] = Resource.Base{
        .debug_name = debug_name,
        .imported = false,
        .lifetime = undefined,
    };
    self.virt_buffers.items(.desc)[index] = desc;
    self.virt_buffers.items(.generation)[index] = .default;

    try self.virt_id_to_buf.put(allocator, id, index);
    return id;
}

pub fn declare_pass(self: *FrameGraph, allocator: std.mem.Allocator, name: []const u8) !struct { id: Pass.ID, pass: *Pass } {
    const id = self.next_pass_id();

    const entry = try self.passes.getOrPut(allocator, id);
    if (entry.found_existing) unreachable;

    try self.passes.put(allocator, id, try allocator.create(Pass));
    const ptr: *Pass = self.passes.get(id) orelse unreachable;

    ptr.name = try allocator.dupe(u8, name);
    ptr.id = id;
    ptr.owner = self;
    ptr.buffers = .empty;
    ptr.images = .empty;
    ptr.has_side_effects = false;

    return .{ .id = id, .pass = ptr };
}

fn update_dependency_for_image(self: *FrameGraph, pass_id: Pass.ID, source_img: *const Resource.Image.Reference, in_degree: *std.AutoHashMap(Pass.ID, u16), adj_list: *std.AutoHashMap(Pass.ID, std.ArrayList(Pass.ID))) !void {
    var ite = self.passes.iterator();
    while (ite.next()) |entry| {
        if (!pass_id.eq(entry.key_ptr) and entry.value_ptr.*.is_reading_image(source_img)) {
            const adj = adj_list.getPtr(pass_id) orelse unreachable;
            try adj.append(entry.key_ptr.*);

            const in_degree_ptr = in_degree.getPtr(entry.key_ptr.*) orelse unreachable;
            in_degree_ptr.* += 1;
        }
    }
}

fn update_dependency_for_buffer(self: *FrameGraph, pass_id: Pass.ID, source_buf: *const Resource.Buffer.Reference, in_degree: *std.AutoHashMap(Pass.ID, u16), adj_list: *std.AutoHashMap(Pass.ID, std.ArrayList(Pass.ID))) !void {
    var ite = self.passes.iterator();
    while (ite.next()) |entry| {
        if (!pass_id.eq(entry.key_ptr) and entry.value_ptr.*.is_reading_buffer(source_buf)) {
            const adj = adj_list.getPtr(pass_id) orelse unreachable;
            try adj.append(entry.key_ptr.*);

            const in_degree_ptr = in_degree.getPtr(entry.key_ptr.*) orelse unreachable;
            in_degree_ptr.* += 1;
        }
    }
}

fn topological_sort(self: *FrameGraph, allocator: std.mem.Allocator) !?[][]Pass.ID {
    var in_degree: std.AutoHashMap(Pass.ID, u16) = .init(allocator);
    defer in_degree.deinit();

    var adj_list: std.AutoHashMap(Pass.ID, std.ArrayList(Pass.ID)) = .init(allocator);
    defer {
        var ite = adj_list.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.deinit();
        }
        adj_list.deinit();
    }

    {
        var ite = self.passes.iterator();
        while (ite.next()) |entry| {
            if (!entry.value_ptr.*.has_side_effects and entry.value_ptr.*.rc == 0) continue;
            try in_degree.put(entry.key_ptr.*, 0);
            try adj_list.put(entry.key_ptr.*, .init(allocator));
        }
    }

    {
        var ite = self.passes.iterator();
        while (ite.next()) |entry| {
            if (!entry.value_ptr.*.has_side_effects and entry.value_ptr.*.rc == 0) continue;
            for (@as([]const Resource.Image.Reference, entry.value_ptr.*.images.items)) |*img_ref| {
                if (img_ref.access().write) {
                    try self.update_dependency_for_image(entry.key_ptr.*, img_ref, &in_degree, &adj_list);
                }
            }

            for (@as([]const Resource.Buffer.Reference, entry.value_ptr.*.buffers.items)) |*buf_ref| {
                if (buf_ref.access().write) {
                    try self.update_dependency_for_buffer(entry.key_ptr.*, buf_ref, &in_degree, &adj_list);
                }
            }
        }
    }

    var current_level: std.ArrayList(Pass.ID) = .init(allocator);
    defer current_level.deinit();

    var next_level: std.ArrayList(Pass.ID) = .init(allocator);
    defer next_level.deinit();

    var execution_order: std.ArrayList([]Pass.ID) = .init(allocator);
    var total_processed: usize = 0;

    var in_degree_ite = in_degree.iterator();
    while (in_degree_ite.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try current_level.append(entry.key_ptr.*);
        }
    }

    while (current_level.items.len > 0) {
        var level: std.ArrayListUnmanaged(Pass.ID) = .empty;

        while (current_level.items.len > 0) {
            const current = current_level.orderedRemove(0);
            try level.append(allocator, current);
            total_processed += 1;

            const neighbor_list = adj_list.get(current) orelse @panic("");
            for (neighbor_list.items) |neighbor| {
                const in_degree_ptr = in_degree.getPtr(neighbor) orelse @panic("");
                in_degree_ptr.* -= 1;
                if (in_degree_ptr.* == 0) {
                    try next_level.append(neighbor);
                }
            }
        }

        try execution_order.append(try level.toOwnedSlice(allocator));
        std.mem.swap(std.ArrayList(Pass.ID), &current_level, &next_level);
    }

    if (total_processed == self.passes.count()) {
        return try execution_order.toOwnedSlice();
    } else {
        for (execution_order.items) |item| {
            allocator.free(item);
        }
        execution_order.deinit();
        return null;
    }
}

fn compute_resource_lifetime(self: *FrameGraph, exec_order: [][]Pass.ID) void {
    for (@as([]const Resource.Image.ID, self.virt_images.items(.id)), @as([]Resource.Base, self.virt_images.items(.base))) |id, *base| {
        var min_level: usize = exec_order.len;
        var max_level: usize = 0;

        for (exec_order, 0..) |level, i| {
            for (level) |pass_id| {
                const pass = self.passes.get(pass_id) orelse unreachable;

                if (pass.has_reference_to_image(id)) {
                    min_level = @min(min_level, i);
                    max_level = @max(max_level, i);
                }
            }
        }

        base.lifetime = .{
            .start_level = @intCast(min_level),
            .end_level = @intCast(max_level),
        };
    }

    for (@as([]const Resource.Buffer.ID, self.virt_buffers.items(.id)), @as([]Resource.Base, self.virt_buffers.items(.base))) |id, *base| {
        var min_level: usize = exec_order.len;
        var max_level: usize = 0;

        for (exec_order, 0..) |level, i| {
            for (level) |pass_id| {
                const pass = self.passes.get(pass_id) orelse unreachable;

                if (pass.has_reference_to_buffer(id)) {
                    min_level = @min(min_level, i);
                    max_level = @max(max_level, i);
                }
            }
        }

        base.lifetime = .{
            .start_level = @intCast(min_level),
            .end_level = @intCast(max_level),
        };
    }
}

pub fn compile(self: *FrameGraph, allocator: std.mem.Allocator) !?[][]Pass.ID {
    if (try self.topological_sort(allocator)) |exec_order| {
        self.compute_resource_lifetime(exec_order);
        return exec_order;
    }
    return null;
}

pub fn debug_dot_graph(self: *const FrameGraph, allocator: std.mem.Allocator, graph_name: []const u8) ![]u8 {
    var buffer: std.ArrayList(u8) = .init(allocator);
    const writer = buffer.writer();

    try writer.print("digraph {s} {{\n", .{graph_name});

    for (
        @as([]Resource.Image.ID, self.virt_images.items(.id)),
        @as([]Resource.Base, self.virt_images.items(.base)),
        @as([]Resource.Generation, self.virt_images.items(.generation)),
    ) |id, base, gen| {
        if (base.debug_name) |debug_name| {
            for (1..@intCast(gen.handle)) |g| {
                try writer.print("\t{s}_{} [shape=ellipse]\n", .{ debug_name, g });
            }
        } else {
            for (1..@intCast(gen.handle)) |g| {
                try writer.print("\t{}_{} [shape=ellipse]\n", .{ id.handle, g });
            }
        }
    }

    for (
        @as([]Resource.Buffer.ID, self.virt_buffers.items(.id)),
        @as([]Resource.Base, self.virt_buffers.items(.base)),
        @as([]Resource.Generation, self.virt_buffers.items(.generation)),
    ) |id, base, gen| {
        if (base.debug_name) |debug_name| {
            for (1..@intCast(gen.handle)) |g| {
                try writer.print("\t{s}_{} [shape=octagon]\n", .{ debug_name, g });
            }
        } else {
            for (1..@intCast(gen.handle)) |g| {
                try writer.print("\t{}_{} [shape=octagon]\n", .{ id.handle, g });
            }
        }
    }

    for (self.passes.values()) |pass| {
        try writer.print("\t{s} [shape=box];\n", .{pass.name});

        for (@as([]Resource.Image.Reference, pass.images.items)) |img| {
            const index: usize = self.virt_id_to_img.get(img.id) orelse unreachable;
            const base: *const Resource.Base = &self.virt_images.items(.base)[index];
            const id: Resource.Image.ID = self.virt_images.items(.id)[index];
            if (base.debug_name) |debug_name| {
                if (img.read()) {
                    try writer.print("\t{s}_{} -> {s}\n", .{ debug_name, img.read_gen.handle, pass.name });
                }
                if (img.write()) {
                    try writer.print("\t{s} -> {s}_{}\n", .{ pass.name, debug_name, img.write_gen.handle });
                }
            } else {
                if (img.read()) {
                    try writer.print("\t{}_{} -> {s}\n", .{ id.handle, img.read_gen.handle, pass.name });
                }
                if (img.write()) {
                    try writer.print("\t{s} -> {}_{}\n", .{ pass.name, id.handle, img.write_gen.handle });
                }
            }
        }

        for (@as([]Resource.Buffer.Reference, pass.buffers.items)) |buf| {
            const index: usize = self.virt_id_to_buf.get(buf.id) orelse unreachable;
            const base: *const Resource.Base = &self.virt_buffers.items(.base)[index];
            const id: Resource.Buffer.ID = self.virt_buffers.items(.id)[index];
            if (base.debug_name) |debug_name| {
                if (buf.read()) {
                    try writer.print("\t{s}_{} -> {s}\n", .{ debug_name, buf.read_gen.handle, pass.name });
                }
                if (buf.write()) {
                    try writer.print("\t{s} -> {s}_{}\n", .{ pass.name, debug_name, buf.write_gen.handle });
                }
            } else {
                if (buf.read()) {
                    try writer.print("\t{}_{} -> {s}\n", .{ id.handle, buf.read_gen.handle, pass.name });
                }
                if (buf.write()) {
                    try writer.print("\t{s} -> {}_{}\n", .{ pass.name, id.handle, buf.write_gen.handle });
                }
            }
        }
    }

    try writer.print("}}\n", .{});
    return buffer.toOwnedSlice();
}

pub fn compute_physical_images_allocation(self: *FrameGraph, allocator: std.mem.Allocator) !void {}
