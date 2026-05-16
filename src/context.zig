const std = @import("std");
const gl = @import("gl4_6.zig");

const Device = @import("device.zig");
const BarrierBits = @import("barrier.zig").BarrierBits;

pub const PassType = enum { graphics, compute };

pub const ResourceAccess = enum {
    storage_buffer_write,
    host_write,
    transfer_write_buffer,
    storage_image_write,
    color_attachment_write,
    depth_attachment_write,
    stencil_attachment_write,
    depth_stencil_attachment_write,
    transfer_write_texture,
    mipmap_generation,

    sampled_read,
    storage_image_read,
    storage_buffer_read,
    indirect_command_read,
    index_buffer_read,
    vertex_buffer_read,
    uniform_buffer_read,
    transfer_read_buffer,
    transfer_read_texture,

    pub fn transition(prev: ResourceAccess, next_pass: PassType) BarrierBits {
        var b: BarrierBits = .{};

        switch (next_pass) {
            .graphics => switch (prev) {
                .storage_buffer_write => {
                    b.ssbo = true;
                    b.command = true; // might be used as indirect
                    b.vertex_attrib = true; // might be used as vertex buffer
                    b.index = true; // might be used as index buffer
                    b.uniform = true; // might be used as UBO
                },
                .storage_image_write => {
                    b.texture_fetch = true;
                    b.image_access = true;
                },
                .color_attachment_write, .depth_attachment_write, .depth_stencil_attachment_write => {
                    b.framebuffer = true;
                    b.texture_fetch = true;
                },
                .transfer_write_buffer => {
                    b.ssbo = true;
                    b.vertex_attrib = true;
                    b.index = true;
                    b.uniform = true;
                    b.command = true;
                },
                .transfer_write_texture => b.texture_update = true,
                .mipmap_generation => b.texture_fetch = true,
                .host_write => {},
                else => {},
            },

            .compute => switch (prev) {
                .storage_buffer_write => b.ssbo = true,
                .storage_image_write => b.image_access = true,
                .color_attachment_write, .depth_attachment_write, .depth_stencil_attachment_write => {
                    b.framebuffer = true;
                    b.texture_fetch = true;
                },
                .transfer_write_buffer => b.ssbo = true,
                .transfer_write_texture => b.texture_update = true,
                .mipmap_generation => b.texture_fetch = true,
                .host_write => {},
                else => {},
            },
        }
        return b;
    }
};

pub const AccessedResource = union(enum) {
    buffer: struct {
        handle: Device.BufferHandle,
        access: ResourceAccess,
    },
    texture: struct {
        handle: Device.TextureHandle,
        access: ResourceAccess,
    },

    pub fn transition(self: AccessedResource, next_pass: PassType) BarrierBits {
        return switch (self) {
            .buffer => |b| b.access.transition(next_pass),
            .texture => |t| t.access.transition(next_pass),
        };
    }
};

pub const Context = @This();

device: *Device,

bound_program: u32 = 0,
bound_vao: u32 = 0,

current_pass: ?PassType = null,

pending_access: std.array_list.Aligned(AccessedResource, null),

pub fn init(self: *Context, device: *Device) void {
    self.device = device;
    self.pending_access = .empty;
}

pub fn deinit(self: *Context) void {
    self.pending_access.deinit(self.device.allocator);
}

fn flush_barriers_for_pass(self: *Context, next_pass: PassType) void {
    var bits = BarrierBits{};

    const values = self.pending_access.items;
    for (values) |elem| {
        bits = bits.merge(elem.transition(next_pass));
    }

    if (!bits.is_empty()) {
        gl.memoryBarrier(bits.flags());
    }

    self.pending_access.clearRetainingCapacity();
}

pub const AttachmentLoad = enum { load, clear, dont_care };
pub const AttachmentStore = enum { store, dont_care };

pub const ColorAttachment = struct {
    texture: Device.TextureHandle,
    load: AttachmentLoad = .dont_care,
    store: AttachmentStore = .store,
    clear_value: [4]f32 = [1]f32{0} ** 4,
    mip_level: u32 = 0,
    layer: u32 = 0,
};

pub const DepthAttachment = struct {
    texture: Device.TextureHandle,
    load: AttachmentLoad = .dont_care,
    store: AttachmentStore = .store,
    has_stencil: bool = true,
    clear_depth: f32 = 1.0,
    clear_stencil: u8 = 0,
};

pub const PassAttachments = struct {
    color: []const ColorAttachment = &.{},
    depth: ?DepthAttachment = null,
    target: enum { framebuffer, swapchain },

    pub fn swapchain() PassAttachments {
        return .{ .target = .swapchain };
    }
};

pub fn begin_graphics_pass(self: *Context, attachments: PassAttachments) GraphicsEncoder {
    self.flush_barriers_for_pass(.graphics);

    const fbo: u32 = 0;
    switch (attachments.target) {
        .framebuffer => @panic("not implemented yet"),
        .swapchain => {
            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
        },
    }

    for (attachments.color, 0..) |attachment, i| {
        switch (attachment.load) {
            .dont_care, .load => {},
            .clear => gl.clearNamedFramebufferfv(fbo, gl.COLOR, @intCast(i), &attachment.clear_value),
        }
    }

    if (attachments.depth) |depth| {
        switch (depth.load) {
            .dont_care, .load => {},
            .clear => {
                if (depth.has_stencil) {
                    gl.clearNamedFramebufferfi(fbo, gl.DEPTH_STENCIL, 0, depth.clear_depth, @intCast(depth.clear_stencil));
                } else {
                    gl.clearNamedFramebufferfv(fbo, gl.DEPTH_STENCIL, 0, &depth.clear_depth);
                }
            },
        }
    }

    return GraphicsEncoder{
        .ctx = self,
        .fbo = 0,
        .pipeline = null,
        .attachments = attachments,
    };
}

pub fn begin_compute_pass(self: *Context) ComputeEncoder {
    self.flush_barriers_for_pass(.compute);
    return ComputeEncoder{
        .ctx = self,
        .pipeline = null,
    };
}

pub const GraphicsEncoder = struct {
    ctx: *Context,
    fbo: u32,
    pipeline: ?*const Device.GraphicPipeline = null,
    attachments: PassAttachments,

    pub fn bind_pipeline(self: *GraphicsEncoder, pipeline: *const Device.GraphicPipeline) void {
        if (self.ctx.bound_program != pipeline.program_handle) {
            gl.useProgram(pipeline.program_handle);
            self.ctx.bound_program = pipeline.program_handle;
        }

        if (self.ctx.bound_vao != pipeline.vao_handle) {
            gl.bindVertexArray(pipeline.vao_handle);
            self.ctx.bound_vao = pipeline.vao_handle;
        }

        pipeline.apply_state();
        self.pipeline = pipeline;
    }

    pub fn bind_vertex_buffer(self: *GraphicsEncoder, slot: u32, buf: Device.BufferHandle, offset: usize) void {
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .vertex);
        const binding = self.pipeline.?.vertex_layout.binding[slot];

        gl.vertexArrayVertexBuffer(self.ctx.bound_vao, slot, buffer.handle, @intCast(offset), @intCast(binding.stride));
    }

    pub fn bind_index_buffer(self: *GraphicsEncoder, buf: Device.BufferHandle) void {
        const buffer = self.ctx.device.buffers.get(buf) orelse return;
        std.debug.assert(buffer.flags.usage == .index);

        gl.vertexArrayElementBuffer(self.ctx.bound_vao, buf.handle);
    }

    pub fn bind_uniform_buffer(self: *GraphicsEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) !void {
        const buffer = self.ctx.device.buffers.get(buf) orelse return;
        std.debug.assert(buffer.flags.usage == .uniform);

        gl.bindBufferRange(gl.UNIFORM_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
        try self.ctx.pending_access.append(self.ctx.device.allocator, .{ .buffer = .{
            .handle = buf,
            .access = .uniform_buffer_read,
        } });
    }

    pub fn bind_storage_buffer(self: *GraphicsEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) void {
        const buffer = self.ctx.device.buffers.get(buf) orelse return;
        std.debug.assert(buffer.flags.usage == .storage);

        gl.bindBufferRange(gl.SHADER_STORAGE_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
        try self.ctx.pending_access.append(self.ctx.device.allocator, .{ .buffer = .{
            .handle = buf,
            .access = .storage_buffer_read,
        } });
    }

    pub fn bind_texture(self: *GraphicsEncoder, slot: u32, tex: Device.TextureHandle) void {
        const texture = self.ctx.device.textures.get(tex) orelse return;

        gl.bindTextureUnit(slot, texture.handle);
        try self.ctx.pending_access.append(self.ctx.device.allocator, .{ .texture = .{
            .handle = tex,
            .access = .sampled_read,
        } });
    }

    pub const Mode = enum(u32) {
        triangle = gl.TRIANGLES,
        triangle_strip = gl.TRIANGLE_STRIP,
        triangle_fan = gl.TRIANGLE_FAN,
    };

    pub fn draw(_: *GraphicsEncoder, mode: Mode, first: u32, count: u32, instances: u32, base_instance: u32) void {
        gl.drawArraysInstancedBaseInstance(@intFromEnum(mode), @intCast(first), @intCast(count), @intCast(instances), base_instance);
    }

    pub fn draw_indexed(_: *GraphicsEncoder, mode: Mode, count: u32, first_index: usize, instances: u32, base_vertex: u32, base_instance: u32) void {
        gl.drawElementsInstancedBaseVertexBaseInstance(
            @intFromEnum(mode),
            @intCast(count),
            gl.UNSIGNED_INT,
            @ptrFromInt(first_index * @sizeOf(u32)),
            @intCast(instances),
            @intCast(base_vertex),
            @intCast(base_instance),
        );
    }

    pub fn draw_indirect(self: *GraphicsEncoder, mode: Mode, buf: Device.BufferHandle, offset: usize, draw_count: u32) void {
        const buffer = self.ctx.device.buffers.get(buf) orelse return;
        gl.bindBuffer(gl.DRAW_INDIRECT_BUFFER, buffer.handle);
        gl.multiDrawElementsIndirect(
            @intFromEnum(mode),
            gl.UNSIGNED_BYTE,
            @ptrFromInt(offset),
            @intCast(draw_count),
            0,
        );
    }

    pub fn end(self: *GraphicsEncoder) void {
        var invalidate_attachments: [9]u32 = undefined;
        var invalidate_count: u32 = 0;

        for (self.attachments.color, 0..) |attachment, i| {
            switch (attachment.store) {
                .dont_care => {
                    invalidate_attachments[invalidate_count] = gl.COLOR_ATTACHMENT0 + @as(u32, @intCast(i));
                    invalidate_count += 1;
                },
                .store => {
                    self.ctx.pending_access.append(self.ctx.device.allocator, .{ .texture = .{
                        .handle = attachment.texture,
                        .access = .color_attachment_write,
                    } }) catch unreachable;
                },
            }
        }

        if (self.attachments.depth) |depth| {
            switch (depth.store) {
                .dont_care => {
                    const attachment_point: u32 = switch (depth.has_stencil) {
                        true => gl.DEPTH_STENCIL_ATTACHMENT,
                        false => gl.DEPTH_ATTACHMENT,
                    };
                    invalidate_attachments[invalidate_count] = attachment_point;
                    invalidate_count += 1;
                },
                .store => {
                    self.ctx.pending_access.append(self.ctx.device.allocator, .{ .texture = .{
                        .handle = depth.texture,
                        .access = .depth_attachment_write,
                    } }) catch unreachable;
                },
            }
        }

        if (invalidate_count > 0) {
            gl.invalidateNamedFramebufferData(self.fbo, @intCast(invalidate_count), &invalidate_attachments);
        }

        if (std.debug.runtime_safety) {
            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            self.pipeline = null;
            self.fbo = 0;
            self.ctx = undefined;
        }
    }
};

pub const ComputeEncoder = struct {
    ctx: *Context,
    pipeline: ?*const Device.ComputePipeline = null,

    pub fn bind_storage_buffer(self: *ComputeEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize, access: Device.Buffer.AccessUsage) void {
        const buffer = self.ctx.device.buffers.get(buf) orelse return;
        std.debug.assert(buffer.flags.usage == .storage);

        gl.bindBufferRange(gl.SHADER_STORAGE_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
        switch (access) {
            .read => {},
            .write => try self.ctx.pending_access.append(self.ctx.device.allocator, .{ .buffer = .{
                .handle = buf,
                .access = .storage_buffer_read,
            } }),
        }
    }

    pub fn bind_storage_image(self: *ComputeEncoder, slot: u32, tex: Device.TextureHandle, level: u32, access: Device.Buffer.AccessUsage) void {
        const texture = self.ctx.device.textures.get(tex) orelse return;
        std.debug.assert(texture.usage.storage);

        gl.bindImageTexture(slot, texture.handle, @intCast(level), gl.FALSE, 0, switch (access) {
            .read_only => gl.READ_ONLY,
            .write_only => gl.WRITE_ONLY,
            .read_write => gl.READ_WRITE,
        }, @intFromEnum(texture.format));
        switch (access) {
            .read => {},
            .write => try self.ctx.pending_access.append(self.ctx.device.allocator, .{ .texture = .{
                .handle = tex,
                .access = .storage_image_write,
            } }),
        }
    }

    pub fn dispatch(_: *ComputeEncoder, x: u32, y: u32, z: u32) void {
        gl.dispatchCompute(x, y, z);
    }

    pub fn dispatch_size(self: *ComputeEncoder, x: u32, y: u32, z: u32) void {
        gl.dispatchCompute(
            @divFloor(x, self.pipeline.?.workgroup_size[0]),
            @divFloor(y, self.pipeline.?.workgroup_size[1]),
            @divFloor(z, self.pipeline.?.workgroup_size[2]),
        );
    }
};
