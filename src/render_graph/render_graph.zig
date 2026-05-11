const std = @import("std");
const Pass = @import("pass.zig");

const Device = @import("../Device2.zig");
const TextureHandle = @import("../Device2.zig").TextureHandle;
const BufferHandle = @import("../Device2.zig").BufferHandle;
const Texture = @import("../resource/texture.zig");
const Buffer = @import("../resource/buffer.zig");

pub const RenderGraph = @This();

pub fn RefCounted(comptime T: type) type {
    return struct {
        data: T,
        ref_count: u32 = 0,

        pub fn init(data: T) @This() {
            return .{ .data = data, .ref_count = 0 };
        }
    };
}

const FBOKey = struct {
    color: [8]TextureHandle,
    color_count: u8,
    depth: ?TextureHandle,
};

allocator: std.mem.Allocator,
device: *Device,

frame_arena: std.heap.ArenaAllocator,
textures: std.array_list.Aligned(RefCounted(Pass.RGTextureDesc), null) = .empty,
buffers: std.array_list.Aligned(RefCounted(Pass.RGBufferDesc), null) = .empty,
passes: std.array_list.Aligned(Pass.RGPass, null) = .empty,
tex_outputs: std.array_list.Aligned(Pass.RGTextureHandle, null) = .empty,
buf_outputs: std.array_list.Aligned(Pass.RGBufferHandle, null) = .empty,

fbo_cache: std.AutoHashMapUnmanaged(FBOKey, u32),

pub fn init(allocator: std.mem.Allocator, device: *Device) RenderGraph {
    return .{
        .allocator = allocator,
        .device = device,
        .frame_arena = .init(allocator),
    };
}

pub fn deinit(self: *RenderGraph) void {
    self.frame_arena.deinit();
}

pub fn begin_frame(self: *RenderGraph) void {
    self.textures = .empty;
    self.buffers = .empty;
    self.passes = .empty;
}

pub fn end_frame(self: *RenderGraph) void {
    self.frame_arena.reset(.retain_capacity);
}

pub fn import_texture(self: *RenderGraph, handle: TextureHandle) !Pass.RGTextureHandle {
    const index = self.textures.items.len;
    try self.textures.append(self.frame_arena.allocator(), .init(.{
        .imported = handle,
    }));

    return .{ .id = @intCast(index) };
}

pub fn transient_texture(self: *RenderGraph, desc: Texture.TextureDesc) !Pass.RGTextureHandle {
    const index = self.textures.items.len;
    try self.textures.append(self.frame_arena.allocator(), .init(.{
        .transient = desc,
    }));
    return .{ .id = @intCast(index) };
}

pub fn import_buffer(self: *RenderGraph, handle: BufferHandle) !Pass.RGBufferHandle {
    const index = self.buffers.items.len;
    try self.buffers.append(self.frame_arena.allocator(), .init(.{
        .imported = handle,
    }));
    return .{ .id = @intCast(index) };
}

pub fn transient_buffer(self: *RenderGraph, desc: Buffer.BufferDesc) !Pass.RGBufferHandle {
    const index = self.buffers.items.len;
    try self.buffers.append(self.frame_arena.allocator(), .init(.{
        .transient = desc,
    }));
    return .{ .id = @intCast(index) };
}

pub fn mark_output_texture(self: *RenderGraph, handle: Pass.RGTextureHandle) !void {
    try self.tex_outputs.append(self.frame_arena.allocator(), handle);
}

pub fn mark_output_buffer(self: *RenderGraph, handle: Pass.RGBufferHandle) !void {
    try self.buf_outputs.append(self.frame_arena.allocator(), handle);
}

fn resolve_texture(self: *RenderGraph, handle: Pass.RGTextureHandle) !TextureHandle {
    const rg_desc = self.textures.items[@intCast(handle.id)].data;
    switch (rg_desc) {
        .imported => |h| return h,
        .transient => |d| {
            const id, const ptr = try self.device.textures.set();
            ptr.init(&d);

            return id;
        },
    }
}

fn resolve_buffer(self: *RenderGraph, handle: Pass.RGBufferHandle) !TextureHandle {
    const rg_desc = self.buffers.items[@intCast(handle.id)].data;
    switch (rg_desc) {
        .imported => |h| return h,
        .transient => |d| {
            const id, const ptr = try self.device.buffers.set();
            ptr.init(&d);
            return id;
        },
    }
}

fn get_or_put_fbo(self: *RenderGraph, pass: *Pass.RGPass) !u32 {
    const key = 
}

pub const PassBuilder = struct {
    pass: *Pass.RGPass,
    graph: *RenderGraph,

    tex_reads: std.array_list.Aligned(Pass.RGTextureHandle, null) = .empty,
    tex_writes: std.array_list.Aligned(Pass.RGTextureHandle, null) = .empty,

    buf_reads: std.array_list.Aligned(Pass.RGBufferHandle, null) = .empty,
    buf_writes: std.array_list.Aligned(Pass.RGBufferHandle, null) = .empty,

    pub fn set_type(self: @This(), t: Pass.PassType) void {
        self.pass.type = t;
    }

    pub fn read_texture(self: @This(), h: Pass.RGTextureHandle) !void {
        try self.tex_reads.append(self.graph.allocator, h);
        self.graph.textures.items[@intCast(h.id)].ref_count += 1;
    }

    pub fn write_texture(self: @This(), h: Pass.RGTextureHandle) !void {
        try self.tex_writes.append(self.graph.allocator, h);
    }

    pub fn read_buffer(self: @This(), h: Pass.RGBufferHandle) !void {
        try self.buf_reads.append(self.graph.allocator, h);
        self.graph.buffers.items[@intCast(h.id)].ref_count += 1;
    }

    pub fn write_buffer(self: @This(), h: Pass.RGBufferHandle) !void {
        try self.buf_writes.append(self.graph.allocator, h);
    }

    pub fn set_color_attachment(self: @This(), h: Pass.RGTextureHandle) !void {
        if (self.pass.color_attachment_count >= 8) return error.OutOfMemory;
        self.pass.color_attachments[self.pass.color_attachment_count] = h;
        try self.write_texture(h);
    }

    pub fn set_depth_attachment(self: @This(), h: Pass.RGTextureHandle) !void {
        self.pass.depth_attachment[self.pass.color_attachment_count] = h;
        try self.write_texture(h);
    }

    pub fn set_execute_callback(self: @This(), callback: *const fn (ctx: *anyopaque, pass: Pass.PassContext) void) void {
        self.pass.execute_fn = callback;
    }

    pub fn finish(self: @This()) !void {
        self.pass.tex_writes = try self.tex_writes.toOwnedSlice(self.graph.allocator);
        self.pass.tex_reads = try self.tex_reads.toOwnedSlice(self.graph.allocator);
        self.pass.buf_writes = try self.buf_writes.toOwnedSlice(self.graph.allocator);
        self.pass.buf_reads = try self.buf_reads.toOwnedSlice(self.graph.allocator);
    }
};

pub fn add_pass(self: *RenderGraph, comptime name: []const u8, comptime Ctx: type, comptime ExternalData: type, setup: *const fn (data: *Ctx, b: PassBuilder, ext: *const ExternalData) anyerror!void, ext: *const ExternalData) !void {
    const pass = try self.passes.addOne(self.allocator);

    pass.name = name;

    const ctx = try self.frame_arena.allocator().create(Ctx);
    pass.execute_ctx = @ptrCast(ctx);

    const builder: PassBuilder = .{
        .graph = self,
        .pass = pass,
    };
    try setup(ctx, builder, ext);
}

pub fn cull_passes(self: *RenderGraph) void {
    for (self.tex_outputs.items) |rgh| {
        self.textures.items[@intCast(rgh.id)].ref_count += 1;
    }

    for (self.buf_outputs.items) |rgh| {
        self.buffers.items[@intCast(rgh.id)].ref_count += 1;
    }

    var i = self.passes.items.len;
    while (i > 0) {
        i -= 1;
        const pass = &self.passes.items[i];

        const alive = blk: {
            for (pass.tex_writes) |rgh| {
                if (self.textures.items[@intCast(rgh.id)].ref_count > 0) break :blk true;
            }

            for (pass.buf_writes) |rgh| {
                if (self.buffers.items[@intCast(rgh.id)].ref_count > 0) break :blk true;
            }

            break :blk false;
        };

        if (!alive) {
            continue;
        }

        pass.ref_count += 1;

        for (pass.tex_reads) |rgh| {
            self.textures.items[@intCast(rgh.id)].ref_count += 1;
        }

        for (pass.buf_reads) |rgh| {
            self.buffers.items[@intCast(rgh.id)].ref_count += 1;
        }
    }
}

pub fn validate_no_cycles(self: *RenderGraph) !void {
    var last_write: std.AutoHashMap(u16, usize) = .init(self.frame_arena.allocator());

    for (self.passes.items, 0..) |*pass, pass_idx| {
        for (pass.tex_reads) |rgh| {
            if (last_write.get(rgh.id)) |writer_idx| {
                if (writer_idx > pass_idx) {
                    std.log.err(
                        "Frame graph cycle: pass '{s}' (index {}) reads texture {} " ++
                            "written by pass '{s}' (index {}) which comes later",
                        .{
                            pass.name,  pass_idx,
                            rgh.id,     self.passes.items[writer_idx].name,
                            writer_idx,
                        },
                    );
                    return error.frame_graph_cycle;
                }
            }
        }

        for (pass.buf_reads) |rgh| {
            if (last_write.get(rgh.id + 0x8000)) |writer_idx| { // offset to avoid collision with texture ids
                if (writer_idx > pass_idx) {
                    std.log.err(
                        "Frame graph cycle: pass '{s}' reads buffer {} " ++
                            "written by pass '{s}' which comes later",
                        .{ pass.name, rgh.id, self.passes.items[writer_idx].name },
                    );
                    return error.frame_graph_cycle;
                }
            }
        }

        for (pass.tex_writes) |rgh| {
            try last_write.put(rgh.id, pass_idx);
        }

        for (pass.buf_writes) |rgh| {
            try last_write.put(rgh.id + 0x8000, pass_idx);
        }
    }
}

// TODO
pub fn insert_barriers(_: *RenderGraph) void {}
