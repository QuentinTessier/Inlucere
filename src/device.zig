const std = @import("std");
const gl = @import("gl4_6.zig");

pub const Device = @This();

const ResourcePool = @import("resource_pool.zig").ResourcePool;
const Handle = @import("resource_pool.zig").Handle;
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

        pub fn from_untyped(h: Handle) @This() {
            return .{ .index = h.index, .generation = h.generation };
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
    self.buffers.init();
    self.textures.init();
    self.shaders.init();
    self.graphic_pipelines.init();
    self.compute_pipelines.init();

    try self.staging_buffers.init(allocator, &.{});
}

pub fn deinit(self: *Device) void {
    self.buffers.deinit(self.allocator, Buffer.deinit);
    self.textures.deinit(self.allocator, Texture.deinit);
    self.shaders.deinit(self.allocator, Shader.deinit);
    self.graphic_pipelines.deinit(self.allocator, GraphicPipeline.deinit);
    self.compute_pipelines.deinit(self.allocator, ComputePipeline.deinit);

    self.staging_buffers.deinit(self.allocator);
}

pub fn create(comptime resource_type: ResourceHandleIdentifier) type {
    const payload = switch (resource_type) {
        .buffer => Buffer.BufferDesc,
        .texture => Texture.TextureDesc,
        .graphic_pipeline => GraphicPipeline.GraphicPipelineDesc,
        .compute_pipeline => ComputePipeline.ComputePipelineDesc,
        .shader => Shader.ShaderDesc,
        else => void,
    };

    const data_type = switch (resource_type) {
        .buffer => Buffer,
        .texture => Texture,
        .graphic_pipeline => GraphicPipeline,
        .compute_pipeline => ComputePipeline,
        .shader => Shader,
        else => void,
    };

    std.debug.assert(payload != void);
    return struct {
        pub fn create_fn(self: *Device, desc: *const payload) !TypedHandle(resource_type) {
            const id, const ptr = switch (resource_type) {
                .buffer => try self.buffers.new(),
                .texture => try self.textures.new(),
                .graphic_pipeline => try self.graphic_pipelines.new(),
                .compute_pipeline => try self.compute_pipelines.new(),
                .shader => try self.shaders.new(),
                else => unreachable,
            };

            if (resource_type == .graphic_pipeline or resource_type == .compute_pipeline) {
                try ptr.init(self, desc);
            } else {
                try ptr.init(desc);
            }

            return .from_untyped(id);
        }

        pub fn destroy_fn(self: *Device, h: TypedHandle(resource_type)) void {
            switch (resource_type) {
                .buffer => self.buffers.destroy(h, self.allocator, Buffer.deinit),
                .texture => self.textures.destroy(h, self.allocator, Texture.deinit),
                .graphic_pipeline => self.graphic_pipelines.destroy(h, self.allocator, GraphicPipeline.deinit),
                .compute_pipeline => self.compute_pipelines.destroy(h, self.allocator, ComputePipeline.deinit),
                .shader => self.shaders.destroy(h, self.allocator, Shader.deinit),
                else => unreachable,
            }
        }

        pub fn get_fn(self: *Device, h: TypedHandle(resource_type)) ?*data_type {
            return switch (resource_type) {
                .buffer => self.buffers.get(h.to_untyped()),
                .texture => self.textures.get(h.to_untyped()),
                .graphic_pipeline => self.graphic_pipelines.get(h.to_untyped()),
                .compute_pipeline => self.compute_pipelines.get(h.to_untyped()),
                .shader => self.shaders.get(h.to_untyped()),
                else => unreachable,
            };
        }
    };
}

pub const create_buffer = create(.buffer).create_fn;
pub const destroy_buffer = create(.buffer).destroy_fn;
pub const get_buffer = create(.buffer).get_fn;

pub const create_texture = create(.texture).create_fn;
pub const destroy_texture = create(.texture).destroy_fn;
pub const get_texture = create(.texture).get_fn;

pub const create_graphics_pipeline = create(.graphic_pipeline).create_fn;
pub const destroy_graphics_pipeline = create(.graphic_pipeline).destroy_fn;
pub const get_graphics_pipeline = create(.graphic_pipeline).get_fn;

pub const create_compute_pipeline = create(.compute_pipeline).create_fn;
pub const destroy_compute_pipeline = create(.compute_pipeline).destroy_fn;
pub const get_compute_pipeline = create(.compute_pipeline).get_fn;

pub const create_shader = create(.shader).create_fn;
pub const destroy_shader = create(.shader).destroy_fn;
pub const get_shader = create(.shader).get_fn;
