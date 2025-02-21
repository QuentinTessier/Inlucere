const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("./common.zig");

pub const PipelineRasterizationState = @This();

pub const PolygonMode = enum(u32) {
    fill = gl.FILL,
    line = gl.LINE,
    point = gl.POINT,
};

pub const CullMode = enum(u32) {
    back = gl.BACK,
    front = gl.FRONT,
};

pub const FrontFace = enum(u32) {
    clockWise = gl.CW,
    counterClockWise = gl.CCW,
};

depthClampEnable: bool,
frontPolygonMode: PolygonMode,
backPolygonMode: PolygonMode,
cullMode: ?CullMode,
frontFace: FrontFace,
depthBiasEnable: bool,
depthBiasConstantFactor: f32,
depthBiasSlopeFactor: f32,
lineWidth: f32,
pointWidth: f32,

pub fn default() PipelineRasterizationState {
    return .{
        .depthClampEnable = false,
        .frontPolygonMode = .fill,
        .backPolygonMode = .fill,
        .cullMode = .back,
        .frontFace = .counterClockWise,
        .depthBiasEnable = false,
        .depthBiasConstantFactor = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
        .pointWidth = 1.0,
    };
}

pub fn update(self: PipelineRasterizationState, other: PipelineRasterizationState) void {
    if (self.depthClampEnable != other.depthClampEnable) {
        common.enableOrDisable(gl.DEPTH_CLAMP, self.depthClampEnable);
    }

    if (self.frontPolygonMode != other.frontPolygonMode or self.backPolygonMode != self.backPolygonMode) {
        if (self.frontPolygonMode == self.backPolygonMode) {
            gl.polygonMode(gl.FRONT_AND_BACK, @intFromEnum(self.frontPolygonMode));
        } else {
            gl.polygonMode(gl.FRONT, @intFromEnum(self.frontPolygonMode));
            gl.polygonMode(gl.BACK, @intFromEnum(self.backPolygonMode));
        }
    }

    if (self.cullMode != other.cullMode) {
        common.enableOrDisable(gl.CULL_FACE, self.cullMode != null);
        if (self.cullMode != null) {
            gl.cullFace(@intFromEnum(self.cullMode.?));
        }
    }

    if (self.frontFace != other.frontFace) {
        gl.frontFace(@intFromEnum(self.frontFace));
    }

    if (self.depthBiasEnable != other.depthBiasEnable) {
        common.enableOrDisable(gl.POLYGON_OFFSET_FILL, self.depthBiasEnable);
        common.enableOrDisable(gl.POLYGON_OFFSET_LINE, self.depthBiasEnable);
        common.enableOrDisable(gl.POLYGON_OFFSET_POINT, self.depthBiasEnable);
    }

    if (self.depthBiasConstantFactor != other.depthBiasConstantFactor or self.depthBiasSlopeFactor != other.depthBiasSlopeFactor) {
        gl.polygonOffset(self.depthBiasSlopeFactor, self.depthBiasConstantFactor);
    }

    if (self.lineWidth != other.lineWidth) {
        gl.lineWidth(self.lineWidth);
    }

    if (self.pointWidth != other.pointWidth) {
        gl.pointSize(self.pointWidth);
    }
}

pub fn force(self: PipelineRasterizationState) void {
    common.enableOrDisable(gl.DEPTH_CLAMP, self.depthClampEnable);

    if (self.frontPolygonMode == self.backPolygonMode) {
        gl.polygonMode(gl.FRONT_AND_BACK, @intFromEnum(self.frontPolygonMode));
    } else {
        gl.polygonMode(gl.FRONT, @intFromEnum(self.frontPolygonMode));
        gl.polygonMode(gl.BACK, @intFromEnum(self.backPolygonMode));
    }

    common.enableOrDisable(gl.CULL_FACE, self.cullMode != null);
    if (self.cullMode != null) {
        gl.cullFace(@intFromEnum(self.cullMode.?));
    }

    gl.frontFace(@intFromEnum(self.frontFace));

    common.enableOrDisable(gl.POLYGON_OFFSET_FILL, self.depthBiasEnable);
    common.enableOrDisable(gl.POLYGON_OFFSET_LINE, self.depthBiasEnable);
    common.enableOrDisable(gl.POLYGON_OFFSET_POINT, self.depthBiasEnable);

    gl.polygonOffset(self.depthBiasSlopeFactor, self.depthBiasConstantFactor);

    gl.lineWidth(self.lineWidth);

    gl.pointSize(self.pointWidth);
}
