const std = @import("std");
const gl = @import("gl4_6.zig");

const Device = @import("device.zig");
const BarrierBits = @import("barrier.zig").BarrierBits;
const Allocation = @import("memory/gpu_allocator.zig").Allocation;
const ResourceTransition = @import("resource_transition.zig");

pub const PassType = enum { graphics, compute };

pub const Context = @This();

device: *Device,

bound_program: u32 = 0,
bound_vao: u32 = 0,

current_pass: ?PassType = null,
fbo_cache: std.AutoArrayHashMapUnmanaged(u64, u32),
transition_cache: ResourceTransition.ResourceAccessManager,

pub fn init(self: *Context, device: *Device) void {
    self.device = device;
    self.fbo_cache = .empty;
    self.transition_cache = .init(device.allocator);
}

pub fn deinit(self: *Context) void {
    if (self.fbo_cache.values().len > 0) {
        gl.deleteFramebuffers(@intCast(self.fbo_cache.values().len), self.fbo_cache.values().ptr);
    }
    self.fbo_cache.deinit(self.device.allocator);
    self.transition_cache.deinit();
}

pub fn barrier(_: *Context, b: BarrierBits) void {
    gl.memoryBarrier(b.flags());
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

    pub fn hash(self: *const PassAttachments) u64 {
        var h: std.hash.Wyhash = .init(0x0129302);

        h.update(std.mem.sliceAsBytes(self.color));
        h.update(std.mem.asBytes(&self.depth));
        h.update(std.mem.asBytes(&self.target));
        return h.final();
    }
};

fn build_or_get_framebuffer(self: *Context, attachments: PassAttachments) !u32 {
    const h = attachments.hash();
    const result = try self.fbo_cache.getOrPut(self.device.allocator, h);
    if (!result.found_existing) {
        result.value_ptr.* = try self.build_framebuffer(attachments);
    }

    return result.value_ptr.*;
}

pub fn build_framebuffer(self: *Context, attachments: PassAttachments) !u32 {
    var draw_buffers: [16]u32 = [1]u32{0} ** 16;
    var handle: u32 = 0;
    gl.createFramebuffers(1, @ptrCast(&handle));
    errdefer gl.deleteFramebuffers(1, &handle);

    for (attachments.color, 0..) |attachment, i| {
        const texture = self.device.get_texture(attachment.texture) orelse return error.missing_texture;

        gl.namedFramebufferTexture(handle, @intCast(gl.COLOR_ATTACHMENT0 + i), texture.handle, @intCast(attachment.mip_level));
        draw_buffers[i] = @intCast(gl.COLOR_ATTACHMENT0 + i);
    }

    gl.namedFramebufferDrawBuffers(handle, @intCast(attachments.color.len), (&draw_buffers).ptr);
    if (attachments.depth) |depth_attachment| {
        const texture = self.device.get_texture(depth_attachment.texture) orelse return error.missing_texture;

        gl.namedFramebufferTexture(handle, if (depth_attachment.has_stencil) gl.DEPTH_STENCIL_ATTACHMENT else gl.DEPTH_ATTACHMENT, texture.handle, 0);
    }

    if (std.debug.runtime_safety) {
        const status = gl.checkNamedFramebufferStatus(handle, gl.FRAMEBUFFER);
        if (status != gl.FRAMEBUFFER_COMPLETE) {
            std.log.err("Framebuffer incomplete: 0x{x} - {s}", .{ status, switch (status) {
                gl.FRAMEBUFFER_UNDEFINED => "undefined",
                gl.FRAMEBUFFER_INCOMPLETE_ATTACHMENT => "incomplete attachment",
                gl.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT => "missing attachment",
                gl.FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER => "incomplete draw buffer",
                gl.FRAMEBUFFER_INCOMPLETE_READ_BUFFER => "incomplete read buffer",
                gl.FRAMEBUFFER_UNSUPPORTED => "unsupported format combination",
                gl.FRAMEBUFFER_INCOMPLETE_MULTISAMPLE => "inconsistent multisample",
                gl.FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS => "inconsistent layer targets",
                else => "unknown",
            } });
            return error.incomplete_framebuffer;
        }
    }
    return handle;
}

pub fn begin_frame(self: *Context) void {
    self.device.staging_buffers.begin_staging();
    //gl.deleteFramebuffers(@intCast(self.fbo_cache.values().len), self.fbo_cache.values().ptr);
    //self.fbo_cache.clearRetainingCapacity();
}

pub fn end_frame(self: *Context) void {
    self.device.staging_buffers.end_staging();
}

pub const Transition = union(enum) {
    buffer: struct { handle: Device.BufferHandle, access: ResourceTransition.BufferResourceAccess },
    texture: struct { handle: Device.TextureHandle, access: ResourceTransition.TextureResourceAccess },
};

pub fn begin_graphics_pass(self: *Context, attachments: PassAttachments, transitions: []const Transition) !GraphicsEncoder {
    var b: u32 = 0;
    const fbo: u32 = switch (attachments.target) {
        .framebuffer => self.build_or_get_framebuffer(attachments) catch {
            @panic("failed to build framebuffer");
        },
        .swapchain => 0,
    };
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);

    for (attachments.color, 0..) |attachment, i| {
        switch (attachment.load) {
            .dont_care, .load => {},
            .clear => gl.clearNamedFramebufferfv(fbo, gl.COLOR, @intCast(i), &attachment.clear_value),
        }

        b |= if (try self.transition_cache.update_texture(attachment.texture, .color_attachment_write)) |bit| bit else 0;
    }

    if (attachments.depth) |depth| {
        switch (depth.load) {
            .dont_care, .load => {},
            .clear => {
                if (depth.has_stencil) {
                    gl.clearNamedFramebufferfi(fbo, gl.DEPTH_STENCIL, 0, depth.clear_depth, @intCast(depth.clear_stencil));
                } else {
                    gl.clearNamedFramebufferfv(fbo, gl.DEPTH, 0, &depth.clear_depth);
                }
            },
        }
        b |= if (try self.transition_cache.update_texture(depth.texture, .depth_attachment_write)) |bit| bit else 0;
    }

    for (transitions) |t| {
        b |= switch (t) {
            .buffer => |buf| if (try self.transition_cache.update_buffer(buf.handle, buf.access)) |bit| bit else 0,
            .texture => |tex| if (try self.transition_cache.update_texture(tex.handle, tex.access)) |bit| bit else 0,
        };
    }

    if (b != 0) {
        gl.memoryBarrier(b);
    }

    return GraphicsEncoder{
        .ctx = self,
        .fbo = fbo,
        .pipeline = null,
        .attachments = attachments,
    };
}

pub fn begin_transfer_pass(self: *Context, transitions: []const Transition) TransferEncoder {
    var b: u32 = 0;
    for (transitions) |t| {
        b |= switch (t) {
            .buffer => |buf| if (try self.transition_cache.update_buffer(buf.handle, buf.access)) |bit| bit else 0,
            .texture => |tex| if (try self.transition_cache.update_texture(tex.handle, tex.access)) |bit| bit else 0,
        };
    }

    if (b != 0) {
        gl.memoryBarrier(b);
    }

    return .{
        .ctx = self,
    };
}

pub fn begin_compute_pass(self: *Context, transitions: []const Transition) ComputeEncoder {
    var b: u32 = 0;
    for (transitions) |t| {
        b |= switch (t) {
            .buffer => |buf| if (try self.transition_cache.update_buffer(buf.handle, buf.access)) |bit| bit else 0,
            .texture => |tex| if (try self.transition_cache.update_texture(tex.handle, tex.access)) |bit| bit else 0,
        };
    }

    if (b != 0) {
        gl.memoryBarrier(b);
    }
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

    pub fn bind_pipeline(self: *GraphicsEncoder, h: Device.GraphicPipelineHandle) void {
        const pipeline = self.ctx.device.graphic_pipelines.get(h.to_untyped()) orelse unreachable;
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
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .index);

        gl.vertexArrayElementBuffer(self.ctx.bound_vao, buffer.handle);
    }

    pub fn bind_uniform_buffer(self: *GraphicsEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) !void {
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .uniform);

        gl.bindBufferRange(gl.UNIFORM_BUFFER, slot, buffer.handle, @intCast(offset), @intCast(size));
    }

    pub fn bind_storage_buffer(self: *GraphicsEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) void {
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .storage);

        gl.bindBufferRange(gl.SHADER_STORAGE_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
    }

    pub fn bind_texture(self: *GraphicsEncoder, slot: u32, tex: Device.TextureHandle) void {
        const texture = self.ctx.device.textures.get(tex.to_untyped()) orelse return;

        gl.bindTextureUnit(slot, texture.handle);
    }

    pub fn bind_sampled_texture(self: *GraphicsEncoder, slot: u32, s: Device.SamplerHandle, tex: Device.TextureHandle) void {
        const texture = self.ctx.device.textures.get(tex.to_untyped()) orelse return;
        const sampler = self.ctx.device.samplers.get(s.to_untyped()) orelse return;

        gl.bindTextureUnit(slot, texture.handle);
        gl.bindSampler(slot, sampler.handle);
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
                .store => {},
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
                .store => {},
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

    pub fn bind_pipeline(self: *ComputeEncoder, pipeline: Device.ComputePipelineHandle) void {
        const p = self.ctx.device.get_compute_pipeline(pipeline) orelse unreachable;

        if (self.ctx.bound_program != p.handle) {
            gl.useProgram(p.handle);
            self.ctx.bound_program = p.handle;
        }

        self.pipeline = p;
    }

    pub fn bind_storage_buffer(self: *ComputeEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) void {
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .storage);

        gl.bindBufferRange(gl.SHADER_STORAGE_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
    }

    pub fn bind_uniform_buffer(self: *ComputeEncoder, slot: u32, buf: Device.BufferHandle, offset: usize, size: usize) !void {
        const buffer = self.ctx.device.buffers.get(buf.to_untyped()) orelse return;
        std.debug.assert(buffer.flags.usage == .uniform);

        gl.bindBufferRange(gl.UNIFORM_BUFFER, slot, buffer.handle, @intCast(offset), @intCast(size));
    }

    pub fn bind_storage_image(self: *ComputeEncoder, slot: u32, tex: Device.TextureHandle, level: u32, access: Device.Buffer.AccessUsage) void {
        const texture = self.ctx.device.textures.get(tex.to_untyped()) orelse return;
        std.debug.assert(texture.usage.storage);

        gl.bindImageTexture(slot, texture.handle, @intCast(level), gl.FALSE, 0, switch (access) {
            .read_only => gl.READ_ONLY,
            .write_only => gl.WRITE_ONLY,
            .read_write => gl.READ_WRITE,
        }, @intFromEnum(texture.format));
    }

    pub fn bind_texture(self: *ComputeEncoder, slot: u32, tex: Device.TextureHandle) void {
        const texture = self.ctx.device.textures.get(tex.to_untyped()) orelse return;

        gl.bindTextureUnit(slot, texture.handle);
    }

    pub fn bind_sampled_texture(self: *ComputeEncoder, slot: u32, s: Device.SamplerHandle, tex: Device.TextureHandle) void {
        const texture = self.ctx.device.textures.get(tex.to_untyped()) orelse return;
        const sampler = self.ctx.device.samplers.get(s.to_untyped()) orelse return;

        gl.bindTextureUnit(slot, texture.handle);
        gl.bindSampler(slot, sampler.handle);
    }

    pub fn dispatch(_: *ComputeEncoder, x: u32, y: u32, z: u32) void {
        gl.dispatchCompute(x, y, z);
    }

    pub fn dispatch_size(self: *ComputeEncoder, x: u32, y: u32, z: u32) void {
        gl.dispatchCompute(
            std.math.divCeil(u32, x, self.pipeline.?.workgroup_size[0]) catch unreachable,
            std.math.divCeil(u32, y, self.pipeline.?.workgroup_size[1]) catch unreachable,
            std.math.divCeil(u32, z, self.pipeline.?.workgroup_size[2]) catch unreachable,
        );
    }

    pub fn end(self: *ComputeEncoder) void {
        if (std.debug.runtime_safety) {
            self.ctx = undefined;
            self.pipeline = null;
        }
    }
};

pub const TransferEncoder = struct {
    ctx: *Context,

    pub fn upload_buffer(self: *TransferEncoder, dst: Device.BufferHandle, offset: usize, data: []const u8) !void {
        const buffer = self.ctx.device.get_buffer(dst) orelse return error.missing_buffer;
        const result = self.ctx.device.staging_buffers.upload(buffer.handle, offset, data);
        if (!result) return error.staging_full;
    }

    pub fn upload_to_allocation(self: *TransferEncoder, alloc: Allocation, offset: usize, data: []const u8) !void {
        const buffer = self.ctx.device.get_buffer(alloc.buffer) orelse return error.missing_buffer;
        std.debug.assert((@as(usize, @intCast(alloc.size)) - offset) >= data.len);
        const result = self.ctx.device.staging_buffers.upload(buffer.handle, offset, data);

        if (!result) return error.staging_full;
    }

    pub const BufferCopyDesc = struct {
        const Target = union(enum) {
            _buffer: Device.BufferHandle,
            _alloc: Allocation,

            pub fn buffer(h: Device.BufferHandle) Target {
                return .{ ._buffer = h };
            }

            pub fn allocation(a: Allocation) Target {
                return .{ ._alloc = a };
            }
        };

        src: Target,
        src_offset: usize,

        dst: Target,
        dst_offset: usize,

        size: usize,
    };

    pub fn copy_buffer_to_buffer(self: *TransferEncoder, desc: *const BufferCopyDesc) !void {
        const src_buffer = switch (desc.src) {
            ._buffer => |src| self.ctx.device.get_buffer(src) orelse return error.missing_buffer,
            ._alloc => |alloc| self.ctx.device.get_buffer(alloc.buffer) orelse return error.missing_buffer,
        };
        const dst_buffer = switch (desc.dst) {
            ._buffer => |dst| self.ctx.device.get_buffer(dst) orelse return error.missing_buffer,
            ._alloc => |alloc| self.ctx.device.get_buffer(alloc.buffer) orelse return error.missing_buffer,
        };

        const src_offset = switch (desc.src) {
            ._buffer => desc.src_offset,
            ._alloc => |alloc| desc.src_offset + alloc.offset,
        };

        const dst_offset = switch (desc.dst) {
            ._buffer => desc.dst_offset,
            ._alloc => |alloc| desc.dst_offset + alloc.offset,
        };

        gl.copyNamedBufferSubData(src_buffer.handle, dst_buffer.handle, @intCast(src_offset), @intCast(dst_offset), desc.size);
    }

    pub fn map_buffer(self: *TransferEncoder, buf: Device.BufferHandle, comptime T: type) ![]T {
        const buffer = self.ctx.device.get_buffer(buf) orelse return error.missing_buffer;
        if (buffer.ptr == null) return error.unmap_buffer;

        return buffer.cast(T);
    }

    pub fn map_allocation(self: *TransferEncoder, alloc: Allocation, comptime T: type) ![]T {
        const buffer = self.ctx.device.get_buffer(alloc.buffer) orelse return error.missing_buffer;
        if (buffer.ptr == null) return error.unmap_buffer;

        return buffer.cast_range(T, alloc.offset, alloc.size);
    }

    pub fn upload_texture(self: *TransferEncoder, dst: Device.TextureHandle, data: *const Device.Texture.TextureWriteData) !void {
        const texture = self.ctx.device.get_texture(dst) orelse return error.missing_texture;

        texture.write(data);
    }

    pub fn generate_mipmaps(self: *TransferEncoder, dst: Device.TextureHandle) !void {
        const texture = self.ctx.device.get_texture(dst) orelse return error.missing_texture;

        var found: bool = true;
        while (found) {
            found = false;
            for (self.ctx.pending_access.items, 0..) |item, i| {
                switch (item) {
                    .buffer => continue,
                    .texture => |t| {
                        if (t.handle.index == dst.index) {
                            gl.memoryBarrier(gl.TEXTURE_UPDATE_BARRIER_BIT);
                            self.ctx.pending_access.orderedRemove(i);
                            found = true;
                        }
                    },
                }
            }
        }

        gl.generateTextureMipmap(texture.handle);
    }

    pub fn end(self: *TransferEncoder) void {
        if (std.debug.runtime_safety) {
            self.ctx = undefined;
        }
    }
};
