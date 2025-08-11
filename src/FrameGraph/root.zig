const std = @import("std");
pub const Resource = @import("resources.zig");
const Device = @import("../Device.zig");
pub const PassBuilder = @import("pass_builder.zig");
const Pass = PassBuilder.Pass;

pub const FrameGraph = @This();

allocator: std.mem.Allocator,
next_item_id: u32,

resource_version: std.AutoHashMapUnmanaged(u32, u32),
resource_kind: std.AutoHashMapUnmanaged(u32, Resource.ResourceKind),
buffer_storage: Resource.Storage(.buffer, Device.DynamicBuffer, Resource.BufferDescription),
texture2d_storage: Resource.Storage(.texture2d, Device.Texture2D, Resource.Texture2DDescription),
custom_resource_storage: Resource.Storage(.custom, ?*anyopaque, void),

passes: std.AutoArrayHashMapUnmanaged(u32, Pass),
execution_order: ?[][]u32,

pub fn init(allocator: std.mem.Allocator) FrameGraph {
    return FrameGraph{
        .allocator = allocator,
        .next_item_id = 1,
        .resource_version = .empty,
        .resource_kind = .empty,
        .buffer_storage = .init(),
        .texture2d_storage = .init(),
        .custom_resource_storage = .init(),
        .passes = .empty,
        .execution_order = null,
    };
}

pub fn deinit(self: *FrameGraph) void {
    self.resource_version.deinit(self.allocator);
    self.resource_kind.deinit(self.allocator);

    self.buffer_storage.deinit(self.allocator);
    self.texture2d_storage.deinit(self.allocator);
    self.custom_resource_storage.deinit(self.allocator);

    var ite = self.passes.iterator();
    while (ite.next()) |entry| {
        self.allocator.free(entry.value_ptr.name);
        self.allocator.free(entry.value_ptr.virtual_resource_read);
        self.allocator.free(entry.value_ptr.virtual_resource_write);
        self.allocator.free(entry.value_ptr.virtual_color_attachment);
    }
    self.passes.deinit(self.allocator);

    if (self.execution_order) |exec_order| {
        for (exec_order) |list| {
            self.allocator.free(list);
        }
        self.allocator.free(exec_order);
    }
}

pub fn declare_pass(self: *FrameGraph, pass: Pass) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.passes.put(self.allocator, id, pass);
    return id;
}

pub fn declare_managed_buffer(self: *FrameGraph, desc: Resource.BufferDescription) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.buffer_storage.declare_managed(self.allocator, id, desc);
    try self.resource_version.put(self.allocator, id, 0);
    try self.resource_kind.put(self.allocator, id, .buffer);
    return id;
}

pub fn declare_imported_buffer(self: *FrameGraph, obj: Device.DynamicBuffer, desc: ?Resource.BufferDescription) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.buffer_storage.declare_imported(self.allocator, id, obj, desc);
    try self.resource_version.put(self.allocator, id, 0);
    try self.resource_kind.put(self.allocator, id, .buffer);
    return id;
}

pub fn declare_managed_texture2d(self: *FrameGraph, desc: Resource.Texture2DDescription) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.texture2d_storage.declare_managed(self.allocator, id, desc);
    try self.resource_version.put(self.allocator, id, 0);
    try self.resource_kind.put(self.allocator, id, .texture2d);
    return id;
}

pub fn declare_imported_texture2d(self: *FrameGraph, obj: Device.Texture2D, desc: ?Resource.Texture2DDescription) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.texture2d_storage.declare_imported(self.allocator, id, obj, desc);
    try self.resource_version.put(self.allocator, id, 0);
    try self.resource_kind.put(self.allocator, id, .texture2d);
    return id;
}

pub fn declare_custom_resource(self: *FrameGraph, obj: ?*anyopaque) !u32 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.custom_resource_storage.declare_imported(self.allocator, id, obj, void{});
    try self.resource_version.put(self.allocator, id, 0);
    try self.resource_kind.put(self.allocator, id, .custom);
    return id;
}

pub fn get_version(self: *FrameGraph, id: u32) !Resource.VirtualResource {
    return if (self.resource_version.get(id)) |v| Resource.VirtualResource{ .id = id, .version = v } else error.NoSuchResource;
}

pub fn declare_new_version(self: *FrameGraph, id: u32) !Resource.VirtualResource {
    if (self.resource_version.getPtr(id)) |ptr| {
        ptr.* += 1;
        return Resource.VirtualResource{
            .id = id,
            .version = ptr.*,
        };
    } else {
        return error.NoSuchResource;
    }
}

pub fn get_resource(self: *FrameGraph, id: u32) !Resource.Resource {
    const kind = self.resource_kind.get(id) orelse unreachable;

    return switch (kind) {
        .buffer => Resource.Resource{
            .buffer = self.buffer_storage.get_resource(id) orelse unreachable,
        },
        .texture2d => Resource.Resource{
            .texture2d = self.texture2d_storage.get_resource(id) orelse unreachable,
        },
        .custom => Resource.Resource{
            .custom = self.custom_resource_storage.get_resource(id) orelse unreachable,
        },
    };
}

fn topological_sort(self: *FrameGraph) !?[][]u32 {
    var in_degree = std.AutoHashMap(u32, u32).init(self.allocator);
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
        try adj_list.put(pass_id, .init(self.allocator));
    }

    for (self.passes.keys(), @as([]PassBuilder.Pass, self.passes.values())) |pass_id, pass| {
        for (pass.virtual_resource_write) |written_resource| {
            for (self.passes.keys(), @as([]PassBuilder.Pass, self.passes.values())) |other_pass_id, other_pass| {
                if (pass_id != other_pass_id and other_pass.reads_from(written_resource)) {
                    const adj_ptr = adj_list.getPtr(pass_id) orelse @panic("");
                    try adj_ptr.append(other_pass_id);

                    const in_degree_ptr = in_degree.getPtr(other_pass_id) orelse @panic("");
                    in_degree_ptr.* += 1;
                }
            }
        }
    }

    {
        var ite = in_degree.iterator();
        while (ite.next()) |entry| {
            std.log.info("Pass {} degree {}", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    var current_level: std.ArrayList(u32) = .init(self.allocator);
    defer current_level.deinit();

    var next_level: std.ArrayList(u32) = .init(self.allocator);
    defer next_level.deinit();

    var execution_order: std.ArrayList([]u32) = .init(self.allocator);
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

        try execution_order.append(try level.toOwnedSlice(self.allocator));
        std.mem.swap(std.ArrayList(u32), &current_level, &next_level);
    }

    if (total_processed == self.passes.count()) {
        return try execution_order.toOwnedSlice();
    } else {
        for (execution_order.items) |item| {
            self.allocator.free(item);
        }
        execution_order.deinit();
        return null;
    }
}

pub fn build_resources(self: *FrameGraph) !void {
    if (self.execution_order) |exec_order| {
        for (exec_order) |level| {
            for (level) |pass_id| {
                const pass = self.passes.get(pass_id) orelse unreachable;
                for (pass.virtual_resource_read) |r| {
                    const kind = self.resource_kind.get(r.id) orelse unreachable;
                    switch (kind) {
                        .buffer => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .texture2d => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .custom => {},
                    }
                }

                for (pass.virtual_resource_write) |r| {
                    const kind = self.resource_kind.get(r.id) orelse unreachable;
                    switch (kind) {
                        .buffer => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .texture2d => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .custom => {},
                    }
                }
            }
        }
    }
}

pub fn compile(self: *FrameGraph) !bool {
    if (self.execution_order) |exec_order| {
        for (exec_order) |list| {
            self.allocator.free(list);
        }
        self.allocator.free(exec_order);
    }

    if (try self.topological_sort()) |result| {
        self.execution_order = result;
        try self.build_resources();
        return true;
    } else {
        return false;
    }
}

pub fn execute(self: *FrameGraph, device: *Device) !void {
    if (self.execution_order) |exec_order| {
        for (exec_order) |level| {
            for (level) |pass_id| {
                const pass = self.passes.getPtr(pass_id) orelse unreachable;

                try pass.execution_callback(self, device, pass);
            }
        }
    }
}
