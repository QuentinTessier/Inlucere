const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("./common.zig");

pub const PrimitiveTopology = enum(u32) {
    triangle = gl.TRIANGLES,
    triangle_strip = gl.TRIANGLE_STRIP,
};

pub const PipelineInputAssemblyState = @This();

topology: PrimitiveTopology,
enableRestart: bool,
primitiveRestartIndex: u32,

pub fn default() PipelineInputAssemblyState {
    return .{
        .topology = .triangle,
        .enableRestart = false,
        .primitiveRestartIndex = 0,
    };
}

pub fn eql(self: PipelineInputAssemblyState, other: PipelineInputAssemblyState) bool {
    return self.topology == other.topology and self.enableRestart == other.enableRestart;
}

pub fn update(self: PipelineInputAssemblyState, other: PipelineInputAssemblyState) void {
    if (self.enableRestart != other.enableRestart) {
        common.enableOrDisable(gl.PRIMITIVE_RESTART, self.enableRestart);
    }

    if (self.enableRestart and (!other.enableRestart or (self.primitiveRestartIndex != other.primitiveRestartIndex))) {
        gl.primitiveRestartIndex(self.primitiveRestartIndex);
    }
}

pub fn force(self: PipelineInputAssemblyState) void {
    common.enableOrDisable(gl.PRIMITIVE_RESTART, self.enableRestart);
    gl.primitiveRestartIndex(self.primitiveRestartIndex);
}
