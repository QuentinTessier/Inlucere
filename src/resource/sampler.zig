const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const Sampler = @This();

handle: u32,
state: SamplerDesc,

pub fn init(self: *Sampler, desc: *const SamplerDesc) void {
    gl.createSamplers(1, @ptrCast(&self.handle));
    self.state = desc;

    gl.samplerParameteri(self.handle, gl.TEXTURE_MAG_FILTER, @intCast(@intFromEnum(desc.magFilter)));
    const minFilter: u32 = switch (desc.mipFilter) {
        .none => if (desc.minFilter == .linear) gl.LINEAR else gl.NEAREST,
        .linear => if (desc.magFilter == .linear) gl.LINEAR_MIPMAP_LINEAR else gl.NEAREST_MIPMAP_LINEAR,
        .nearest => if (desc.magFilter == .linear) gl.LINEAR_MIPMAP_NEAREST else gl.NEAREST_MIPMAP_NEAREST,
    };
    gl.samplerParameteri(self.handle, gl.TEXTURE_MIN_FILTER, @intCast(minFilter));

    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_S, @intCast(@intFromEnum(desc.wrapS)));
    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_R, @intCast(@intFromEnum(desc.wrapR)));
    gl.samplerParameteri(self.handle, gl.TEXTURE_WRAP_T, @intCast(@intFromEnum(desc.wrapT)));

    switch (desc.broderColor) {
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
    minLod: f32 = -1000.0,
    maxLod: f32 = 1000.0,
    lodBias: f32 = 0.0,
    minFilter: TextureFilter = .linear,
    magFilter: TextureFilter = .linear,
    mipFilter: TextureFilter = .none,
    wrapS: TextureWrap = .clampToEdge,
    wrapT: TextureWrap = .clampToEdge,
    wrapR: TextureWrap = .clampToEdge,
    broderColor: BorderColor = .{
        .float = .{ 0, 0, 0, 1 },
    },
};
