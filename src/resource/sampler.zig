const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const Sampler = @This();

handle: u32,
state: SamplerDesc,

pub fn init(self: *Sampler, desc: *const SamplerDesc) !void {
    gl.createSamplers(1, @ptrCast(&self.handle));
    self.state = desc.*;

    gl.samplerParameteri(self.handle, gl.TEXTURE_MAG_FILTER, @intCast(@intFromEnum(desc.mag_filter)));
    const minFilter: u32 = switch (desc.mip_filter) {
        .none => if (desc.min_filter == .linear) gl.LINEAR else gl.NEAREST,
        .linear => if (desc.mag_filter == .linear) gl.LINEAR_MIPMAP_LINEAR else gl.NEAREST_MIPMAP_LINEAR,
        .nearest => if (desc.mag_filter == .linear) gl.LINEAR_MIPMAP_NEAREST else gl.NEAREST_MIPMAP_NEAREST,
    };
    gl.samplerParameteri(self.handle, gl.TEXTURE_MIN_FILTER, @intCast(minFilter));

    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_S, @intCast(@intFromEnum(desc.wrap_s)));
    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_R, @intCast(@intFromEnum(desc.wrap_r)));
    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_T, @intCast(@intFromEnum(desc.wrap_t)));

    switch (desc.broder_color) {
        .float => |color| {
            gl.samplerParameterfv(self.handle, gl.TEXTURE_BORDER_COLOR, (&color).ptr);
        },
        .integer => |color| {
            gl.samplerParameteriv(self.handle, gl.TEXTURE_BORDER_COLOR, (&color).ptr);
        },
    }
}

pub fn deinit(self: *Sampler, _: void) void {
    gl.deleteSamplers(1, @ptrCast(&self.handle));
}

pub fn eql(self: Sampler, other: Sampler) bool {
    return std.mem.eql(SamplerDesc, &.{self.state}, &.{other.state});
}

pub const TextureFilter = enum(u32) {
    none = 0,
    nearest = gl.NEAREST,
    linear = gl.LINEAR,
};

pub const TextureWrap = enum(u32) {
    clampToEdge = gl.CLAMP_TO_EDGE,
    mirroredRepeat = gl.MIRRORED_REPEAT,
    repeat = gl.REPEAT,
    mirrorClampToEdge = gl.MIRROR_CLAMP_TO_EDGE,
};

pub const BorderColor = union(enum(u32)) {
    float: [4]f32,
    integer: [4]i32,
};

pub const SamplerDesc = struct {
    min_lod: f32 = -1000.0,
    max_lod: f32 = 1000.0,
    lod_bias: f32 = 0.0,
    min_filter: TextureFilter = .linear,
    mag_filter: TextureFilter = .linear,
    mip_filter: TextureFilter = .none,
    wrap_s: TextureWrap = .clampToEdge,
    wrap_t: TextureWrap = .clampToEdge,
    wrap_r: TextureWrap = .clampToEdge,
    broder_color: BorderColor = .{
        .float = .{ 0, 0, 0, 1 },
    },
};
