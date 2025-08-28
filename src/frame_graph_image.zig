const std = @import("std");
const gl = @import("gl4_6.zig");
const Generation = @import("frame_graph_resource.zig").Generation;
const Access = @import("frame_graph_resource.zig").Access;

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

pub const Extent = struct {
    width: u32,
    height: u32,
    depth: u32,

    pub fn @"2D"(width: u32, height: u32) Extent {
        return .{ .width = width, .height = height, .depth = 0 };
    }

    pub fn @"3D"(width: u32, height: u32, depth: u32) Extent {
        return .{ .width = width, .height = height, .depth = depth };
    }
};

pub const ID = struct {
    handle: u16,

    pub const invalid: ID = .{ .handle = 0 };

    pub fn eq(self: *const ID, other: *const ID) bool {
        return self.handle == other.handle;
    }
};

pub const UsageHints = packed struct {
    sampled: bool = false,
    storage: bool = false,
    color_attachment: bool = false,
    depth_attachment: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const Kind = enum {
    image_2d,
    image_2d_array,
    image_3d,
    image_cube,
};

pub const Description = struct {
    kind: Kind,
    extent: Extent,
    format: Format,
    layers: u32 = 1,
    samples: u32,

    pub fn eq(self: *const Description, other: *const Description) bool {
        var res: bool = true;
        inline for (std.meta.fields(Description)) |field| {
            res = res and (@field(self.*, field.name) == @field(other.*, field.name));
        }
        return res;
    }
};

pub const Reference = struct {
    id: ID,
    read_gen: Generation,
    write_gen: Generation,
    usage_hints: UsageHints,

    pub fn access(self: *const Reference) Access {
        return Access{
            .read = self.read_gen.is_valid(),
            .write = self.write_gen.is_valid(),
        };
    }

    pub fn read(self: *const Reference) bool {
        return self.read_gen.is_valid();
    }

    pub fn write(self: *const Reference) bool {
        return self.write_gen.is_valid();
    }
};
