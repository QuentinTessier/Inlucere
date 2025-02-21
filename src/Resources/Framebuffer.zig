const std = @import("std");
const gl = @import("../gl4_6.zig");

const Texture = @import("./Texture.zig");

pub const Framebuffer = @This();

pub const ColorAttachment = struct {
    handle: u32,
    format: Texture.Format,
    width: u32,
    height: u32,
};

pub const ColorAttachmentCreateInfo = struct {
    format: Texture.Format,
    width: u32,
    height: u32,
};

pub const DepthStencilAttachmentCreateInfo = struct {
    width: u32,
    height: u32,
};

pub const DepthStencilAttachment = struct {
    handle: u32,
    width: u32,
    height: u32,
};

handle: u32,
attachments: std.BoundedArray(ColorAttachment, 8),
depthStencilAttachment: ?DepthStencilAttachment,

pub fn init(self: *Framebuffer, colorAttachments: []const ColorAttachmentCreateInfo, depthStencilAttachment: ?DepthStencilAttachmentCreateInfo) !void {
    std.debug.assert(colorAttachments.len <= 8);

    self.attachments = .{};
    self.depthStencilAttachment = null;

    var drawBuffers: [8]u32 = [1]u32{0} ** 8;
    gl.createFramebuffers(1, @ptrCast(&self.handle));
    for (colorAttachments, 0..) |attachment, i| {
        var handle: u32 = 0;
        gl.createTextures(gl.TEXTURE_2D, 1, @ptrCast(&handle));
        gl.textureStorage2D(
            handle,
            1,
            @intFromEnum(attachment.format),
            @intCast(attachment.width),
            @intCast(attachment.height),
        );
        gl.textureParameteri(handle, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.textureParameteri(handle, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        gl.namedFramebufferTexture(self.handle, @intCast(gl.COLOR_ATTACHMENT0 + i), handle, 0);

        try self.attachments.append(.{
            .handle = handle,
            .format = attachment.format,
            .height = attachment.height,
            .width = attachment.width,
        });
        drawBuffers[i] = @intCast(gl.COLOR_ATTACHMENT0 + i);
    }
    gl.namedFramebufferDrawBuffers(self.handle, @intCast(colorAttachments.len), (&drawBuffers).ptr);

    if (depthStencilAttachment) |depthStencil| {
        var handle: u32 = 0;
        gl.createRenderbuffers(1, @ptrCast(&handle));
        gl.namedRenderbufferStorage(handle, gl.DEPTH24_STENCIL8, @intCast(depthStencil.width), @intCast(depthStencil.height));
        gl.namedFramebufferRenderbuffer(self.handle, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, handle);
        self.depthStencilAttachment = .{
            .handle = handle,
            .width = depthStencil.width,
            .height = depthStencil.height,
        };
    }

    if (gl.checkNamedFramebufferStatus(self.handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.IncompleteFramebuffer;
    }
}

pub fn deinit(self: *Framebuffer) void {
    for (self.attachments.constSlice()) |texture| {
        gl.deleteTextures(1, @ptrCast(&texture.handle));
    }
    if (self.depthStencilAttachment) |depthStencil| {
        gl.deleteRenderbuffers(1, @ptrCast(&depthStencil.handle));
    }
}
