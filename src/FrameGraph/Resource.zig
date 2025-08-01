const std = @import("std");
const Device = @import("../Device.zig");

pub const ResourceKind = enum {
    buffer,
    texture2d,
    render_target,
};

pub const BufferDescription = struct {
    size: u32,
    stride: u32,
};

pub const Texture2DDescription = struct {
    width: u32,
    height: u32,
    format: Device.Texture.Format,
};

pub const Description = union(ResourceKind) {
    buffer: BufferDescription,
    texture2d: Texture2DDescription,
    render_target: Texture2DDescription, // TODO: Only allow valid Device.Texture.Format for rendering.
};

pub const Resource = union(ResourceKind) {
    buffer: struct {
        name: []const u8,
        handle: u32,
        description: BufferDescription,
    },
    texture2d: struct {
        name: []const u8,
        handle: u32,
        description: Texture2DDescription,
    },
    render_target: struct {
        name: []const u8,
        handle: u32,
        description: Texture2DDescription,
    },

    pub fn name(self: *const Resource) []const u8 {
        return switch (self.*) {
            .buffer => |b| b.name,
            .texture2d => |t| t.name,
            .render_target => |r| r.name,
        };
    }
};
