const std = @import("std");
const TextureHandle = @import("../Device2.zig").TextureHandle;
const BufferHandle = @import("../Device2.zig").BufferHandle;
const Texture = @import("../resource/texture.zig");
const Buffer = @import("../resource/buffer.zig");

pub const RGTextureHandle = struct { id: u16 };
pub const RGBufferHandle = struct { id: u16 };

pub const ResourceKind = enum {
    transient,
    imported,
};

pub const RGTextureDesc = union(ResourceKind) {
    transient: Texture.TextureDesc,
    imported: TextureHandle,
};

pub const RGBufferDesc = union(ResourceKind) {
    transient: Buffer.BufferDesc,
    imported: BufferHandle,
};

pub const PassType = enum { graphics, compute };

pub const PassContext = struct {};

pub const BarrierBits = packed struct(u32) {};

pub const RGPass = struct {
    name: []const u8,
    type: PassType,

    tex_reads: []RGTextureHandle = undefined,
    tex_writes: []RGTextureHandle = undefined,

    buf_reads: []RGBufferHandle = undefined,
    buf_writes: []RGBufferHandle = undefined,

    color_attachments: [8]RGTextureHandle = undefined,
    color_attachment_count: u8 = 0,
    depth_attachment: ?RGTextureHandle,

    execute_fn: *const fn (ctx: *anyopaque, pass: PassContext) void,
    execute_ctx: *anyopaque,

    barrier_before: BarrierBits = .{},
    ref_count: u32 = 0,
};
