const std = @import("std");
const gl = @import("../../gl4_6.zig");

const Texture = @import("./Texture.zig");
const BindlessTexture = @import("./BindlessTexture.zig");
const Sampler = @import("../Sampler.zig");

pub const Texture2D = @This();

pub const Texture2DCreateInfo = struct {
    name: ?[]const u8,
    extent: Texture.Extent2D,
    format: Texture.Format,
    levelCount: u32,
    data: ?TextureData = null,
};

pub const TextureData = struct {
    extent: Texture.Extent2D,
    offset: Texture.Extent2D,
    level: u32,
    channels: Texture.TextureInternalFormat,
    type: Texture.DataType,
    data: []const u8,
};

handle: u32,
extent: Texture.Extent2D,
format: Texture.Format,
levelCount: u32,

pub fn getTextureType() Texture.TextureType {
    return .@"2D";
}

pub fn init(self: *Texture2D, createInfo: *const Texture2DCreateInfo) void {
    gl.createTextures(gl.TEXTURE_2D, 1, @ptrCast(&self.handle));
    gl.textureStorage2D(
        self.handle,
        @intCast(createInfo.levelCount),
        @intFromEnum(createInfo.format),
        @intCast(createInfo.extent.width),
        @intCast(createInfo.extent.height),
    );

    if (createInfo.name) |n| {
        gl.objectLabel(gl.TEXTURE, self.handle, @intCast(n.len), n.ptr);
    }

    if (createInfo.data) |data| {
        self.write(&data);
    }

    self.extent = createInfo.extent;
    self.format = createInfo.format;
    self.levelCount = createInfo.levelCount;
}

pub fn deinit(self: *const Texture2D) void {
    gl.deleteTextures(1, @ptrCast(&self.handle));
}

pub fn toTexture(self: *const Texture2D) Texture {
    return .{
        .handle = self.handle,
        .extent = .{
            .@"2D" = self.extent,
        },
        .format = self.format,
    };
}

pub fn write(self: *const Texture2D, data: *const TextureData) void {
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.pixelStorei(gl.PACK_ALIGNMENT, 1);
    defer {
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
        gl.pixelStorei(gl.PACK_ALIGNMENT, 4);
    }

    gl.textureSubImage2D(
        self.handle,
        @intCast(data.level),
        @intCast(data.offset.width),
        @intCast(data.offset.height),
        @intCast(data.extent.width),
        @intCast(data.extent.height),
        @intFromEnum(data.channels),
        @intFromEnum(data.type),
        data.data.ptr,
    );
}

pub fn bindless(self: *const Texture2D, state: Sampler.SamplerState) BindlessTexture {
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
