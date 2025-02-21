const std = @import("std");
const gl = @import("../gl4_6.zig");

const Sampler = @import("./Sampler.zig");
const BindlessTexture = @import("./BindlessTexture.zig");

pub const Texture = @This();

pub const Extent = struct {
    width: u32,
    height: u32,
    depth: u32,
};

handle: u32,
isBindless: bool = false,
type: ImageType,
extent: Extent,
format: Format,
mipLevels: u32,

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

pub const ImageType = enum(u32) {
    _2D,
    _3D,
    _1DArray,
    _2DArray,
    cubeMap,
    cubeMapArray,
    _2DMultiSample,
    _3DMultiSample,

    pub fn toGL(t: ImageType) u32 {
        return switch (t) {
            ._2D => gl.TEXTURE_2D,
            ._3D => gl.TEXTURE_3D,
            ._1DArray => gl.TEXTURE_1D_ARRAY,
            ._2DArray => gl.TEXTURE_2D_ARRAY,
            .cubeMap => gl.TEXTURE_CUBE_MAP,
            .cubeMapArray => gl.TEXTURE_CUBE_MAP_ARRAY,
            ._2DMultiSample => gl.TEXTURE_2D_MULTISAMPLE,
            ._3DMultiSample => gl.TEXTURE_2D_MULTISAMPLE_ARRAY,
        };
    }
};

pub const TextureCreateInfo = struct {
    type: ImageType,
    extent: Extent,
    format: Format,
    mipLevels: u32 = 1,
};

pub fn init(self: *Texture, name: ?[]const u8, info: *const TextureCreateInfo) void {
    var handle: u32 = 0;
    gl.createTextures(info.type.toGL(), 1, @ptrCast(&handle));
    switch (info.type) {
        ._2D, ._1DArray, .cubeMap => gl.textureStorage2D(
            handle,
            @intCast(info.mipLevels),
            @intFromEnum(info.format),
            @intCast(info.extent.width),
            @intCast(info.extent.height),
        ),
        ._2DMultiSample => gl.textureStorage2DMultisample(
            handle,
            @intCast(info.mipLevels),
            @intFromEnum(info.format),
            @intCast(info.extent.width),
            @intCast(info.extent.height),
            gl.TRUE,
        ),
        ._3D, ._2DArray, .cubeMapArray => gl.textureStorage3D(
            handle,
            @intCast(info.mipLevels),
            @intFromEnum(info.format),
            @intCast(info.extent.width),
            @intCast(info.extent.height),
            @intCast(info.extent.depth),
        ),
        ._3DMultiSample => gl.textureStorage3DMultisample(
            handle,
            @intCast(info.mipLevels),
            @intFromEnum(info.format),
            @intCast(info.extent.width),
            @intCast(info.extent.height),
            @intCast(info.extent.depth),
            gl.TRUE,
        ),
    }

    if (name) |n| {
        gl.objectLabel(gl.TEXTURE, handle, @intCast(n.len), n.ptr);
    }

    self.* = .{
        .handle = handle,
        .type = info.type,
        .extent = info.extent,
        .format = info.format,
        .mipLevels = info.mipLevels,
    };
}

pub fn generateBindlessTexture(self: *Texture, state: Sampler.SamplerState) BindlessTexture {
    const minFilter: u32 = switch (state.mipFilter) {
        .none => if (state.minFilter == .linear) gl.LINEAR else gl.NEAREST,
        .linear => if (state.magFilter == .linear) gl.LINEAR_MIPMAP_LINEAR else gl.NEAREST_MIPMAP_LINEAR,
        .nearest => if (state.magFilter == .linear) gl.LINEAR_MIPMAP_NEAREST else gl.NEAREST_MIPMAP_NEAREST,
    };
    gl.textureParameteri(self.handle, gl.TEXTURE_MAG_FILTER, @intCast(@intFromEnum(state.magFilter)));
    gl.textureParameteri(self.handle, gl.TEXTURE_MIN_FILTER, @intCast(minFilter));
    switch (state.broderColor) {
        .float => |color| {
            gl.textureParameterfv(self.handle, gl.TEXTURE_BORDER_COLOR, (&color).ptr);
        },
        .integer => |color| {
            gl.textureParameteriv(self.handle, gl.TEXTURE_BORDER_COLOR, (&color).ptr);
        },
    }
    gl.textureParameteri(self.handle, gl.TEXTURE_WRAP_R, @intCast(@intFromEnum(state.wrapR)));
    gl.textureParameteri(self.handle, gl.TEXTURE_WRAP_S, @intCast(@intFromEnum(state.wrapS)));
    gl.textureParameteri(self.handle, gl.TEXTURE_WRAP_T, @intCast(@intFromEnum(state.wrapT)));
    const handle = gl.GL_ARB_bindless_texture.getTextureHandleARB(self.handle);
    return BindlessTexture{ .handle = handle };
}

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

pub const TextureUpdateInformation = struct {
    level: u32 = 0,
    extent: Extent,
    offset: Extent = .{ .width = 0, .height = 0, .depth = 0 },
    format: TextureInternalFormat, // TODO: Use enums
    type: DataType,
    data: []const u8,
};

pub fn update(self: Texture, info: TextureUpdateInformation) void {
    std.debug.assert(!self.isBindless);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.pixelStorei(gl.PACK_ALIGNMENT, 1);
    defer {
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
        gl.pixelStorei(gl.PACK_ALIGNMENT, 4);
    }
    switch (self.type) {
        ._2D, ._1DArray, .cubeMap => gl.textureSubImage2D(
            self.handle,
            @intCast(info.level),
            0,
            0,
            @intCast(info.extent.width),
            @intCast(info.extent.height),
            @intFromEnum(info.format),
            @intFromEnum(info.type),
            info.data.ptr,
        ),
        ._3D, ._2DArray, .cubeMapArray => gl.textureSubImage3D(
            self.handle,
            @intCast(info.level),
            @intCast(info.offset.width),
            @intCast(info.offset.height),
            @intCast(info.offset.depth),
            @intCast(info.extent.width),
            @intCast(info.extent.height),
            @intCast(info.extent.depth),
            @intFromEnum(info.format),
            @intFromEnum(info.type),
            info.data.ptr,
        ),

        else => @panic("Texture type not supported yet"),
    }
}

pub fn deinit(self: Texture) void {
    if (self.handle == 0) return;
    gl.deleteTextures(1, @ptrCast(&self.handle));
}
