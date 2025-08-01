const std = @import("std");
const Pass = @import("Pass.zig");
const Resource = @import("Resources.zig");
const Device = @import("../Device.zig");

pub const FrameGraph = @This();

allocator: std.mem.Allocator,
device: *Device,
resources: Resource.ResourceManager,

passes: std.AutoArrayHashMapUnmanaged(Pass.PassId, Pass.PassDescription),
pass_dependencies: std.AutoArrayHashMapUnmanaged(
    Pass.PassId,
    std.ArrayListUnmanaged(Pass.PassId),
),
execution_order: std.ArrayListUnmanaged(Pass.PassId),

next_pass_id: Pass.PassId = 1,

pub fn init(allocator: std.mem.Allocator, device: *Device) FrameGraph {
    return FrameGraph{
        .allocator = allocator,
        .device = device,
        .resources = .init(device),
        .passes = .empty,
        .pass_dependencies = .empty,
        .execution_order = .empty,
    };
}

pub fn deinit(self: *FrameGraph) void {
    self.resources.deinit(self.allocator);
    self.passes.deinit(self.allocator);

    var ite = self.pass_dependencies.iterator();
    while (ite.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.pass_dependencies.deinit(self.allocator);
}

pub fn add_pass(self: *FrameGraph, desc: Pass.PassDescription) !Pass.PassId {
    const pass_id = self.next_pass_id;
    self.next_pass_id += 1;

    try self.passes.put(self.allocator, pass_id, desc);

    return pass_id;
}

pub fn add_managed_resource(self: *FrameGraph, desc: Resource.ResourceDescription) !Resource.ResourceId {
    return self.resources.add_managed_resource(self.allocator, desc);
}

pub fn add_free_resource(self: *FrameGraph, comptime type_: Resource.ResourceType, description: Resource.ResourceDescription, resource: Resource.ResourceKindFreeType(type_)) !Resource.ResourceId {
    return self.resources.add_free_resource(type_, self.allocator, description, resource);
}

fn build_dependency_graph(self: *FrameGraph) !void {
    var dep_iter = self.pass_dependencies.iterator();
    while (dep_iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.pass_dependencies.clearRetainingCapacity();

    var resource_writer = std.AutoHashMap(Resource.ResourceId, Pass.PassId).init(self.allocator);
    defer resource_writer.deinit();

    var resource_reader = std.AutoHashMap(Resource.ResourceId, std.ArrayList(Pass.PassId)).init(self.allocator);
    defer {
        var reader_iter = resource_reader.iterator();
        while (reader_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        resource_reader.deinit();
    }

    var pass_iter = self.passes.iterator();
    while (pass_iter.next()) |entry| {
        const pass_id = entry.key_ptr.*;
        const pass_desc = entry.value_ptr;

        for (pass_desc.inputs) |input| {
            if (input.usage == .read or input.usage == .read_write) {
                if (resource_reader.getPtr(input.id)) |list| {
                    try list.append(pass_id);
                } else {
                    var list: std.ArrayList(Pass.PassId) = .init(self.allocator);
                    try list.append(pass_id);
                    try resource_reader.put(input.id, list);
                }
            }
        }

        for (pass_desc.outputs) |output| {
            if (output.usage == .write or output.usage == .read_write) {
                try resource_writer.put(output.id, pass_id);
            }
        }
    }

    pass_iter.reset();
    for (pass_iter.next()) |entry| {
        const pass_id: Pass.PassId = entry.key_ptr.*;
        const pass_desc: *Pass.PassDescription = entry.value_ptr;

        var dependencies: std.ArrayListUnmanaged(Pass.PassId) = .empty;
        for (pass_desc.inputs) |input| {
            if (resource_writer.get(input.id)) |writer_pass| {
                if (writer_pass != pass_id) {
                    try dependencies.append(self.allocator, writer_pass);
                }
            }
        }

        try self.pass_dependencies.put(pass_id, dependencies);
    }
}

fn topological_sort(self: *FrameGraph) !void {
    var in_degree = std.AutoHashMap(Pass.PassId, u32).init(self.allocator);
    defer in_degree.deinit();

    for (self.passes.keys()) |id| {
        try in_degree.put(id, 0);
    }

    var dep_iter = self.pass_dependencies.iterator();
    while (dep_iter.next()) |entry| {
        for (entry.value_ptr.items) |_| {
            const current_degree = in_degree.get(entry.key_ptr.*) orelse 0;
            try in_degree.put(entry.key_ptr.*, current_degree + 1);
        }
    }
}

pub fn compile(self: *FrameGraph) !void {
    self.execution_order.clearRetainingCapacity();
}
