const std = @import("std");
const gl = @import("../gl4_6.zig");

const ShaderHandle = @import("../device.zig").ShaderHandle;
const TextureFormat = @import("texture.zig").TextureFormat;
const Device = @import("../device.zig");

// Vertex Data
pub const VertexInputRate = enum {
    vertex,
    instance,
};

pub const VertexFormat = struct {
    pub const Info = struct {
        component_type: u32, // gl.FLOAT, gl.HALF_FLOAT, gl.INT, etc.
        component_count: u32, // 1, 2, 3, 4
        normalized: bool,
    };

    pub const f32x1: Info = .{ .component_type = gl.FLOAT, .component_count = 1, .normalized = false };
    pub const f32x2: Info = .{ .component_type = gl.FLOAT, .component_count = 2, .normalized = false };
    pub const f32x3: Info = .{ .component_type = gl.FLOAT, .component_count = 3, .normalized = false };
    pub const f32x4: Info = .{ .component_type = gl.FLOAT, .component_count = 4, .normalized = false };
    pub const f16x2: Info = .{ .component_type = gl.HALF_FLOAT, .component_count = 2, .normalized = false };
    pub const f16x4: Info = .{ .component_type = gl.HALF_FLOAT, .component_count = 4, .normalized = false };
    pub const u8x4_norm: Info = .{ .component_type = gl.UNSIGNED_BYTE, .component_count = 4, .normalized = true };
    pub const i16x2_norm: Info = .{ .component_type = gl.SHORT, .component_count = 2, .normalized = true };
    pub const u32x1: Info = .{ .component_type = gl.UNSIGNED_INT, .component_count = 1, .normalized = false };
};

pub const VertexAttribute = struct {
    location: u32,
    binding: u32,
    format: VertexFormat.Info,
    offset: u32,
};

pub const VertexBinding = struct {
    binding: u32,
    stride: u32,
    input_rate: VertexInputRate = .vertex,
};

pub const VertexLayout = struct {
    attributes: []const VertexAttribute,
    binding: []const VertexBinding,
};

// Rasterizer
pub const PolygonMode = enum(u32) { fill = gl.FILL, line = gl.LINE, point = gl.POINT };
pub const CullMode = enum(u32) { none, front = gl.FRONT, back = gl.BACK };
pub const FrontFace = enum(u32) { ccw = gl.CCW, cw = gl.CW };
pub const DepthBias = struct {
    constant_factor: f32 = 0.0,
    slop_factor: f32 = 0.0,
    //clamp: f32 = 0.0, // requires GL_EXT_polygon_offset_clamp
};

pub const RasterizerState = struct {
    polygon_mode: PolygonMode = .fill,
    cull_mode: CullMode = .back,
    front_face: FrontFace = .ccw,
    depth_bias: ?DepthBias = null,
    depth_clamp: bool = false,
    scissor_test: bool = false,
    rasterizer_discard: bool = false,
};

// Depth Stencil

pub const CompareOp = enum(u32) {
    never = gl.NEVER,
    less = gl.LESS,
    equal = gl.EQUAL,
    lequal = gl.LEQUAL,
    greater = gl.GREATER,
    nequal = gl.NOTEQUAL,
    gequal = gl.GEQUAL,
    always = gl.ALWAYS,
};

pub const StencilOp = enum(u32) {
    keep = gl.KEEP,
    zero = gl.ZERO,
    replace = gl.REPLACE,
    incr_clamp = gl.INCR,
    decr_clamp = gl.DECR,
    invert = gl.INVERT,
    incr_wrap = gl.INCR_WRAP,
    decr_wrap = gl.DECR_WRAP,
};

pub const DepthStencilState = struct {
    // Depth
    depth_test: bool = true,
    depth_write: bool = true,
    depth_compare: CompareOp = .less,

    // Stencil
    stencil_test: bool = false,
    front: StencilFaceState = .{},
    back: StencilFaceState = .{},
};

pub const StencilFaceState = struct {
    fail_op: StencilOp = .keep,
    depth_fail_op: StencilOp = .keep,
    pass_op: StencilOp = .keep,
    compare: CompareOp = .always,
    compare_mask: u8 = 0xFF,
    write_mask: u8 = 0xFF,
    reference: u8 = 0,
};

// Blend

pub const BlendFactor = enum(u32) {
    zero = gl.ZERO,
    one = gl.ONE,
    src_color = gl.SRC_COLOR,
    one_minus_src_color = gl.ONE_MINUS_SRC_COLOR,
    dst_color = gl.DST_COLOR,
    one_minus_dst_color = gl.ONE_MINUS_DST_COLOR,
    src_alpha = gl.SRC_ALPHA,
    one_minus_src_alpha = gl.ONE_MINUS_SRC_ALPHA,
    dst_alpha = gl.DST_ALPHA,
    one_minus_dst_alpha = gl.ONE_MINUS_DST_ALPHA,
    constant_color = gl.CONSTANT_COLOR,
    one_minus_constant = gl.ONE_MINUS_CONSTANT_COLOR,
    src_alpha_saturate = gl.SRC_ALPHA_SATURATE,
    // dual-source blending (GL_ARB_blend_func_extended)
    src1_color = gl.SRC1_COLOR,
    one_minus_src1_color = gl.ONE_MINUS_SRC1_COLOR,
    src1_alpha = gl.SRC1_ALPHA,
    one_minus_src1_alpha = gl.ONE_MINUS_SRC1_ALPHA,
};

pub const BlendOp = enum(u32) {
    add = gl.FUNC_ADD,
    subtract = gl.FUNC_SUBTRACT,
    reverse_subtract = gl.FUNC_REVERSE_SUBTRACT,
    min = gl.MIN,
    max = gl.MAX,
};

pub const ColorWriteMask = packed struct(u4) {
    r: bool = true,
    g: bool = true,
    b: bool = true,
    a: bool = true,
};

// Per-attachment blend state — maps to glBlendFuncSeparatei / glBlendEquationSeparatei
pub const AttachmentBlendState = struct {
    blend_enable: bool = false,
    src_color: BlendFactor = .one,
    dst_color: BlendFactor = .zero,
    color_op: BlendOp = .add,
    src_alpha: BlendFactor = .one,
    dst_alpha: BlendFactor = .zero,
    alpha_op: BlendOp = .add,
    write_mask: ColorWriteMask = .{},
};

pub const BlendState = struct {
    // Per-attachment — index matches color attachment index in the framebuffer
    // For your G-buffer pass you'll have 3-4 attachments with blend disabled on all.
    // For your lighting/transparency pass you'll have blend on attachment 0 only.
    attachments: []const AttachmentBlendState,
    blend_constants: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const GraphicPipelineDesc = struct {
    vertex_shader: ShaderHandle,
    fragment_shader: ShaderHandle,
    tess_control_shader: ?ShaderHandle = null,
    tess_eval_shader: ?ShaderHandle = null,

    vertex_layout: VertexLayout,
    rasterizer_state: RasterizerState = .{},
    depth_stencil_state: DepthStencilState = .{},
    blend_state: BlendState,

    color_attachment_formats: []const TextureFormat,
    depth_format: ?TextureFormat = null,

    debug_name: ?[]const u8 = null,
};

pub const GraphicPipeline = @This();

pub const StageBit = packed struct(u8) {
    vertex: bool = false,
    fragment: bool = false,
    tess_control: bool = false,
    tess_eval: bool = false,
    __padding: u4 = 0,
};

program_handle: u32,
stages: StageBit,

vao_handle: u32,

vao_hash: u64,
vertex_layout: VertexLayout,
rasterizer_state: RasterizerState = .{},
depth_stencil_state: DepthStencilState = .{},
blend_state: BlendState,

color_attachment_formats: []const TextureFormat,
depth_format: ?TextureFormat = null,

fn compute_vertex_array_hash(vertex_layout: *const VertexLayout) u64 {
    var hash: std.hash.Wyhash = .init(0x0129302);

    hash.update(std.mem.asBytes(vertex_layout.attributes));
    hash.update(std.mem.asBytes(vertex_layout.binding));

    return hash.final();
}

pub fn init(self: *GraphicPipeline, device: *Device, desc: *const GraphicPipelineDesc) !void {
    self.program_handle = gl.createProgram();
    self.stages = .{};

    self.vertex_layout = desc.vertex_layout;
    self.rasterizer_state = desc.rasterizer_state;
    self.depth_stencil_state = desc.depth_stencil_state;
    self.blend_state = desc.blend_state;

    self.color_attachment_formats = desc.color_attachment_formats;
    self.depth_format = desc.depth_format;

    const vertex_shader = device.shaders.get(desc.vertex_shader.to_untyped()) orelse return error.missing_shader;
    const fragment_shader = device.shaders.get(desc.fragment_shader.to_untyped()) orelse return error.missing_shader;
    const tess_control_shader = if (desc.tess_control_shader) |handle| device.shaders.get(handle.to_untyped()) orelse return error.missing_shader else null;
    const tess_eval_shader = if (desc.tess_eval_shader) |handle| device.shaders.get(handle.to_untyped()) orelse return error.missing_shader else null;

    gl.attachShader(self.program_handle, vertex_shader.handle);
    self.stages.vertex = true;
    gl.attachShader(self.program_handle, fragment_shader.handle);
    self.stages.fragment = true;
    if (tess_control_shader) |sh| gl.attachShader(self.program_handle, sh.handle);
    self.stages.tess_control = tess_control_shader != null;
    if (tess_eval_shader) |sh| gl.attachShader(self.program_handle, sh.handle);
    self.stages.tess_eval = tess_eval_shader != null;

    gl.linkProgram(self.program_handle);
    {
        var success: i32 = 0;
        gl.getProgramiv(self.program_handle, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            var size: isize = 0;
            var buffer: [1024]u8 = undefined;
            gl.getProgramInfoLog(self.program_handle, 1024, @ptrCast(&size), (&buffer).ptr);
            std.log.err("Failed to link program: {s}", .{buffer[0..@intCast(size)]});
            return error.program_linking_failed;
        }
    }

    gl.detachShader(self.program_handle, vertex_shader.handle);
    gl.detachShader(self.program_handle, fragment_shader.handle);
    if (tess_control_shader) |sh| gl.detachShader(self.program_handle, sh.handle);
    if (tess_eval_shader) |sh| gl.detachShader(self.program_handle, sh.handle);

    self.vao_hash, self.vao_handle = try device.create_vertex_array(&desc.vertex_layout);
    if (desc.debug_name) |label| {
        gl.objectLabel(gl.PROGRAM, self.program_handle, @intCast(label.len), label.ptr);
    }
}

pub fn deinit(self: *GraphicPipeline, device: *Device) void {
    gl.deleteProgram(self.program_handle);
    device.destroy_vertex_array(self.vao_hash);
}

fn enable_or_disable(flag: u32, value: bool) void {
    switch (value) {
        true => gl.enable(flag),
        false => gl.disable(flag),
    }
}

pub fn apply_rasterizer_state(self: *const GraphicPipeline) void {
    gl.polygonMode(gl.FRONT_AND_BACK, @intFromEnum(self.rasterizer_state.polygon_mode));

    if (self.rasterizer_state.cull_mode == .none) {
        gl.disable(gl.CULL_FACE);
    } else {
        gl.enable(gl.CULL_FACE);
        gl.cullFace(@intFromEnum(self.rasterizer_state.cull_mode));
    }

    gl.frontFace(@intFromEnum(self.rasterizer_state.front_face));

    enable_or_disable(gl.POLYGON_OFFSET_FILL, self.rasterizer_state.depth_bias != null);
    enable_or_disable(gl.POLYGON_OFFSET_LINE, self.rasterizer_state.depth_bias != null);
    enable_or_disable(gl.POLYGON_OFFSET_POINT, self.rasterizer_state.depth_bias != null);
    if (self.rasterizer_state.depth_bias) |bias| {
        gl.polygonOffset(bias.slop_factor, bias.constant_factor);
    }

    enable_or_disable(gl.DEPTH_CLAMP, self.rasterizer_state.depth_clamp);
    enable_or_disable(gl.SCISSOR_TEST, self.rasterizer_state.scissor_test);
    enable_or_disable(gl.RASTERIZER_DISCARD, self.rasterizer_state.rasterizer_discard);
}

fn apply_stencil_face(face: u32, state: *const StencilFaceState) void {
    gl.stencilFuncSeparate(
        face,
        @intFromEnum(state.compare),
        state.reference,
        state.compare_mask,
    );
    gl.stencilOpSeparate(
        face,
        @intFromEnum(state.fail_op),
        @intFromEnum(state.depth_fail_op),
        @intFromEnum(state.pass_op),
    );
    gl.stencilMaskSeparate(face, state.write_mask);
}

pub fn apply_depth_stencil_state(self: *const GraphicPipeline) void {
    if (self.depth_stencil_state.depth_test) {
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(@intFromEnum(self.depth_stencil_state.depth_compare));
    } else {
        gl.disable(gl.DEPTH_TEST);
    }

    gl.depthMask(if (self.depth_stencil_state.depth_write) gl.TRUE else gl.FALSE);

    if (self.depth_stencil_state.stencil_test) {
        gl.enable(gl.STENCIL_TEST);
        apply_stencil_face(gl.FRONT, &self.depth_stencil_state.front);
        apply_stencil_face(gl.BACK, &self.depth_stencil_state.back);
    }
}

fn apply_attachment_blend(slot: u32, attachment: AttachmentBlendState) void {
    if (!attachment.blend_enable) {
        gl.disablei(gl.BLEND, slot);
        gl.colorMaski(
            slot,
            if (attachment.write_mask.r) gl.TRUE else gl.FALSE,
            if (attachment.write_mask.g) gl.TRUE else gl.FALSE,
            if (attachment.write_mask.b) gl.TRUE else gl.FALSE,
            if (attachment.write_mask.a) gl.TRUE else gl.FALSE,
        );
        return;
    }

    gl.enablei(gl.BLEND, slot);
    gl.blendFuncSeparatei(
        slot,
        @intFromEnum(attachment.src_color),
        @intFromEnum(attachment.dst_color),
        @intFromEnum(attachment.src_alpha),
        @intFromEnum(attachment.dst_alpha),
    );

    gl.blendEquationSeparatei(
        slot,
        @intFromEnum(attachment.color_op),
        @intFromEnum(attachment.alpha_op),
    );

    gl.colorMaski(
        slot,
        if (attachment.write_mask.r) gl.TRUE else gl.FALSE,
        if (attachment.write_mask.g) gl.TRUE else gl.FALSE,
        if (attachment.write_mask.b) gl.TRUE else gl.FALSE,
        if (attachment.write_mask.a) gl.TRUE else gl.FALSE,
    );
}

pub fn apply_blend(self: *const GraphicPipeline) void {
    gl.blendColor(
        self.blend_state.blend_constants[0],
        self.blend_state.blend_constants[1],
        self.blend_state.blend_constants[2],
        self.blend_state.blend_constants[3],
    );

    for (self.blend_state.attachments, 0..) |attachment, i| {
        apply_attachment_blend(@intCast(i), attachment);
    }
}

pub fn apply_state(self: *const GraphicPipeline) void {
    self.apply_rasterizer_state();
    self.apply_depth_stencil_state();
    self.apply_blend();
}
