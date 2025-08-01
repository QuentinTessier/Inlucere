const std = @import("std");
const Resource = @import("Resource.zig");
const Pass = @import("Pass.zig");
const gl = @import("../gl4_6.zig");

pub const FrameGraph = @This();

allocator: std.mem.Allocator,

next_resource_id: u32 = 1,
resource_data: std.AutoArrayHashMapUnmanaged(u32, Resource.Resource),
resource_descriptions: std.AutoArrayHashMapUnmanaged(u32, Resource.Description),
resource_version: std.AutoArrayHashMapUnmanaged(u32, u32),

next_pass_id: u32 = 1,
passes: std.AutoArrayHashMapUnmanaged(u32, Pass),

execution_order: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u32)),

pub fn init(allocator: std.mem.Allocator) FrameGraph {
    return FrameGraph{
        .allocator = allocator,
        .resource_data = .empty,
        .resource_descriptions = .empty,
        .resource_version = .empty,
        .passes = .empty,
        .execution_order = .empty,
    };
}

pub fn deinit(self: *FrameGraph) void {
    for (self.resource_data.values()) |data| {
        switch (data) {
            .buffer => |buffer| {
                self.allocator.free(buffer.name);
                if (buffer.handle != 0) gl.deleteBuffers(1, @ptrCast(&buffer.handle));
            },
            .texture2d => |texture2d| {
                self.allocator.free(texture2d.name);
                if (texture2d.handle != 0) gl.deleteTextures(1, @ptrCast(&texture2d.handle));
            },
            .render_target => |texture2d| {
                self.allocator.free(texture2d.name);
                if (texture2d.handle != 0) gl.deleteTextures(1, @ptrCast(&texture2d.handle));
            },
        }
    }
    self.resource_data.deinit(self.allocator);
    self.resource_descriptions.deinit(self.allocator);
    self.resource_version.deinit(self.allocator);

    for (@as([]Pass, self.passes.values())) |*pass| {
        self.allocator.free(pass.name);
        pass.read_resources.deinit(self.allocator);
        pass.write_resources.deinit(self.allocator);
    }
    self.passes.deinit(self.allocator);

    for (@as([]std.ArrayListUnmanaged(u32), self.execution_order.items)) |*item| {
        item.deinit(self.allocator);
    }
    self.execution_order.deinit(self.allocator);
}

pub const ResourceReference = struct {
    id: u32,
    version: u32,
};

pub fn declare_resource(self: *FrameGraph, name: []const u8, description: Resource.Description) !u32 {
    const id = self.next_resource_id;
    self.next_resource_id += 1;

    switch (description) {
        .buffer => {
            try self.resource_data.put(self.allocator, id, Resource.Resource{ .buffer = .{
                .name = try self.allocator.dupe(u8, name),
                .handle = 0,
                .description = description.buffer,
            } });
        },
        .texture2d => {
            try self.resource_data.put(self.allocator, id, Resource.Resource{ .texture2d = .{
                .name = try self.allocator.dupe(u8, name),
                .handle = 0,
                .description = description.texture2d,
            } });
        },
        .render_target => {
            try self.resource_data.put(self.allocator, id, Resource.Resource{ .render_target = .{
                .name = try self.allocator.dupe(u8, name),
                .handle = 0,
                .description = description.render_target,
            } });
        },
    }

    try self.resource_descriptions.put(self.allocator, id, description);
    try self.resource_version.put(self.allocator, id, 0);
    return id;
}

pub fn current_version(self: *FrameGraph, resource_id: u32) ResourceReference {
    const v = self.resource_version.get(resource_id) orelse @panic("TODO: Not use panic");
    return .{ .id = resource_id, .version = v };
}

pub fn new_version(self: *FrameGraph, resource_id: u32) ResourceReference {
    const v = self.resource_version.getPtr(resource_id) orelse @panic("TODO: Not use panic");
    v.* += 1;
    return .{ .id = resource_id, .version = v.* };
}

pub fn declare_pass(self: *FrameGraph, name: []const u8) !u32 {
    const id = self.next_pass_id;
    self.next_pass_id += 1;

    try self.passes.put(self.allocator, id, try Pass.init(self.allocator, name));
    return id;
}

pub fn pass_reads_from(self: *FrameGraph, pass_id: u32, ref: ResourceReference) !void {
    const ptr: *Pass = self.passes.getPtr(pass_id) orelse @panic("TODO: Not use panic");
    return ptr.read(self.allocator, ref);
}

pub fn pass_writes_to(self: *FrameGraph, pass_id: u32, ref: ResourceReference) !void {
    const ptr: *Pass = self.passes.getPtr(pass_id) orelse @panic("TODO: Not use panic");
    return ptr.write(self.allocator, ref);
}

pub fn pass_reads_writes(self: *FrameGraph, pass_id: u32, ref: Pass.ReadWriteReference) !void {
    const ptr: *Pass = self.passes.getPtr(pass_id) orelse @panic("TODO: Not use panic");
    return ptr.read_write(self.allocator, ref);
}

fn topological_sort(self: *FrameGraph) !bool {
    var in_degree: std.AutoHashMap(u32, u32) = .init(self.allocator);
    defer in_degree.deinit();

    var adj_list: std.AutoHashMap(u32, std.ArrayList(u32)) = .init(self.allocator);
    defer {
        var ite = adj_list.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.deinit();
        }
        adj_list.deinit();
    }

    for (self.passes.keys()) |pass_id| {
        try in_degree.put(pass_id, 0);
        try adj_list.put(pass_id, std.ArrayList(u32).init(self.allocator));
    }

    for (self.passes.keys(), @as([]Pass, self.passes.values())) |pass_id, pass| {
        for (pass.write_resources.items) |written_resource| {
            for (self.passes.keys(), @as([]Pass, self.passes.values())) |other_pass_id, other_pass| {
                if (other_pass.is_reading_from(written_resource)) {
                    const adj_ptr = adj_list.getPtr(pass_id) orelse @panic("");
                    try adj_ptr.append(other_pass_id);

                    const in_degree_ptr = in_degree.getPtr(other_pass_id) orelse @panic("");
                    in_degree_ptr.* += 1;
                }
            }
        }
    }

    var current_level: std.ArrayList(u32) = .init(self.allocator);
    defer current_level.deinit();

    var next_level: std.ArrayList(u32) = .init(self.allocator);
    defer next_level.deinit();

    for (@as([]std.ArrayListUnmanaged(u32), self.execution_order.items)) |*item| {
        item.deinit(self.allocator);
    }
    self.execution_order.clearRetainingCapacity();
    var total_processed: usize = 0;

    var in_degree_ite = in_degree.iterator();
    while (in_degree_ite.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try current_level.append(entry.key_ptr.*);
        }
    }

    while (current_level.items.len > 0) {
        var level: std.ArrayListUnmanaged(u32) = .empty;

        while (current_level.items.len > 0) {
            const current = current_level.orderedRemove(0);
            try level.append(self.allocator, current);
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

        try self.execution_order.append(self.allocator, level);
        std.mem.swap(std.ArrayList(u32), &current_level, &next_level);
    }

    return total_processed == self.passes.count();
}

pub fn compile(self: *FrameGraph) !bool {
    return self.topological_sort();
}
