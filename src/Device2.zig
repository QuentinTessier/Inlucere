const std = @import("std");
const gl = @import("gl4_6.zig");

pub const Device = @This();

const Handle = @import("resource_pool.zig").Handle;
const ResourcePool = @import("resource_pool.zig").ResourcePool;
pub const DeviceLimit = @import("Resources/DeviceLimits.zig");
pub const Buffer = @import("resource/buffer.zig");
pub const Texture = @import("resource/texture.zig");
pub const Shader = @import("resource/shader.zig");
pub const GraphicPipeline = @import("resource/graphic_pipeline.zig");
pub const ComputePipeline = @import("resource/compute_pipeline.zig");

const StagingBuffers = @import("staging_buffers.zig");

pub const ResourceHandleIdentifier = enum {
    buffer,
    texture,
    sampler,
    framebuffer,

    shader,
    graphic_pipeline,
    compute_pipeline,
};

pub fn TypedHandle(comptime _: ResourceHandleIdentifier) type {
    return packed struct(u32) {
        index: u24,
        generation: u8,

        pub fn to_untyped(self: @This()) Handle {
            return @bitCast(self);
        }
    };
}

pub const BufferHandle = TypedHandle(.buffer);
pub const TextureHandle = TypedHandle(.texture);
pub const ShaderHandle = TypedHandle(.shader);
pub const GraphicPipelineHandle = TypedHandle(.graphic_pipeline);
pub const ComputePipelineHandle = TypedHandle(.compute_pipeline);

allocator: std.mem.Allocator,

// TODO: Allow build.zig to specify the size of each pool.
buffers: ResourcePool(Buffer, 64) = undefined,
textures: ResourcePool(Texture, 128) = undefined,
shaders: ResourcePool(Shader, 32) = undefined,
graphic_pipelines: ResourcePool(GraphicPipeline, 32) = undefined,
compute_pipelines: ResourcePool(ComputePipeline, 32) = undefined,

staging_buffers: StagingBuffers,

pub fn init(self: *Device, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;
    try self.buffers.init(allocator);
    try self.textures.init(allocator);
    try self.shaders.init(allocator);
    try self.graphic_pipelines.init(allocator);
    try self.compute_pipelines.init(allocator);

    try self.staging_buffers.init(allocator, .{});
}

pub fn deinit(self: *Device) void {
    self.buffers.deinit(self.allocator, Buffer.deinit);
    self.textures.deinit(self.allocator, Texture.deinit);
    self.shaders.deinit(self.allocator, Shader.deinit);
    self.graphic_pipelines.deinit(self.allocator, GraphicPipeline.deinit);
    self.compute_pipelines.deinit(self.allocator, ComputePipeline.deinit);

    self.staging_buffers.deinit(self.allocator);
}

pub const GraphicsPass = struct {
    current_pipeline: ?*const GraphicPipeline = null,
    active_fbo: u32,

    pub fn bind_pipeline(self: *GraphicsPass, pipeline: *const GraphicPipeline) void {
        self.current_pipeline = pipeline;
        gl.useProgram(pipeline.program_handle);
        gl.bindVertexArray(pipeline.vao_handle);

        pipeline.apply_rasterizer();
        pipeline.apply_depth_stencil();
        pipeline.apply_blend();
    }
    pub fn bind_vertex_buffer(self: *GraphicsPass, slot: u32, buf: *const Buffer, offset: usize) void {
        const p = self.current_pipeline orelse unreachable;
        const binding = p.vertex_layout.binding[slot];

        gl.vertexArrayVertexBuffer(p.vao, slot, buf.handle, @intCast(offset), binding.stride);
    }

    pub fn bind_index_buffer(self: *GraphicsPass, buf: *const Buffer) void {
        const p = self.current_pipeline orelse unreachable;
        std.debug.assert(buf.flags.usage == .storage);
        gl.vertexArrayElementBuffer(p.vao_handle, buf.handle);
    }

    pub fn bind_storage_buffer(_: *GraphicsPass, slot: u32, buf: *const Buffer) void {
        std.debug.assert(buf.flags.usage == .storage);
        gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, slot, buf.handle);
    }

    pub fn bind_uniform_buffer(_: *GraphicsPass, slot: u32, buf: *const Buffer, offset: usize, size: usize) void {
        std.debug.assert(buf.flags.usage == .uniform);
        gl.bindBufferRange(gl.UNIFORM_BUFFER, slot, buf.handle, @intCast(offset), @intCast(size));
    }

    pub fn bind_texture(_: *GraphicsPass, slot: u32, tex: *const Texture) void {
        gl.bindTextureUnit(slot, tex.handle);
    }

    pub fn draw(_: *GraphicsPass, first: u32, count: u32, instances: u32) void {
        gl.drawArraysInstanced(gl.TRIANGLES, @intCast(first), @intCast(count), @intCast(instances));
    }

    pub fn draw_indexed(_: *GraphicsPass, count: u32, first_index: u32, base_vertex: u32, instances: u32) void {
        gl.drawElementsInstancedBaseVertex(
            gl.TRIANGLES,
            @intCast(count),
            gl.UNSIGNED_INT,
            @ptrFromInt(first_index * @sizeOf(u32)),
            @intCast(instances),
            base_vertex,
        );
    }
    pub fn draw_indirect(self: *GraphicsPass, buf: *const Buffer, offset: usize, draw_count: u32) void {
        std.debug.assert(self.current_pipeline != null);
        std.debug.assert(buf.flags.usage == .indirect);
        gl.bindBuffer(gl.DRAW_INDIRECT_BUFFER, buf.handle);
        gl.multiDrawElementsIndirect(
            gl.TRIANGLES,
            gl.UNSIGNED_INT,
            @ptrFromInt(offset),
            @intCast(draw_count),
            0, // tightly packed
        );
    }

    pub fn draw_indirect_count(self: *GraphicsPass, cmd_buf: *const Buffer, count_buf: *const Buffer, max_draws: u32) void {
        std.debug.assert(self.current_pipeline != null);
        std.debug.assert(cmd_buf.flags.usage == .indirect);
        std.debug.assert(count_buf.flags.usage == .storage);

        gl.bindBuffer(gl.DRAW_INDIRECT_BUFFER, cmd_buf.handle);
        gl.bindBuffer(gl.PARAMETER_BUFFER, count_buf.handle);
        gl.multiDrawElementsIndirectCount(
            gl.TRIANGLES,
            gl.UNSIGNED_INT,
            null,
            0,
            @intCast(max_draws),
            0,
        );
    }
};

pub const ComputePass = struct {
    current_pipeline: ?*const ComputePipeline = null,

    pub fn bind_pipeline(self: *ComputePass, pipeline: *const ComputePipeline) void {
        self.current_pipeline = pipeline;
        gl.useProgram(pipeline.handle);
    }

    pub fn bind_storage_buffer(_: *ComputePass, slot: u32, buf: *const Buffer) void {
        std.debug.assert(buf.flags.usage == .storage);
        gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, slot, buf.handle);
    }

    pub fn bind_image(_: *ComputePass, slot: u32, tex: *const Texture, level: u32, access: Texture.TextureWriteData) void {
        std.debug.assert(tex.usage.storage);
        gl.bindImageTexture(
            slot,
            tex.handle,
            @intCast(level),
            gl.FALSE,
            0,
            switch (access) {
                .read_only => gl.READ_ONLY,
                .write_only => gl.WRITE_ONLY,
                .read_write => gl.READ_WRITE,
            },
            @intFromEnum(tex.format),
        );
    }

    pub fn bind_texture(_: *ComputePass, slot: u32, tex: *const Texture) void {
        gl.bindTextureUnit(slot, tex.handle);
    }

    pub fn dispatch(self: *ComputePass, x: u32, y: u32, z: u32) void {
        std.debug.assert(self.current_pipeline != null);
        gl.dispatchCompute(x, y, z);
    }

    pub fn dispatch_for_size(self: *ComputePass, x: u32, y: u32, z: u32) void {
        const p = self.current_pipeline orelse unreachable;
        gl.dispatchCompute(
            @divFloor(x + p.workgroup_size[0] - 1, p.workgroup_size[0]),
            @divFloor(y + p.workgroup_size[1] - 1, p.workgroup_size[1]),
            @divFloor(z + p.workgroup_size[2] - 1, p.workgroup_size[2]),
        );
    }
};
