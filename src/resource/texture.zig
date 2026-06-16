const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const TextureFormat = enum(u32) {
    r8 = gl.R8,
    r8_snorm = gl.R8_SNORM,
    r16 = gl.R16,
    r16_snorm = gl.R16_SNORM,
    rg8 = gl.RG8,
    rg8_snorm = gl.RG8_SNORM,
    rg16 = gl.RG16,
    rg16_snorm = gl.RG16_SNORM,
    r3_g3_b2 = gl.R3_G3_B2,
    rgb4 = gl.RGB4,
    rgb5 = gl.RGB5,
    rgb8 = gl.RGB8,
    rgb8_snorm = gl.RGB8_SNORM,
    rgb10 = gl.RGB10,
    rgb12 = gl.RGB12,
    rgb16_snorm = gl.RGB16_SNORM,
    rgba2 = gl.RGBA2,
    rgba4 = gl.RGBA4,
    rgb5_a1 = gl.RGB5_A1,
    rgba8 = gl.RGBA8,
    rgba8_snorm = gl.RGBA8_SNORM,
    rgb10_a2 = gl.RGB10_A2,
    rgb10_a2ui = gl.RGB10_A2UI,
    rgba12 = gl.RGBA12,
    rgba16 = gl.RGBA16,
    srgb8 = gl.SRGB8,
    srgb8_alpha8 = gl.SRGB8_ALPHA8,
    r16f = gl.R16F,
    rg16f = gl.RG16F,
    rgb16f = gl.RGB16F,
    rgba16f = gl.RGBA16F,
    r32f = gl.R32F,
    rg32f = gl.RG32F,
    rgb32f = gl.RGB32F,
    rgba32f = gl.RGBA32F,
    r11f_g11f_b10f = gl.R11F_G11F_B10F,
    rgb9_e5 = gl.RGB9_E5,
    r8i = gl.R8I,
    r8ui = gl.R8UI,
    r16i = gl.R16I,
    r16ui = gl.R16UI,
    r32i = gl.R32I,
    r32ui = gl.R32UI,
    rg8i = gl.RG8I,
    rg8ui = gl.RG8UI,
    rg16i = gl.RG16I,
    rg16ui = gl.RG16UI,
    rg32i = gl.RG32I,
    rg32ui = gl.RG32UI,
    rgb8i = gl.RGB8I,
    rgb8ui = gl.RGB8UI,
    rgb16i = gl.RGB16I,
    rgb16ui = gl.RGB16UI,
    rgb32i = gl.RGB32I,
    rgb32ui = gl.RGB32UI,
    rgba8i = gl.RGBA8I,
    rgba8ui = gl.RGBA8UI,
    rgba16i = gl.RGBA16I,
    rgba16ui = gl.RGBA16UI,
    rgba32i = gl.RGBA32I,
    rgba32ui = gl.RGBA32UI,

    df32 = gl.DEPTH_COMPONENT32F,
    d32 = gl.DEPTH_COMPONENT32,
    d24 = gl.DEPTH_COMPONENT24,
    d16 = gl.DEPTH_COMPONENT16,
    d32s8 = gl.DEPTH32F_STENCIL8,
    d24s8 = gl.DEPTH24_STENCIL8,
};

pub const TextureUsage = packed struct(u8) {
    sampled: bool = false,
    color_attachment: bool = false,
    depth_stencil_attachment: bool = false,
    storage: bool = false,
    _padding: u4 = 0,

    pub fn sampled_color_attachment() TextureUsage {
        return .{ .sampled = true, .color_attachment = true };
    }

    pub fn sampled_depth_attachment() TextureUsage {
        return .{ .sampled = true, .depth_stencil_attachment = true };
    }

    pub fn sampled_storage() TextureUsage {
        return .{ .sampled = true, .storage = true };
    }
};

pub const SampleCount = enum {
    @"1",
    @"2",
    @"4",
    @"8",

    pub fn samples(self: *const SampleCount) u32 {
        return switch (self.*) {
            .@"1" => 1,
            .@"2" => 2,
            .@"4" => 4,
            .@"8" => 8,
        };
    }
};

pub const Kind = enum(u32) {
    @"1d",
    @"2d",
    @"3d",
    @"1d_array",
    @"2d_array",
    cube,
    cube_array,
    @"2d_multisample",
    @"2d_array_multisample",
};

pub const TextureDesc = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    kind: Kind,

    mip_levels: u32 = 1,

    format: TextureFormat,
    usage: TextureUsage,
    samples: SampleCount = .@"1",
    debug_name: ?[]const u8 = null,

    pub fn target_flag(self: *const TextureDesc) u32 {
        return switch (self.kind) {
            .@"1d" => gl.TEXTURE_1D,
            .@"2d" => gl.TEXTURE_2D,
            .@"3d" => gl.TEXTURE_3D,
            .@"1d_array" => gl.TEXTURE_1D_ARRAY,
            .@"2d_array" => gl.TEXTURE_2D_ARRAY,
            .cube => gl.TEXTURE_CUBE_MAP,
            .cube_array => gl.TEXTURE_CUBE_MAP_ARRAY,
            .@"2d_multisample" => gl.TEXTURE_2D_MULTISAMPLE,
            .@"2d_array_multisample" => gl.TEXTURE_2D_MULTISAMPLE_ARRAY,
        };
    }

    pub fn validate_target(self: *const TextureDesc) void {
        switch (self.kind) {
            .@"1d" => std.debug.assert(self.height == 1 and self.depth == 1),
            .@"2d" => std.debug.assert(self.depth == 1),
            .@"1d_array" => std.debug.assert(self.depth == 1),
            .cube => std.debug.assert(self.height == self.width and self.depth == 1),
            .cube_array => std.debug.assert(self.depth == self.width),
            .@"2d_multisample" => std.debug.assert(self.depth == 1 and self.samples != .@"1"),
            .@"2d_array_multisample" => std.debug.assert(self.samples != .@"1"),
            .@"2d_array" => {},
            .@"3d" => {},
        }
    }
};

// TODO: Bindless texture support
pub const Texture = @This();

handle: u32,
kind: Kind,
dimensions: struct { width: u32, height: u32, depth: u32 },
format: TextureFormat,
usage: TextureUsage,
mip_levels: u32,

pub fn init(self: *Texture, desc: *const TextureDesc) !void {
    desc.validate_target();

    gl.createTextures(desc.target_flag(), 1, @ptrCast(&self.handle));

    self.dimensions = .{
        .width = desc.width,
        .height = desc.height,
        .depth = desc.depth,
    };
    self.kind = desc.kind;
    self.format = desc.format;
    self.usage = desc.usage;
    self.mip_levels = desc.mip_levels;

    switch (self.kind) {
        .@"1d" => gl.textureStorage1D(
            self.handle,
            @intCast(self.mip_levels),
            @intFromEnum(self.format),
            @intCast(self.dimensions.width),
        ),
        .@"2d", .@"1d_array", .cube => gl.textureStorage2D(
            self.handle,
            @intCast(self.mip_levels),
            @intFromEnum(self.format),
            @intCast(self.dimensions.width),
            @intCast(self.dimensions.height),
        ),
        .@"3d", .@"2d_array", .cube_array => gl.textureStorage3D(
            self.handle,
            @intCast(self.mip_levels),
            @intFromEnum(self.format),
            @intCast(self.dimensions.width),
            @intCast(self.dimensions.height),
            @intCast(self.dimensions.depth),
        ),
        .@"2d_multisample" => gl.textureStorage2DMultisample(
            self.handle,
            @intCast(desc.samples.samples()),
            @intFromEnum(self.format),
            @intCast(self.dimensions.width),
            @intCast(self.dimensions.height),
            gl.TRUE,
        ),
        .@"2d_array_multisample" => gl.textureStorage3DMultisample(
            self.handle,
            @intCast(desc.samples.samples()),
            @intFromEnum(self.format),
            @intCast(self.dimensions.width),
            @intCast(self.dimensions.height),
            @intCast(self.dimensions.depth),
            gl.TRUE,
        ),
    }

    if (desc.debug_name) |label| {
        gl.objectLabel(gl.TEXTURE, self.handle, @intCast(label.len), label.ptr);
    }
}

pub fn deinit(self: *const Texture, _: std.mem.Allocator) void {
    gl.deleteTextures(1, @ptrCast(&self.handle));
}

pub const Channels = packed struct {
    _r: bool = false,
    _g: bool = false,
    _b: bool = false,
    _a: bool = false,

    _depth: bool = false,
    _stencil: bool = false,

    pub fn rgba() Channels {
        return .{
            ._r = true,
            ._g = true,
            ._b = true,
            ._a = true,
        };
    }

    pub fn rgb() Channels {
        return .{
            ._r = true,
            ._g = true,
            ._b = true,
        };
    }

    pub fn rg() Channels {
        return .{
            ._r = true,
            ._g = true,
        };
    }

    pub fn r() Channels {
        return .{
            ._r = true,
        };
    }

    pub fn depth() Channels {
        return .{
            ._depth = true,
        };
    }

    pub fn stencil() Channels {
        return .{
            ._stencil = true,
        };
    }

    pub fn depth_stencil() Channels {
        return .{
            ._depth = true,
            ._stencil = true,
        };
    }

    pub fn flags(self: Channels) u32 {
        if (self._r and self._g and self._b and self._a) {
            return gl.RGBA;
        } else if (self._r and self._g and self._b) {
            return gl.RGB;
        } else if (self._r and self._g) {
            return gl.RG;
        } else if (self._r) {
            return gl.RED;
        } else if (self._depth and self._stencil) {
            return gl.DEPTH_STENCIL;
        } else if (self._depth) {
            return gl.DEPTH;
        } else if (self._stencil) {
            return gl.STENCIL;
        }
        return 0;
    }
};

pub const DataType = enum(u32) {
    u8 = gl.UNSIGNED_BYTE,
    i8 = gl.BYTE,
    u16 = gl.UNSIGNED_SHORT,
    i16 = gl.SHORT,
    u32 = gl.UNSIGNED_INT,
    i32 = gl.INT,
    f32 = gl.FLOAT,
    f16 = gl.HALF_FLOAT,
    u8_3_3_2 = gl.UNSIGNED_BYTE_3_3_2,
    u8_2_3_3 = gl.UNSIGNED_BYTE_2_3_3_REV,
    u16_5_6_5 = gl.UNSIGNED_SHORT_5_6_5,
    u16_5_6_5_rev = gl.UNSIGNED_SHORT_5_6_5_REV,
    u16_4_4_4_4 = gl.UNSIGNED_SHORT_4_4_4_4,
    u16_4_4_4_4_rev = gl.UNSIGNED_SHORT_4_4_4_4_REV,
    u16_5_5_5_1 = gl.UNSIGNED_SHORT_5_5_5_1,
    u16_1_5_5_5 = gl.UNSIGNED_SHORT_1_5_5_5_REV,
    u32_8_8_8_8 = gl.UNSIGNED_INT_8_8_8_8,
    u32_8_8_8_8_rev = gl.UNSIGNED_INT_8_8_8_8_REV,
    u32_10_10_10_2 = gl.UNSIGNED_INT_10_10_10_2,
    u32_2_10_10_10 = gl.UNSIGNED_INT_2_10_10_10_REV,
};

pub const TextureWriteData = struct {
    extent: struct { width: u32, height: u32, depth: u32 },
    offset: struct { width: u32 = 0, height: u32 = 0, depth: u32 = 0 } = .{},
    level: u32 = 0,
    channels: Channels,
    data_type: DataType,
    data: []const u8,
};

pub fn write(self: *const Texture, data: *const TextureWriteData) void {
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.pixelStorei(gl.PACK_ALIGNMENT, 1);
    defer {
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
        gl.pixelStorei(gl.PACK_ALIGNMENT, 4);
    }

    switch (self.kind) {
        .@"1d" => gl.textureSubImage1D(
            self.handle,
            @intCast(data.level),
            @intCast(data.offset.width),
            @intCast(data.extent.width),
            data.channels.flags(),
            @intFromEnum(data.data_type),
            data.data.ptr,
        ),
        .@"2d", .@"1d_array" => gl.textureSubImage2D(
            self.handle,
            @intCast(data.level),
            @intCast(data.offset.width),
            @intCast(data.offset.height),
            @intCast(data.extent.width),
            @intCast(data.extent.height),
            data.channels.flags(),
            @intFromEnum(data.data_type),
            data.data.ptr,
        ),
        .@"3d", .@"2d_array", .cube, .cube_array => gl.textureSubImage3D(
            self.handle,
            @intCast(data.level),
            @intCast(data.offset.width),
            @intCast(data.offset.height),
            @intCast(data.offset.depth),
            @intCast(data.extent.width),
            @intCast(data.extent.height),
            @intCast(data.extent.depth),
            data.channels.flags(),
            @intFromEnum(data.data_type),
            data.data.ptr,
        ),
        else => @panic("Can't write from CPU to this kind of texture"),
    }
}
