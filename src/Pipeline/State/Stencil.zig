const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("common.zig");

pub const PipelineStencilState = @This();

pub const CompareOp = common.CompareOp;

pub const StencilOp = enum(u32) {
    keep = gl.KEEP,
    zero = gl.ZERO,
    replace = gl.REPLACE,
    incr = gl.INCR,
    incrWrap = gl.INCR_WRAP,
    decr = gl.DECR,
    decrWrap = gl.DECR_WRAP,
    invert = gl.INVERT,
};

pub const StencilOperationState = struct {
    stencilFail: StencilOp = .keep,
    stencilPass: StencilOp = .keep,
    depthFail: StencilOp = .keep,

    compareOp: CompareOp = .always,

    compareMask: u32 = 0x0,
    writeMask: u32 = 0x0,
    reference: i32 = 0x0,

    pub fn eq(self: StencilOperationState, other: StencilOperationState) bool {
        const b1 = std.mem.asBytes(&self);
        const b2 = std.mem.asBytes(&other);

        return std.mem.eql(u8, b1, b2);
    }
};

stencilTestEnable: bool,

front: StencilOperationState,
back: StencilOperationState,

pub fn default() PipelineStencilState {
    return .{
        .stencilTestEnable = false,
        .front = .{},
        .back = .{},
    };
}

pub fn update(self: PipelineStencilState, other: PipelineStencilState) void {
    if (self.stencilTestEnable != other.stencilTestEnable) {
        common.enableOrDisable(gl.STENCIL_TEST, self.stencilTestEnable);

        gl.stencilOpSeparate(
            gl.FRONT,
            @intFromEnum(self.front.stencilFail),
            @intFromEnum(self.front.depthFail),
            @intFromEnum(self.front.stencilPass),
        );
        gl.stencilFuncSeparate(
            gl.FRONT,
            @intFromEnum(self.front.compareOp),
            self.front.reference,
            self.front.compareMask,
        );
        gl.stencilMaskSeparate(gl.FRONT, self.front.writeMask);

        gl.stencilOpSeparate(
            gl.BACK,
            @intFromEnum(self.back.stencilFail),
            @intFromEnum(self.back.depthFail),
            @intFromEnum(self.back.stencilPass),
        );
        gl.stencilFuncSeparate(
            gl.BACK,
            @intFromEnum(self.back.compareOp),
            self.back.reference,
            self.back.compareMask,
        );
        gl.stencilMaskSeparate(gl.BACK, self.back.writeMask);
    }
}

pub fn force(self: PipelineStencilState) void {
    common.enableOrDisable(gl.STENCIL_TEST, self.stencilTestEnable);

    gl.stencilOpSeparate(
        gl.FRONT,
        @intFromEnum(self.front.stencilFail),
        @intFromEnum(self.front.depthFail),
        @intFromEnum(self.front.stencilPass),
    );
    gl.stencilFuncSeparate(
        gl.FRONT,
        @intFromEnum(self.front.compareOp),
        self.front.reference,
        self.front.compareMask,
    );
    gl.stencilMaskSeparate(gl.FRONT, self.front.writeMask);

    gl.stencilOpSeparate(
        gl.BACK,
        @intFromEnum(self.back.stencilFail),
        @intFromEnum(self.back.depthFail),
        @intFromEnum(self.back.stencilPass),
    );
    gl.stencilFuncSeparate(
        gl.BACK,
        @intFromEnum(self.back.compareOp),
        self.back.reference,
        self.back.compareMask,
    );
    gl.stencilMaskSeparate(gl.BACK, self.back.writeMask);
}
