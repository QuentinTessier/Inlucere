const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("common.zig");

const CompareOp = common.CompareOp;

pub const PipelineDepthState = @This();

depthTestEnable: bool = false,
depthWriteEnable: bool = false,
depthCompareOp: CompareOp = .less,

pub fn default() PipelineDepthState {
    return .{
        .depthTestEnable = false,
        .depthWriteEnable = false,
        .depthCompareOp = .less,
    };
}

pub fn update(self: PipelineDepthState, other: PipelineDepthState) void {
    if (self.depthTestEnable != other.depthTestEnable) {
        common.enableOrDisable(gl.DEPTH_TEST, self.depthTestEnable);
    }

    if (self.depthWriteEnable != other.depthWriteEnable) {
        gl.depthMask(if (self.depthWriteEnable) gl.TRUE else gl.FALSE);
    }

    if (self.depthCompareOp != other.depthCompareOp) {
        gl.depthFunc(@intFromEnum(self.depthCompareOp));
    }
}

pub fn force(self: PipelineDepthState) void {
    common.enableOrDisable(gl.DEPTH_TEST, self.depthTestEnable);
    gl.depthMask(if (self.depthWriteEnable) gl.TRUE else gl.FALSE);
    gl.depthFunc(@intFromEnum(self.depthCompareOp));
}
