const std = @import("std");
const Device = @import("../Device.zig");
const gl = @import("../gl4_6.zig");

pub const ResourceId = packed struct(u32) {
    kind: ResourceKind,
    id: u31,
};

pub const ResourceType = enum {
    buffer,
    texture,
    render_target,
};

pub const ResourceKind = enum(u1) {
    managed,
    free,
};

pub fn ResourceKindFreeType(comptime type_: ResourceType) type {
    return switch (type_) {
        .buffer => FreeResource.Buffer,
        .texture, .render_target => FreeResource.Texture,
    };
}

pub const ResourceUsage = enum {
    read,
    write,
    read_write,
};

pub const ResourceReference = struct {
    id: ResourceId,
    usage: ResourceUsage,
};

pub const ResourceBufferDescription = struct {
    size: u32,
    stride: u32,
    usage: enum { vertex, index, uniform, storage },
};

pub const ResourceTextureDescription = struct {
    width: u32,
    height: u32,
    lod: u32,
    format: Device.Texture.Format,
    samples: u32 = 1,
};

pub const ResourceDescription = union(ResourceType) {
    buffer: ResourceBufferDescription,
    texture: ResourceTextureDescription,
    render_target: ResourceTextureDescription,
};

pub const ManagedResource = struct {
    pub const Buffer = struct {
        handle: u32,
        description: ResourceBufferDescription,
        created: bool = false,
    };

    pub const Texture = struct {
        handle: u32,
        description: ResourceTextureDescription,
        created: bool = false,
    };
};

pub const FreeResource = struct {
    pub const Buffer = struct {
        handle: u32,
        description: ResourceBufferDescription,
    };

    pub const Texture = struct {
        handle: u32,
        description: ResourceTextureDescription,
    };
};

pub const ResourceManager = struct {
    device: *Device,

    managed_resources: struct {
        buffer_pool: std.AutoArrayHashMapUnmanaged(ResourceId, ManagedResource.Buffer),
        texture_pool: std.AutoArrayHashMapUnmanaged(ResourceId, ManagedResource.Texture),
    },
    free_resources: struct {
        buffer_pool: std.AutoArrayHashMapUnmanaged(ResourceId, FreeResource.Buffer),
        texture_pool: std.AutoArrayHashMapUnmanaged(ResourceId, FreeResource.Texture),
    },

    resource_descriptions: std.AutoHashMapUnmanaged(ResourceId, ResourceDescription),

    next_resource_id: u31,

    pub fn init(device: *Device) ResourceManager {
        return .{
            .device = device,
            .managed_resources = .{
                .buffer_pool = .empty,
                .texture_pool = .empty,
            },
            .free_resources = .{
                .buffer_pool = .empty,
                .texture_pool = .empty,
            },
            .resource_descriptions = .empty,
            .next_resource_id = 1,
        };
    }

    pub fn deinit(self: *ResourceManager, allocator: std.mem.Allocator) void {
        var managed_buffer_pool_ite = self.managed_resources.buffer_pool.iterator();
        while (managed_buffer_pool_ite.next()) |entry| {
            gl.deleteBuffers(1, @intCast(&entry.value_ptr.handle));
        }
        self.managed_resources.buffer_pool.deinit(allocator);

        var managed_texture_pool_ite = self.managed_resources.texture_pool.iterator();
        while (managed_texture_pool_ite.next()) |entry| {
            gl.deleteTextures(1, @intCast(&entry.value_ptr.handle));
        }
        self.managed_resources.texture_pool.deinit(allocator);

        self.free_resources.buffer_pool.deinit(allocator);
        self.free_resources.texture_pool.deinit(allocator);
        self.resource_descriptions.deinit(allocator);
    }

    pub fn add_managed_resource(self: *ResourceManager, allocator: std.mem.Allocator, description: ResourceDescription) !ResourceId {
        const id = self.next_resource_id;
        self.next_resource_id += 1;
        try self.resource_descriptions.put(allocator, ResourceId{
            .kind = .managed,
            .id = id,
        }, description);

        return ResourceId{
            .kind = .managed,
            .id = id,
        };
    }

    pub fn add_free_resource(self: *ResourceManager, comptime type_: ResourceType, allocator: std.mem.Allocator, description: ResourceDescription, resource: ResourceKindFreeType(type_)) !ResourceId {
        const id = self.next_resource_id;
        self.next_resource_id += 1;

        try self.resource_descriptions.put(allocator, ResourceId{
            .kind = .managed,
            .id = id,
        }, description);
        switch (type_) {
            .buffer => try self.free_resources.buffer_pool.put(allocator, ResourceId{ .kind = .managed, .id = id }, resource),
            .texture, .render_target => try self.free_resources.texture_pool.put(allocator, ResourceId{ .kind = .managed, .id = id }, resource),
        }
    }

    pub fn get_buffer(self: *ResourceManager, id: ResourceId) ?Device.Buffer {
        switch (id.kind) {
            .managed => {
                if (self.managed_resources.buffer_pool.get(id)) |entry| {
                    if (entry.created) {
                        return Device.Buffer{
                            .handle = entry.handle,
                            .size = entry.description.size,
                            .stride = entry.description.stride,
                        };
                    }
                }
                return null;
            },
            .free => {
                if (self.free_resources.buffer_pool.get(id)) |entry| {
                    return Device.Buffer{
                        .handle = entry.handle,
                        .size = entry.description.size,
                        .stride = entry.description.stride,
                    };
                }
                return null;
            },
        }
    }

    pub fn get_texture(self: *ResourceManager, id: ResourceId) ?Device.Texture {
        switch (id.kind) {
            .managed => {
                if (self.managed_resources.texture_pool.get(id)) |entry| {
                    if (entry.created) {
                        return Device.Texture{
                            .handle = entry.handle,
                            .extent = .{
                                .@"2D" = .{
                                    .width = entry.description.width,
                                    .height = entry.description.height,
                                },
                            },
                            .format = entry.description.format,
                        };
                    }
                }
                return null;
            },
            .free => {
                if (self.free_resources.texture_pool.get(id)) |entry| {
                    return Device.Texture{
                        .handle = entry.handle,
                        .extent = .{
                            .@"2D" = .{
                                .width = entry.description.width,
                                .height = entry.description.height,
                            },
                        },
                        .format = entry.description.format,
                    };
                }
                return null;
            },
        }
    }
};
