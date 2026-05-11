const std = @import("std");
const gl = @import("../gl4_6.zig");

const TextureHandle = @import("../Device2.zig").TextureHandle;
const Device = @import("../Device2.zig");
const Pass = @import("pass.zig");

const FBOKey = struct {
    color: [8]TextureHandle,
    color_count: u8,
    depth: ?TextureHandle,
};

pub const FBOCache = @This();

cache: std.AutoHashMapUnmanaged(FBOKey, u32),

pub fn get_or_create_fbo(self: *FBOCache, device: *Device, allocator: std.mem.Allocator, pass: *Pass.RGPass) !u32 {
    if (self.cache.get(key)) |fbo| return fbo;

    var fbo: u32 = 0;
    gl.createFramebuffers(1, &fbo);

    for (pass.color_attachments[0..@intCast(pass.color_attachment_count)], 0..) |attachment, i| {
        const text = 
    }
}
