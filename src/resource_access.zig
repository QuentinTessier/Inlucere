const BarrierBits = @import("barrier.zig").BarrierBits;
pub const PassType = enum { graphics, compute, transfer };
const gl = @import("gl4_6.zig");
const std = @import("std");
const Device = @import("device.zig");

pub const BufferResourceAccess = enum {
    ssbo_write,
    ssbo_read,
    uniform_read,
    vertex_read,
    index_read,
    command_read,
    update_write,
    host_read,
    host_write,
    transform_feedback_write,
    transform_feedback_read,
    query_buffer_write,
    query_buffer_read,

    pub fn is_write(self: BufferResourceAccess) bool {
        return switch (self) {
            .ssbo_write, .update_write, .host_write, .transform_feedback_write, .query_buffer_write => true,
            else => false,
        };
    }

    pub fn transition(_: BufferResourceAccess, next: BufferResourceAccess) u32 {
        return switch (next) {
            .ssbo_read, .ssbo_write => gl.SHADER_STORAGE_BARRIER_BIT,
            .uniform_read => gl.UNIFORM_BARRIER_BIT,
            .vertex_read => gl.VERTEX_ATTRIB_ARRAY_BARRIER_BIT,
            .index_read => gl.ELEMENT_ARRAY_BARRIER_BIT,
            .command_read => gl.COMMAND_BARRIER_BIT,
            .update_write => gl.BUFFER_UPDATE_BARRIER_BIT,
            .host_read, .host_write => gl.CLIENT_MAPPED_BUFFER_BARRIER_BIT,
            .transform_feedback_write, .transform_feedback_read => gl.TRANSFORM_FEEDBACK_BARRIER_BIT,
            .query_buffer_write, .query_buffer_read => gl.QUERY_BUFFER_BARRIER_BIT,
            else => null,
        };
    }
};

pub const TextureResourceAccess = enum {
    image_read,
    image_write,
    sampled_read,
    color_attachment_write,
    depth_attachment_write,
    update_write,
    update_read,
    mipmap_generation,

    pub fn is_write(self: TextureResourceAccess) bool {
        return switch (self) {
            .image_write, .color_attachment_write, .depth_attachment_write, .update_write, .mipmap_generation => true,
            else => false,
        };
    }

    pub fn transition(_: TextureResourceAccess, next: TextureResourceAccess) u32 {
        return switch (next) {
            .image_read, .image_write => gl.SHADER_IMAGE_ACCESS_BARRIER_BIT,
            .sampled_read => gl.TEXTURE_FETCH_BARRIER_BIT,
            .color_attachment_write, .depth_attachment_write => gl.FRAMEBUFFER_BARRIER_BIT,
            .update_write, .update_read, .mipmap_generation => gl.TEXTURE_UPDATE_BARRIER_BIT,
        };
    }
};

const TextureResource = union(enum) {
    idle: void,
    pending_write: TextureResourceAccess,
    pending_read: TextureResourceAccess,
};

pub const ResourceAccessManager = struct {
    allocator: std.mem.Allocator,
    textures: std.AutoHashMapUnmanaged(Device.TextureHandle, TextureResource),

    pub fn init(allocator: std.mem.Allocator) ResourceAccessManager {
        return .{
            .allocator = allocator,
            .buffers = .empty,
            .textures = .empty,
        };
    }

    pub fn deinit(self: *ResourceAccessManager) void {
        self.textures.deinit(self.allocator);
    }

    pub fn update_texture(self: *ResourceAccessManager, h: Device.TextureHandle, access: TextureResourceAccess) !?u32 {
        const entry = try self.textures.getOrPut(self.allocator, h);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .pending_write = if (access.is_write()) access else null,
                .pending_read = if (!access.is_write()) access else null,
            };
            return null;
        }

        const tex = entry.value_ptr;
        switch (tex.*) {
            .idle => {
                if (access.is_write()) {
                    tex.* = @unionInit(TextureResource, "pending_write", access);
                } else {
                    tex.* = @unionInit(TextureResource, "pending_read", access);
                }
                return null;
            },
            .pending_write => |prev| {
                const bit = prev.transition(access);
                if (access.is_write()) {
                    tex.* = @unionInit(TextureResource, "pending_write", access);
                } else {
                    tex.* = @unionInit(TextureResource, "pending_read", access);
                }

                // Guard against incoherent writes since we do not expose `write_only`, `read_only` and `read_write` and coherent/incoherent resource access.
                if (!access.is_write() or prev == .image_write or access == .image_write) {
                    return bit;
                }
                return null;
            },
            .pending_read => |prev| {
                if (!access.is_write()) {
                    tex.pending_read = access;
                    return null;
                }

                const bit = prev.transition(access);
                tex.* = @unionInit(TextureResource, "pending_write", access);
                return bit;
            },
        }
    }
};
