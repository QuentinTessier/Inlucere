const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("common.zig");

pub const PipelineColorBlendState = @This();

pub const LogicOp = enum(u32) {
    clear = gl.CLEAR,
    set = gl.SET,
    copy = gl.COPY,
    copyInverted = gl.COPY_INVERTED,
    noop = gl.NOOP,
    invert = gl.INVERT,
    and_ = gl.AND,
    nand = gl.NAND,
    or_ = gl.OR,
    nor = gl.NOR,
    xor = gl.XOR,
    equiv = gl.EQUIV,
    andReverse = gl.AND_REVERSE,
    andInverted = gl.AND_INVERTED,
    orReverse = gl.OR_REVERSE,
    OrInverted = gl.OR_INVERTED,
};

pub const BlendFactor = enum(u32) {
    Zero = gl.ZERO,
    One = gl.ONE,
    SrcColor = gl.SRC_COLOR,
    OneMinusSrcColor = gl.ONE_MINUS_SRC_COLOR,
    DstColor = gl.DST_COLOR,
    OneMinusDstColor = gl.ONE_MINUS_DST_COLOR,
    SrcAlpha = gl.SRC_ALPHA,
    OneMinusSrcAlpha = gl.ONE_MINUS_SRC_ALPHA,
    DstAlpha = gl.DST_ALPHA,
    OneMinusDstAlpha = gl.ONE_MINUS_DST_ALPHA,
    ConstantColor = gl.CONSTANT_COLOR,
    OneMinusConstantColor = gl.ONE_MINUS_CONSTANT_COLOR,
    ConstantAlpha = gl.CONSTANT_ALPHA,
    OneMinusConstantAlpha = gl.ONE_MINUS_CONSTANT_ALPHA,
    SrcAlphaSaturate = gl.SRC_ALPHA_SATURATE,
};

pub const BlendOp = enum(u32) {
    Add = gl.FUNC_ADD,
    Substract = gl.FUNC_SUBTRACT,
    ReverseSubstract = gl.FUNC_REVERSE_SUBTRACT,
    Min = gl.MIN,
    Max = gl.MAX,
};

pub const ColorComponentFlags = packed struct(u32) {
    red: bool = true,
    green: bool = true,
    blue: bool = true,
    alpha: bool = true,
    __unused0: u28 = 0,

    pub fn eq(self: ColorComponentFlags, other: ColorComponentFlags) bool {
        return self.red == other.red and self.green == other.green and self.blue == other.blue and self.alpha == other.alpha;
    }
};

pub const ColorAttachmentState = struct {
    blendEnable: bool = false,
    srcRgbFactor: BlendFactor = .One,
    dstRgbFactor: BlendFactor = .Zero,
    colorBlendOp: BlendOp = .Add,
    srcAlphaFactor: BlendFactor = .One,
    dstAlphaFactor: BlendFactor = .Zero,
    alphaBlendOp: BlendOp = .Add,
    colorWriteMask: ColorComponentFlags = .{
        .red = true,
        .green = true,
        .blue = true,
        .alpha = true,
    },

    pub fn eq(self: ColorAttachmentState, other: ColorAttachmentState) bool {
        const b1 = std.mem.asBytes(&self);
        const b2 = std.mem.asBytes(&other);
        return std.mem.eql(u8, b1, b2);
    }
};

logicOpEnable: bool,
logicOp: LogicOp,
attachments: []const ColorAttachmentState,
blendConstants: [4]f32,

pub fn default() PipelineColorBlendState {
    return .{
        .logicOpEnable = false,
        .logicOp = .copy,
        .attachments = &.{},
        .blendConstants = .{ 0, 0, 0, 0 },
    };
}

pub fn update(self: PipelineColorBlendState, other: PipelineColorBlendState) void {
    if (self.logicOpEnable != other.logicOpEnable) {
        common.enableOrDisable(gl.COLOR_LOGIC_OP, self.logicOpEnable);
        if (!other.logicOpEnable or (self.logicOpEnable and self.logicOp != other.logicOp)) {
            gl.logicOp(@intFromEnum(self.logicOp));
        }
    }

    if (!std.mem.eql(f32, &self.blendConstants, &other.blendConstants)) {
        gl.blendColor(self.blendConstants[0], self.blendConstants[1], self.blendConstants[2], self.blendConstants[3]);
    }

    if (self.attachments.len > 0) {
        gl.enable(gl.BLEND);
    } else if (self.attachments.len != other.attachments.len) {
        gl.disable(gl.BLEND);
    }

    for (self.attachments, 0..) |attachment, i| {
        if (i < other.attachments.len and attachment.eq(other.attachments[i])) {
            continue;
        }

        if (attachment.blendEnable) {
            gl.blendFuncSeparatei(
                @intCast(i),
                @intFromEnum(attachment.srcRgbFactor),
                @intFromEnum(attachment.dstRgbFactor),
                @intFromEnum(attachment.srcAlphaFactor),
                @intFromEnum(attachment.dstAlphaFactor),
            );
            gl.blendEquationSeparatei(@intCast(i), @intFromEnum(attachment.colorBlendOp), @intFromEnum(attachment.alphaBlendOp));
        } else {
            gl.blendFuncSeparatei(@intCast(i), gl.SRC_COLOR, gl.ZERO, gl.SRC_ALPHA, gl.ZERO);
            gl.blendEquationSeparatei(@intCast(i), gl.FUNC_ADD, gl.FUNC_ADD);
        }
        const r: gl.GLboolean = if (attachment.colorWriteMask.red) gl.TRUE else gl.FALSE;
        const g: gl.GLboolean = if (attachment.colorWriteMask.green) gl.TRUE else gl.FALSE;
        const b: gl.GLboolean = if (attachment.colorWriteMask.blue) gl.TRUE else gl.FALSE;
        const a: gl.GLboolean = if (attachment.colorWriteMask.alpha) gl.TRUE else gl.FALSE;
        gl.colorMaski(@intCast(i), r, g, b, a);
    }
}

pub fn force(self: PipelineColorBlendState) void {
    common.enableOrDisable(gl.COLOR_LOGIC_OP, self.logicOpEnable);
    gl.logicOp(@intFromEnum(self.logicOp));

    gl.blendColor(self.blendConstants[0], self.blendConstants[1], self.blendConstants[2], self.blendConstants[3]);

    if (self.attachments.len > 0) {
        gl.enable(gl.BLEND);
    } else {
        gl.disable(gl.BLEND);
    }

    for (self.attachments, 0..) |attachment, i| {
        if (attachment.blendEnable) {
            gl.blendFuncSeparatei(
                @intCast(i),
                @intFromEnum(attachment.srcRgbFactor),
                @intFromEnum(attachment.dstRgbFactor),
                @intFromEnum(attachment.srcAlphaFactor),
                @intFromEnum(attachment.dstAlphaFactor),
            );
            gl.blendEquationSeparatei(@intCast(i), @intFromEnum(attachment.colorBlendOp), @intFromEnum(attachment.alphaBlendOp));
        } else {
            gl.blendFuncSeparatei(@intCast(i), gl.SRC_COLOR, gl.ZERO, gl.SRC_ALPHA, gl.ZERO);
            gl.blendEquationSeparatei(@intCast(i), gl.FUNC_ADD, gl.FUNC_ADD);
        }
        const r: gl.GLboolean = if (attachment.colorWriteMask.red) gl.TRUE else gl.FALSE;
        const g: gl.GLboolean = if (attachment.colorWriteMask.green) gl.TRUE else gl.FALSE;
        const b: gl.GLboolean = if (attachment.colorWriteMask.blue) gl.TRUE else gl.FALSE;
        const a: gl.GLboolean = if (attachment.colorWriteMask.alpha) gl.TRUE else gl.FALSE;
        gl.colorMaski(@intCast(i), r, g, b, a);
    }
}
