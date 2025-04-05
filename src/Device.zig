const std = @import("std");
const gl = @import("gl4_6.zig");

const DeviceLimit = @import("./Resources/DeviceLimits.zig");

const Element = @import("./Resources/Element.zig").Element;
pub const Program = @import("./Pipeline/Program.zig");
pub const GraphicPipeline = @import("./Pipeline/Graphic.zig");
pub const ComputePipeline = @import("./Pipeline/Compute.zig");
pub const Buffer = @import("./Resources/Buffer.zig");
pub const MappedBuffer = @import("./Resources/Buffer/MappedBuffer.zig");
pub const DynamicBuffer = @import("./Resources/DynamicBuffer.zig");
pub const StaticBuffer = @import("./Resources/StaticBuffer.zig");
pub const Texture = @import("./Resources/Texture/Texture.zig");
pub const Texture2D = @import("./Resources/Texture/Texture2D.zig");
pub const TextureCube = @import("./Resources/Texture/TextureCube.zig");
pub const BindlessTexture = @import("./Resources/Texture/BindlessTexture.zig");
pub const Framebuffer = @import("./Resources/Framebuffer2.zig");
const VertexArrayObject = @import("./Resources/VertexArrayObject.zig");

const MemoryBarrier = @import("./Resources/MemoryBarrier.zig");
const Fence = @import("./Resources/Fence.zig");

pub const Device = @This();
pub const DeviceLogger = std.log.scoped(.Device);

const BufferType = enum {
    Uniform,
    ShaderStorage,
    Texture,
    TransfromFeedback,
};

const Pipeline = union(enum) {
    Graphic: []const u8,
    Compute: []const u8,
};

allocator: std.mem.Allocator,
limits: DeviceLimit,

// Managed data
programs: std.StringHashMapUnmanaged(Program),
graphicPipeline: std.StringHashMapUnmanaged(*GraphicPipeline),
computePipeline: std.StringHashMapUnmanaged(*ComputePipeline),

framebuffers: std.StringHashMapUnmanaged(Framebuffer),

vertexArrayObjectCounter: u32 = 1,
vertexArrayObject: std.AutoArrayHashMapUnmanaged(u32, VertexArrayObject),

// State
currentPipeline: Pipeline = .{ .Graphic = &.{} },
currentFramebuffer: ?Framebuffer,
currentVertexArray: u32,

currentTopology: GraphicPipeline.PipelineInputAssemblyState.PrimitiveTopology,
currentElementType: Element,

currentViewport: Viewport,
swapchainExtent: ViewportExtent,

textureSlots: [8]u32,

pub fn init(self: *Device, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;
    self.limits = DeviceLimit.init();

    self.programs = .{};
    self.graphicPipeline = .{};
    self.computePipeline = .{};
    self.framebuffers = .{};
    self.vertexArrayObjectCounter = 1;
    self.vertexArrayObject = .{};
    self.currentTopology = .triangle;
    self.currentElementType = .u32;
    self.currentViewport = .{
        .extent = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    };
    self.swapchainExtent = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    self.currentFramebuffer = null;
    self.textureSlots = [1]u32{0} ** 8;

    const renderer = gl.getString(gl.RENDERER) orelse "null";
    const vendor = gl.getString(gl.VENDOR) orelse "null";
    const version = gl.getString(gl.VERSION) orelse "null";
    DeviceLogger.info("Running {s} on {s} {s}", .{ version, renderer, vendor });
}

pub fn deinit(self: *Device) void {
    {
        var ite = self.programs.iterator();
        while (ite.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            gl.deleteProgram(entry.value_ptr.handle);
        }
        self.programs.deinit(self.allocator);
    }
    {
        var ite = self.graphicPipeline.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.graphicPipeline.deinit(self.allocator);
    }
    {
        var ite = self.computePipeline.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.computePipeline.deinit(self.allocator);
    }
    {
        var ite = self.framebuffers.iterator();
        while (ite.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.framebuffers.deinit(self.allocator);
    }
    {
        for (self.vertexArrayObject.values()) |value| {
            gl.deleteVertexArrays(1, @ptrCast(&value.handle));
        }
        self.vertexArrayObject.deinit(self.allocator);
    }
}

pub fn loadShader(self: *Device, name: []const u8, sources: []const Program.ShaderSource) !bool {
    if (self.programs.contains(name)) return false;

    var program: Program = undefined;
    try program.init(sources);

    try self.programs.put(self.allocator, try self.allocator.dupe(u8, name), program);
    DeviceLogger.info("Sucessfuly created Program {s}", .{name});
    return true;
}

fn createVertexArrayObject(self: *Device, createInfo: *const GraphicPipeline.PipelineVertexInputState) !struct {
    id: u32,
    vao: *VertexArrayObject,
} {
    var ite = self.vertexArrayObject.iterator();
    while (ite.next()) |entry| {
        if (entry.value_ptr.vertexInputState.eql(createInfo)) {
            DeviceLogger.info("Found already existing vertex array object", .{});
            return .{
                .id = entry.key_ptr.*,
                .vao = entry.value_ptr,
            };
        }
    }

    const id = self.vertexArrayObjectCounter;
    self.vertexArrayObjectCounter += 1;

    var new_vao: VertexArrayObject = undefined;
    new_vao.init(createInfo);

    try self.vertexArrayObject.put(self.allocator, id, new_vao);
    return .{
        .id = id,
        .vao = self.vertexArrayObject.getPtr(id) orelse unreachable,
    };
}

pub fn createGraphicPipeline(self: *Device, name: []const u8, createInfo: *const GraphicPipeline.GraphicPipelineCreateInfo) !*GraphicPipeline {
    if (self.graphicPipeline.get(name)) |p| {
        return p;
    }

    const vao = try self.createVertexArrayObject(&createInfo.vertexInputState);
    DeviceLogger.info("ProgramPipeline {s} uses VAO {}", .{ name, vao.id });
    const new = try self.allocator.create(GraphicPipeline);
    try new.init(&self.programs, createInfo, vao.id);

    if (self.graphicPipeline.size == 0) {
        self.currentPipeline = .{ .Graphic = name };
        gl.bindProgramPipeline(new.handle);
        if (vao.id != 0) gl.bindVertexArray(vao.vao.handle);
        self.currentVertexArray = vao.id;
        new.force();
    }

    gl.objectLabel(gl.PROGRAM_PIPELINE, new.handle, @intCast(name.len), @ptrCast(name.ptr));

    try self.graphicPipeline.put(self.allocator, try self.allocator.dupe(u8, name), new);
    return new;
}

pub fn createComputePipeline(self: *Device, name: []const u8, shader: []const u8) !*ComputePipeline {
    if (self.computePipeline.get(name)) |p| {
        return p;
    }

    const new = try self.allocator.create(ComputePipeline);
    try new.init(shader);

    gl.objectLabel(gl.PROGRAM, new.handle, @intCast(name.len), @ptrCast(name.ptr));
    try self.computePipeline.put(self.allocator, try self.allocator.dupe(u8, name), new);
    return new;
}

fn bindVertexArrayObject(self: *Device, id: u32) bool {
    if (id == 0) {
        self.currentVertexArray = 0;
        gl.bindVertexArray(0);
        return true;
    } else if (self.currentVertexArray != id) {
        const vao = self.vertexArrayObject.get(id) orelse return false;
        self.currentVertexArray = id;
        gl.bindVertexArray(vao.handle);
        return true;
    }
    return true;
}

pub fn bindGraphicPipeline(self: *Device, name: []const u8) bool {
    const nPipeline: *GraphicPipeline = self.graphicPipeline.get(name) orelse return false;

    switch (self.currentPipeline) {
        .Graphic => |pName| {
            gl.bindProgramPipeline(nPipeline.handle);
            if (nPipeline.vao != self.currentVertexArray and !self.bindVertexArrayObject(nPipeline.vao)) {
                std.log.err("{s} doesn't have a valid vertex array object", .{name});
                return false;
            }
            if (self.graphicPipeline.get(pName)) |pPipeline| {
                nPipeline.update(pPipeline);
            } else {
                nPipeline.force();
            }
        },
        .Compute => {
            gl.useProgram(0);
            gl.bindProgramPipeline(nPipeline.handle);
            if (nPipeline.vao != self.currentVertexArray and !self.bindVertexArrayObject(nPipeline.vao)) {
                std.log.err("{s} doesn't have a valid vertex array object", .{name});
                return false;
            }
            nPipeline.force();
        },
    }

    self.currentPipeline = .{ .Graphic = name };
    self.currentTopology = nPipeline.inputAssemblyState.topology;
    return true;
}

pub fn bindComputePipeline(self: *Device, name: []const u8) bool {
    const nPipeline = self.computePipeline.get(name) orelse return false;

    gl.useProgram(nPipeline.handle);
    gl.bindProgramPipeline(0);
    self.currentPipeline = .{ .Compute = name };
    return true;
}

pub fn bindStorageBuffer(_: *Device, slot: u32, buffer: Buffer, binding: Buffer.Binding) void {
    switch (binding) {
        ._whole => gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, slot, buffer.handle),
        ._range => |range| gl.bindBufferRange(gl.SHADER_STORAGE_BUFFER, slot, buffer.handle, range[0], range[1]),
    }
}

pub fn bindUniformBuffer(_: *Device, slot: u32, buffer: Buffer, binding: Buffer.Binding) void {
    switch (binding) {
        ._whole => gl.bindBufferBase(gl.UNIFORM_BUFFER, slot, buffer.handle),
        ._range => |range| gl.bindBufferRange(gl.UNIFORM_BUFFER, slot, buffer.handle, range[0], range[1]),
    }
}

pub fn bindVertexBuffer(self: *Device, slot: u32, buffer: Buffer, offset: u32, stride: ?i32) void {
    if (self.currentVertexArray == 0) return;

    const vao = self.vertexArrayObject.get(self.currentVertexArray) orelse unreachable;
    const st: i32 = if (stride) |s| s else @intCast(buffer.stride);
    gl.vertexArrayVertexBuffer(
        vao.handle,
        slot,
        buffer.handle,
        @intCast(offset),
        st,
    );
}

pub fn bindElementBuffer(self: *Device, buffer: Buffer, element: Element) void {
    if (self.currentVertexArray == 0) return;

    const vao = self.vertexArrayObject.get(self.currentVertexArray) orelse unreachable;
    gl.vertexArrayElementBuffer(vao.handle, buffer.handle);
    self.currentElementType = element;
}

pub fn draw(self: *const Device, first: i32, count: i32, instanceCount: i32, baseInstance: u32) void {
    gl.drawArraysInstancedBaseInstance(
        @intFromEnum(self.currentTopology),
        first,
        count,
        instanceCount,
        baseInstance,
    );
}

pub fn drawElements(self: *const Device, count: i32, instanceCount: i32, firstIndex: usize, baseVertex: i32, baseInstance: u32) void {
    gl.drawElementsInstancedBaseVertexBaseInstance(
        @intFromEnum(self.currentTopology),
        count,
        @intFromEnum(self.currentElementType),
        @ptrFromInt(firstIndex * self.currentElementType.byteSize()),
        instanceCount,
        baseVertex,
        baseInstance,
    );
}

pub fn setMemoryBarrier(_: *const Device, flags: MemoryBarrier.Flags) void {
    gl.memoryBarrier(@bitCast(flags));
}

pub const AttachmentLoadOp = enum(u32) {
    keep,
    clear,
    dontCare,
};

pub const ViewportExtent = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn eql(self: ViewportExtent, other: ViewportExtent) bool {
        return self.x == other.x and self.y == other.y and self.width == other.width and self.height == other.height;
    }
};

pub const DepthRange = enum(u32) {
    NegativeOneToOne = gl.NEGATIVE_ONE_TO_ONE,
    ZeroToOne = gl.ZERO_TO_ONE,
};

pub const Viewport = struct {
    extent: ViewportExtent,
    minDepth: f32 = -1.0,
    maxDepth: f32 = 1.0,
    depthRange: DepthRange = .NegativeOneToOne,

    pub fn update(self: Viewport, other: Viewport) void {
        if (!self.extent.eql(other.extent)) {
            gl.viewport(
                @intCast(self.extent.x),
                @intCast(self.extent.y),
                @intCast(self.extent.width),
                @intCast(self.extent.height),
            );
        }
        if (self.depthRange != other.depthRange) {
            gl.clipControl(gl.LOWER_LEFT, @intFromEnum(self.depthRange));
        }
        if (self.minDepth != other.minDepth or self.maxDepth != other.maxDepth) {
            gl.depthRangef(self.minDepth, self.maxDepth);
        }
    }
};

pub const ClearInfo = struct {
    colorLoadOp: AttachmentLoadOp = .keep,
    clearColor: [4]f32 = .{ 0, 0, 0, 1 },
    depthLoadOp: AttachmentLoadOp = .keep,
    clearDepthValue: f32 = 0.0,
    stencilLoadOp: AttachmentLoadOp = .keep,
    stencilClearValue: u32 = 0,
};

pub const SwapchainRenderInfo = struct {
    clearInfo: ClearInfo,
    extent: ?ViewportExtent = null,
    minDepth: f32 = -1.0,
    maxDepth: f32 = 1.0,
    depthRange: DepthRange = .NegativeOneToOne,
};

pub fn getSwapchainExtent(self: *const Device) ViewportExtent {
    return self.swapchainExtent;
}

pub fn updateSwapchainExtent(self: *Device, width: u32, height: u32) void {
    self.swapchainExtent.width = width;
    self.swapchainExtent.height = height;
}

pub fn clearSwapchain(_: *const Device, clearInfo: ClearInfo) void {
    switch (clearInfo.colorLoadOp) {
        .keep => {},
        .clear => {
            gl.clearNamedFramebufferfv(
                0,
                gl.COLOR,
                0,
                @ptrCast(&clearInfo.clearColor),
            );
        },
        .dontCare => {},
    }
    switch (clearInfo.depthLoadOp) {
        .keep => {},
        .clear => {
            gl.clearNamedFramebufferfv(
                0,
                gl.DEPTH,
                0,
                @ptrCast(&clearInfo.clearDepthValue),
            );
        },
        .dontCare => {},
    }
    switch (clearInfo.stencilLoadOp) {
        .keep => {},
        .clear => {
            gl.clearNamedFramebufferfv(
                0,
                gl.DEPTH,
                0,
                @ptrCast(&clearInfo.stencilClearValue),
            );
        },
        .dontCare => {},
    }
}

pub fn createFramebuffer(self: *Device, name: []const u8, createInfo: *const Framebuffer.FramebufferCreateInfo) !void {
    const entry = try self.framebuffers.getOrPut(self.allocator, name);
    if (entry.found_existing) {
        entry.value_ptr.deinit();
        try entry.value_ptr.init(createInfo);
    } else {
        try entry.value_ptr.init(createInfo);
    }

    if (std.debug.runtime_safety) {
        gl.objectLabel(gl.FRAMEBUFFER, entry.value_ptr.handle, @intCast(name.len), @ptrCast(name.ptr));
    }
}

pub fn destroyFramebuffer(self: *Device, name: []const u8) bool {
    if (self.framebuffers.get(name)) |fb| {
        fb.deinit();

        return self.framebuffers.remove(name);
    }
    return false;
}

pub fn bindSwapchain(self: *Device) void {
    if (self.currentFramebuffer != null) {
        self.currentFramebuffer = null;
        gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
    }
}

pub fn bindFramebuffer(self: *Device, name: []const u8) bool {
    const nFramebuffer = self.framebuffers.get(name) orelse return false;
    if (self.currentFramebuffer != null and self.currentFramebuffer.?.handle == nFramebuffer.handle) return true;

    self.currentFramebuffer = nFramebuffer;
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, nFramebuffer.handle);

    return true;
}

pub const ColorAttachmentClearInfo = struct {
    loadOp: AttachmentLoadOp = .keep,
    color: [4]f32 = .{ 0, 0, 0, 1 },
};

pub const FramebufferClearInfo = struct {
    colorAttachments: []const ColorAttachmentClearInfo,
    depthLoadOp: AttachmentLoadOp = .keep,
    clearDepthValue: f32 = 0.0,
    stencilLoadOp: AttachmentLoadOp = .keep,
    stencilClearValue: u32 = 0,
};

pub fn clearFramebuffer(self: *Device, name: []const u8, clearInfo: FramebufferClearInfo) void {
    const framebuffer = self.framebuffers.get(name) orelse unreachable;
    std.debug.assert(framebuffer.attachments.len == clearInfo.colorAttachments.len);

    for (clearInfo.colorAttachments, 0..) |attachment, i| {
        switch (attachment.loadOp) {
            .clear => gl.clearNamedFramebufferfv(
                framebuffer.handle,
                gl.COLOR,
                @intCast(i),
                @ptrCast(&attachment.color),
            ),
            else => {},
        }
    }

    if (framebuffer.depthStencilAttachment != 0) {
        switch (clearInfo.depthLoadOp) {
            .clear => gl.clearNamedFramebufferfv(
                framebuffer.handle,
                gl.DEPTH,
                0,
                @ptrCast(&clearInfo.clearDepthValue),
            ),
            else => {},
        }

        switch (clearInfo.stencilLoadOp) {
            .clear => gl.clearNamedFramebufferfv(
                framebuffer.handle,
                gl.STENCIL,
                0,
                @ptrCast(&clearInfo.stencilClearValue),
            ),
            else => {},
        }
    }
}

pub const AttribFlags = enum(u32) {
    GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING,
    GL_VERTEX_ATTRIB_ARRAY_ENABLED,
    GL_VERTEX_ATTRIB_ARRAY_SIZE,
    GL_VERTEX_ATTRIB_ARRAY_STRIDE,
    GL_VERTEX_ATTRIB_ARRAY_TYPE,
    GL_VERTEX_ATTRIB_ARRAY_NORMALIZED,
    GL_VERTEX_ATTRIB_ARRAY_INTEGER,
    GL_VERTEX_ATTRIB_ARRAY_DIVISOR,
    GL_CURRENT_VERTEX_ATTRIB,
};

pub fn getActiveAttrib(self: *Device, index: u32) void {
    std.debug.assert(self.currentVertexArray != 0);

    var vao: i32 = 0;
    gl.getIntegerv(gl.VERTEX_ARRAY_BINDING, &vao);

    var params: [4]i32 = undefined;
    gl.getVertexAttribiv(index, gl.CURRENT_VERTEX_ATTRIB, (&params).ptr);
    DeviceLogger.info("getActiveAttrib({}) = {}: {any}", .{ index, vao, params });
}

pub fn bindTexture(self: *Device, slot: u32, texture: Texture) void {
    if (self.textureSlots[slot] == texture.handle) return;
    gl.bindTextureUnit(slot, texture.handle);
    self.textureSlots[slot] = texture.handle;
}

pub const ImageAccess = enum(u32) {
    readOnly = gl.READ_ONLY,
    writeOnly = gl.WRITE_ONLY,
    readWrite = gl.READ_WRITE,
};

pub fn bindImage(_: *const Device, slot: u32, texture: Texture, level: i32, isLayered: bool, layer: ?i32, access: ImageAccess) void {
    gl.bindImageTexture(
        slot,
        texture.handle,
        level,
        if (isLayered) gl.TRUE else gl.FALSE,
        if (layer) |l| l else 0,
        @intFromEnum(access),
        @intFromEnum(texture.format),
    );
}

pub fn dispatch(self: *const Device, x: u32, y: u32, z: u32) void {
    std.debug.assert(self.currentPipeline == .Compute);

    gl.dispatchCompute(x, y, z);
}
