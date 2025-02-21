const std = @import("std");
const gl = @import("../../gl4_6.zig");

const Texture = @import("./Texture.zig");

pub const TextureCube = @This();

pub const TextureCubeCreateInfo = struct {
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
    return .Cube;
}

pub fn init(self: *TextureCube, createInfo: *const TextureCubeCreateInfo) void {
    gl.createTextures(gl.TEXTURE_CUBE_MAP, 1, @ptrCast(&self.handle));
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

pub fn deinit(self: *const TextureCube) void {
    gl.deleteTextures(1, @ptrCast(self.handle));
}

pub fn toTexture(self: *const TextureCube) Texture {
    return .{
        .handle = self.handle,
        .extent = .{
            .Cube = self.extent,
        },
        .format = self.format,
    };
}

pub fn write(self: *const TextureCube, data: *const TextureData) void {
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

pub const Face = enum(u32) {
    PositiveX = gl.TEXTURE_CUBE_MAP_POSITIVE_X,
    NegativeX = gl.TEXTURE_CUBE_MAP_NEGATIVE_X,
    PositiveY = gl.TEXTURE_CUBE_MAP_POSITIVE_Y,
    NegativeY = gl.TEXTURE_CUBE_MAP_NEGATIVE_Y,
    PositiveZ = gl.TEXTURE_CUBE_MAP_POSITIVE_Z,
    NegativeZ = gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
};

pub fn updateFace(self: *const TextureCube, face: Face, data: *const TextureData) void {
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, self.handle);
    defer gl.bindTexture(gl.TEXTURE_CUBE_MAP, 0);

    gl.texSubImage2D(
        @intFromEnum(face),
        0,
        @intCast(data.offset.width),
        @intCast(data.offset.height),
        @intCast(data.extent.width),
        @intCast(data.extent.height),
        @intFromEnum(data.channels),
        @intFromEnum(data.type),
        data.data.ptr,
    );
}
