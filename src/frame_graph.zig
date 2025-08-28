const std = @import("std");
pub const Resource = @import("frame_graph_resource.zig");

pub const FrameGraph = @This();

id_counter: u16,

virt_images: std.MultiArrayList(struct {
    base: Resource.Base,
    desc: Resource.Image.Description,
    generation: Resource.Generation,
}),
virt_id_to_img: std.AutoHashMapUnmanaged(Resource.Image.ID, usize),

virt_buffers: std.MultiArrayList(struct {
    base: Resource.Base,
    desc: Resource.Buffer.Description,
    generation: Resource.Generation,
}),
virt_id_to_buf: std.AutoHashMapUnmanaged(Resource.Buffer.ID, usize),

pub fn init() FrameGraph {
    return FrameGraph{
        .id_counter = 1,
        .virt_images = .empty,
        .virt_id_to_img = .empty,
        .virt_buffers = .empty,
        .virt_id_to_buf = .empty,
    };
}

pub fn deinit(self: *FrameGraph, allocator: std.mem.Allocator) void {
    self.virt_images.deinit(allocator);
    self.virt_id_to_img.deinit(allocator);

    self.virt_buffers.deinit(allocator);
    self.virt_id_to_buf.deinit(allocator);
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

pub fn declare_image(self: *FrameGraph, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Image.Description) !Resource.Image.ID {
    const id = self.next_image_id();

    const index = try self.virt_images.addOne(allocator);
    self.virt_images.items(.base)[index] = Resource.Base{
        .debug_name = debug_name,
        .imported = false,
    };
    self.virt_images.items(.desc)[index] = desc;
    self.virt_images.items(.generation)[index] = .default;

    try self.virt_id_to_img.put(allocator, id, index);
    return id;
}

pub fn declare_buffer(self: *FrameGraph, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Buffer.Description) !Resource.Buffer.ID {
    const id = self.next_buffer_id();

    const index = try self.virt_buffers.addOne(allocator);
    self.virt_buffers.items(.base)[index] = Resource.Base{
        .debug_name = debug_name,
        .imported = false,
    };
    self.virt_buffers.items(.desc)[index] = desc;
    self.virt_buffers.items(.generation)[index] = .default;

    try self.virt_id_to_buf.put(allocator, id, index);
    return id;
}
