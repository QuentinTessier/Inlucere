const std = @import("std");
const gl = @import("../../gl4_6.zig");

pub const Texture = @This();

handle: u32,
extent: Extent,
format: Format,

pub fn isLayered(self: *const Texture) bool {
    return switch (self.extent) {
        .@"1D", .@"2D", .Cube => false,
        else => true,
    };
}

pub const TextureType = enum {
    @"1D",
    @"2D",
    @"3D",
    Cube,
    @"1DArray",
    @"2DArray",
    CubeArray,
};

pub const Format = enum(u32) {
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

pub const TextureInternalFormat = enum(u32) {
    r = gl.RED,
    rg = gl.RG,
    rgb = gl.RGB,
    rgba = gl.RGBA,
    depth = gl.DEPTH_COMPONENT,
    stencil = gl.STENCIL_INDEX,
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

pub const Extent1D = struct {
    width: u32,
};

pub const Extent2D = struct {
    width: u32,
    height: u32,
};

pub const Extent3D = struct {
    width: u32,
    height: u32,
    depth: u32,
};

pub const Extent = union(TextureType) {
    @"1D": Extent1D,
    @"2D": Extent2D,
    @"3D": Extent3D,
    Cube: Extent2D,
    @"1DArray": Extent2D,
    @"2DArray": Extent2D,
    CubeArray: Extent3D,
};
