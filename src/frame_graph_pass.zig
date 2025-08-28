const std = @import("std");
const FrameGraph = @import("frame_graph.zig");
const Resource = @import("frame_graph_resource.zig");

pub const Pass = @This();

pub const ID = struct {
    handle: u16,

    pub const invalid: ID = .{ .handle = 0 };

    pub fn eq(self: *const ID, other: *const ID) bool {
        return self.handle == other.handle;
    }

    pub fn is_valid(self: *const ID) bool {
        return self.handle != 0;
    }
};

name: []u8,
id: Pass.ID,
owner: *FrameGraph,
has_side_effects: bool,
rc: u32,
images: std.ArrayListUnmanaged(Resource.Image.Reference),
buffers: std.ArrayListUnmanaged(Resource.Buffer.Reference),

pub fn has_reference_to_image(self: *const Pass, searched: Resource.Image.ID) bool {
    for (self.images.items) |*img_ref| {
        if (img_ref.id.eq(&searched)) {
            return true;
        }
    }
    return false;
}

pub fn has_reference_to_buffer(self: *const Pass, searched: Resource.Buffer.ID) bool {
    for (self.buffers.items) |*buf_ref| {
        if (buf_ref.id.eq(&searched)) {
            return true;
        }
    }
    return false;
}

pub fn is_reading_image(self: *const Pass, searched: *const Resource.Image.Reference) bool {
    for (self.images.items) |*img_ref| {
        if (img_ref.id.eq(&searched.id) and img_ref.read_gen.eq(&searched.write_gen)) {
            return true;
        }
    }
    return false;
}

pub fn is_reading_buffer(self: *const Pass, searched: *const Resource.Buffer.Reference) bool {
    for (@as([]const Resource.Buffer.Reference, self.buffers.items)) |*buf_ref| {
        if (buf_ref.id.eq(&searched.id) and buf_ref.read_gen.eq(&searched.write_gen)) {
            return true;
        }
    }
    return false;
}

pub fn is_writing_image(self: *const Pass, searched: *const Resource.Image.Reference) bool {
    for (self.images.items) |*img_ref| {
        if (img_ref.id.eq(&searched.id) and img_ref.write_gen.eq(&searched.read_gen)) {
            return true;
        }
    }
    return false;
}

pub fn is_writing_buffer(self: *const Pass, searched: *const Resource.Buffer.Reference) bool {
    for (@as([]const Resource.Buffer.Reference, self.buffers.items)) |*buf_ref| {
        if (buf_ref.id.eq(&searched.id) and buf_ref.write_gen.eq(&searched.read_gen)) {
            return true;
        }
    }
    return false;
}

pub fn image(self: *Pass, allocator: std.mem.Allocator, image_id: Resource.Image.ID, access: Resource.Access, usage_hints: Resource.Image.UsageHints) !void {
    _ = .{ allocator, image_id, access, usage_hints };
    if (self.owner.virt_id_to_img.get(image_id)) |index| {
        const version: *Resource.Generation = &self.owner.virt_images.items(.generation)[index];
        const read_generation = if (access.read) version.* else Resource.Generation.invalid;
        const write_generation = if (access.write) blk: {
            version.* = version.next();
            break :blk version.*;
        } else Resource.Generation.invalid;

        try self.images.append(allocator, Resource.Image.Reference{
            .id = image_id,
            .read_gen = read_generation,
            .write_gen = write_generation,
            .usage_hints = usage_hints,
        });
    } else {
        return error.NoSuchImg;
    }
}

pub fn buffer(self: *Pass, allocator: std.mem.Allocator, buffer_id: Resource.Buffer.ID, access: Resource.Access, usage_hints: Resource.Buffer.UsageHints) !void {
    if (self.owner.virt_id_to_buf.get(buffer_id)) |index| {
        const version: *Resource.Generation = &self.owner.virt_buffers.items(.generation)[index];
        const read_generation = if (access.read) version.* else Resource.Generation.invalid;
        const write_generation = if (access.write) blk: {
            version.* = version.next();
            break :blk version.*;
        } else Resource.Generation.invalid;

        try self.buffers.append(allocator, Resource.Buffer.Reference{
            .id = buffer_id,
            .read_gen = read_generation,
            .write_gen = write_generation,
            .usage_hints = usage_hints,
        });
    } else {
        return error.NoSuchImg;
    }
}

pub fn create_image(self: *Pass, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Image.Description, usage_hints: Resource.Image.UsageHints) !Resource.Image.ID {
    const id = try self.owner.declare_image(allocator, debug_name, desc);
    try self.images.append(allocator, Resource.Image.Reference{
        .id = id,
        .read_gen = .invalid,
        .write_gen = .default,
        .usage_hints = usage_hints,
    });
    return id;
}

pub fn create_buffer(self: *Pass, allocator: std.mem.Allocator, debug_name: ?[]const u8, desc: Resource.Buffer.Description, usage_hints: Resource.Buffer.UsageHints) !Resource.Buffer.ID {
    const id = try self.owner.declare_buffer(allocator, debug_name, desc);
    try self.buffers.append(allocator, Resource.Buffer.Reference{
        .id = id,
        .read_gen = .invalid,
        .write_gen = .default,
        .usage_hints = usage_hints,
    });
    return id;
}

// Mark the Pass with side effects avoiding it to be culled (this should be temporary and might be replaced by a swapchain resource that signal that we should never cull the pass)
pub fn present(self: *Pass) void {
    self.has_side_effects = true;
}
