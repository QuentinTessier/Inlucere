const std = @import("std");
pub const Resource = @import("resources.zig");
const Device = @import("../Device.zig");
pub const PassBuilder = @import("pass_builder.zig");
const Pass = PassBuilder.Pass;

pub const FrameGraph = @This();

// Quick example to render a triangle, shaders is the same has DefaultTriangleExample
// We do not use pass color attachment at the moment. Swapchain is represented by a empty resource to manage dependency.
// %--------------------------------------------------------------------------------%
// var fg: Inlucere.FrameGraph = .init(allocator);
// defer fg.deinit();
//
// const swapchain = try fg.declare_custom_resource(null);
// const triangle_vertices = try fg.declare_managed_buffer(.fromBytes("triangle_vertices", std.mem.sliceAsBytes(&cpu_vertices), @sizeOf(f32) * 3));
//
// const swapchain_v1 = try fg.get_version(swapchain);
// const swapchain_v2 = try fg.declare_new_version(swapchain);
// const swapchain_v3 = try fg.declare_new_version(swapchain);
//
// const triangle_vertices_v1 = try fg.get_version(triangle_vertices);
//
// var clear_pass_builder = try Inlucere.FrameGraph.PassBuilder.init(allocator, "clear_swapchain", struct {
//     pub fn inline_callback(_: *Inlucere.FrameGraph, d: *Inlucere.Device, _: *Inlucere.FrameGraph.PassBuilder.Pass) !void {
//         d.clearSwapchain(.{
//             .colorLoadOp = .clear,
//         });
//     }
// }.inline_callback);
// _ = try clear_pass_builder.read(allocator, swapchain_v1);
// _ = try clear_pass_builder.write(allocator, swapchain_v2);
// _ = try fg.declare_pass(try clear_pass_builder.finalize(allocator));
//
// var default_triangle_pass = try Inlucere.FrameGraph.PassBuilder.init(allocator, "default_triangle", struct {
//     pub fn inline_callback(graph: *Inlucere.FrameGraph, d: *Inlucere.Device, pass: *Inlucere.FrameGraph.PassBuilder.Pass) !void {
//         // TODO: Better way
//         const vertex_buffer_id = pass.virtual_resource_read[1].id;
//         const buffer = graph.buffer_storage.get_resource(vertex_buffer_id) orelse unreachable;
//         if (d.bindGraphicPipeline("DefaultTriangle")) {
//             d.bindVertexBuffer(0, buffer.toBuffer(), 0, null);
//             d.draw(0, 3, 1, 0);
//         }
//     }
// }.inline_callback);
// _ = try default_triangle_pass.read(allocator, swapchain_v2);
// _ = try default_triangle_pass.read(allocator, triangle_vertices_v1);
// _ = try default_triangle_pass.write(allocator, swapchain_v3);
// _ = try fg.declare_pass(try default_triangle_pass.finalize(allocator));
//
// _ = try device.loadShader("DefaultTriangleProgram", &.{
//     .{
//         .source = @embedFile("./shaders/default_triangle.vert"),
//         .stage = .Vertex,
//     },
//     .{
//         .source = @embedFile("./shaders/default_triangle.frag"),
//         .stage = .Fragment,
//     },
// });
//
// _ = try device.createGraphicPipeline("DefaultTriangle", &.{
//     .programs = &.{
//         "DefaultTriangleProgram",
//     },
//     .vertexInputState = .{ .vertexAttributeDescription = &.{
//         .{ .location = 0, .binding = 0, .inputType = .vec3 },
//     } },
// });
//
// if (!try fg.compile()) {
//     std.log.err("Failed to compile", .{});
//     return;
// }
//
// while (!window.shouldClose()) {
//     glfw.pollEvents();
//     try fg.execute(&device);
//     window.swapBuffers();
// }

// TODO: Better way to access resource from Pass callback
// TODO: Use color attachments to build framebuffers
// TODO: Swapchain integration
// TODO: Resource aliasing/reuse

allocator: std.mem.Allocator,
next_item_id: u16,

resource_version: std.AutoHashMapUnmanaged(u16, struct { version: u16, kind: Resource.ResourceKind }),
buffer_storage: Resource.Storage(.buffer, Device.Buffer, Resource.BufferDescription),
texture2d_storage: Resource.Storage(.texture2d, Device.Texture2D, Resource.Texture2DDescription),
custom_resource_storage: Resource.Storage(.custom, ?*anyopaque, void),

passes: std.AutoArrayHashMapUnmanaged(u16, Pass),
execution_order: ?[][]u16,

pub fn init(allocator: std.mem.Allocator) FrameGraph {
    return FrameGraph{
        .allocator = allocator,
        .next_item_id = 1,
        .resource_version = .empty,
        .buffer_storage = .init(),
        .texture2d_storage = .init(),
        .custom_resource_storage = .init(),
        .passes = .empty,
        .execution_order = null,
    };
}

pub fn deinit(self: *FrameGraph) void {
    self.resource_version.deinit(self.allocator);

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

pub fn declare_pass(self: *FrameGraph, pass: Pass) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.passes.put(self.allocator, id, pass);
    return id;
}

pub fn declare_managed_buffer(self: *FrameGraph, desc: Resource.BufferDescription) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.buffer_storage.declare_managed(self.allocator, id, desc);
    try self.resource_version.put(self.allocator, id, .{
        .kind = .buffer,
        .version = 0,
    });
    return id;
}

pub fn declare_imported_buffer(self: *FrameGraph, obj: Device.DynamicBuffer, desc: ?Resource.BufferDescription) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.buffer_storage.declare_imported(self.allocator, id, obj, desc);
    try self.resource_version.put(self.allocator, id, .{
        .kind = .buffer,
        .version = 0,
    });
    return id;
}

pub fn declare_managed_texture2d(self: *FrameGraph, desc: Resource.Texture2DDescription) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.texture2d_storage.declare_managed(self.allocator, id, desc);
    try self.resource_version.put(self.allocator, id, .{
        .kind = .texture2d,
        .version = 0,
    });
    return id;
}

pub fn declare_imported_texture2d(self: *FrameGraph, obj: Device.Texture2D, desc: ?Resource.Texture2DDescription) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.texture2d_storage.declare_imported(self.allocator, id, obj, desc);
    try self.resource_version.put(self.allocator, id, .{
        .kind = .texture2d,
        .version = 0,
    });
    return id;
}

pub fn declare_custom_resource(self: *FrameGraph, obj: ?*anyopaque) !u16 {
    const id = self.next_item_id;
    self.next_item_id += 1;

    try self.custom_resource_storage.declare_imported(self.allocator, id, obj, void{});
    try self.resource_version.put(self.allocator, id, .{
        .kind = .custom,
        .version = 0,
    });
    return id;
}

pub fn get_version(self: *FrameGraph, id: u16) !Resource.VirtualResource {
    return if (self.resource_version.get(id)) |v| Resource.VirtualResource{ .id = id, .version = v.version, .kind = v.kind } else error.NoSuchResource;
}

pub fn declare_new_version(self: *FrameGraph, id: u16) !Resource.VirtualResource {
    if (self.resource_version.getPtr(id)) |ptr| {
        ptr.version += 1;
        return Resource.VirtualResource{
            .id = id,
            .version = ptr.version,
            .kind = ptr.kind,
        };
    } else {
        return error.NoSuchResource;
    }
}

pub fn get_resource(self: *FrameGraph, id: u16) !Resource.Resource {
    const t = self.resource_version.get(id) orelse unreachable;

    return switch (t.kind) {
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

fn topological_sort(self: *FrameGraph) !?[][]u16 {
    var in_degree = std.AutoHashMap(u16, u32).init(self.allocator);
    defer in_degree.deinit();

    var adj_list: std.AutoHashMap(u16, std.ArrayList(u16)) = .init(self.allocator);
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

    var current_level: std.ArrayList(u16) = .init(self.allocator);
    defer current_level.deinit();

    var next_level: std.ArrayList(u16) = .init(self.allocator);
    defer next_level.deinit();

    var execution_order: std.ArrayList([]u16) = .init(self.allocator);
    var total_processed: usize = 0;

    var in_degree_ite = in_degree.iterator();
    while (in_degree_ite.next()) |entry| {
        if (entry.value_ptr.* == 0) {
            try current_level.append(entry.key_ptr.*);
        }
    }

    while (current_level.items.len > 0) {
        var level: std.ArrayListUnmanaged(u16) = .empty;

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
        std.mem.swap(std.ArrayList(u16), &current_level, &next_level);
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
                    const t = self.resource_version.get(r.id) orelse unreachable;
                    switch (t.kind) {
                        .buffer => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .texture2d => _ = try self.buffer_storage.build_resource(self.allocator, r.id),
                        .custom => {},
                    }
                }

                for (pass.virtual_resource_write) |r| {
                    const t = self.resource_version.get(r.id) orelse unreachable;
                    switch (t.kind) {
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
