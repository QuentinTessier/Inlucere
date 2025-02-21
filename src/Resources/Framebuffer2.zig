const std = @import("std");
const gl = @import("../gl4_6.zig");

const Texture = @import("./Texture/Texture.zig");
const Texture2D = @import("./Texture/Texture2D.zig");

pub const ColorAttachmentCreateInfo = union(enum) {
    texture2D: Texture2D,
};

pub const FramebufferCreateInfo = struct {
    attachments: []const ColorAttachmentCreateInfo = &.{},
    depthStencilAttachment: ?Texture.Extent2D = null,
};

pub const Framebuffer = @This();

handle: u32,
attachments: std.BoundedArray(Texture, 8),
depthStencilAttachment: u32,

pub fn init(self: *Framebuffer, createInfo: *const FramebufferCreateInfo) !void {
    self.attachments = .{};
    self.depthStencilAttachment = 0;

    var drawBuffers: [8]u32 = [1]u32{0} ** 8;
    gl.createFramebuffers(1, @ptrCast(&self.handle));
    for (createInfo.attachments, 0..) |attachment, i| {
        switch (attachment) {
            .texture2D => |texture| {
                gl.namedFramebufferTexture(self.handle, @intCast(gl.COLOR_ATTACHMENT0 + i), texture.handle, 0);
                try self.attachments.append(texture.toTexture());
                drawBuffers[i] = @intCast(gl.COLOR_ATTACHMENT0 + i);
            },
        }
    }
    gl.namedFramebufferDrawBuffers(self.handle, @intCast(createInfo.attachments.len), (&drawBuffers).ptr);

    if (createInfo.depthStencilAttachment) |extent| {
        var rbHandle: u32 = 0;
        gl.createRenderbuffers(1, @ptrCast(&rbHandle));
        gl.namedRenderbufferStorage(
            rbHandle,
            gl.DEPTH24_STENCIL8,
            @intCast(extent.width),
            @intCast(extent.height),
        );
        gl.namedFramebufferRenderbuffer(self.handle, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rbHandle);
        self.depthStencilAttachment = rbHandle;
    }

    if (gl.checkNamedFramebufferStatus(self.handle, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return error.IncompleteFramebuffer;
    }
}

pub fn deinit(self: *const Framebuffer) void {
    if (self.depthStencilAttachment != 0) {
        gl.deleteRenderbuffers(1, @ptrCast(&self.depthStencilAttachment));
    }
    gl.deleteFramebuffers(1, @ptrCast(&self.handle));
}

pub fn getAttachment(self: *const Framebuffer, index: usize) ?Texture {
    if (self.attachments.len <= index) return null;
    return self.attachments.get(index);
}
