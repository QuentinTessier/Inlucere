const std = @import("std");
const gl = @import("../gl4_6.zig");

const DeviceLogger = @import("../Device.zig").DeviceLogger;

const PipelineVertexInputState = @import("../Pipeline/State/VertexInput.zig");

pub const VertexArrayObject = @This();

handle: u32,
vertexInputState: PipelineVertexInputState,

pub fn init(self: *VertexArrayObject, vertexInputState: *const PipelineVertexInputState) void {
    gl.createVertexArrays(1, @ptrCast(&self.handle));

    var offset: usize = 0;
    for (vertexInputState.vertexAttributeDescription) |input| {
        DeviceLogger.info("VertexArrayObject({}) : layout(location = {}) {s}", .{ self.handle, input.location, @tagName(input.inputType) });
        gl.enableVertexArrayAttrib(self.handle, input.location);
        gl.vertexArrayAttribBinding(self.handle, input.location, input.binding);
        gl.vertexArrayAttribFormat(
            self.handle,
            input.location,
            @intCast(input.inputType.getSize()),
            input.inputType.getGLType(),
            gl.FALSE,
            @intCast(offset),
        );
        offset += input.inputType.getByteSize();
    }

    self.vertexInputState = vertexInputState.*;
}

pub inline fn deinit(self: VertexArrayObject) void {
    gl.deleteVertexArrays(1, @ptrCast(&self.handle));
}
