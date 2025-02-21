const std = @import("std");
const gl = @import("../../gl4_6.zig");
const common = @import("common.zig");

pub const PipelineVertexInputState = @This();

pub const VertexInputFormat = enum(u32) {
    i8 = gl.BYTE,
    u8 = gl.UNSIGNED_BYTE,
    i16 = gl.SHORT,
    u16 = gl.UNSIGNED_SHORT,
    i32 = gl.INT,
    u32 = gl.UNSIGNED_INT,
    fixed = gl.FIXED,
    f32 = gl.FLOAT,
    f64 = gl.DOUBLE,

    pub fn getSize(self: VertexInputFormat) u32 {
        return switch (self) {
            .i8, .u8 => 1,
            .i16, .u16 => 2,
            .i32, .u32, .f32, .fixed => 4,
            .f64 => 8,
        };
    }
};

pub const InputTypes = enum {
    // boolean
    bool,
    vec2b,
    vec3b,
    vec4b,

    // integer
    i32,
    vec2i,
    vec3i,
    vec4i,

    // unsigned integer
    u32,
    vec2u,
    vec3u,
    vec4u,

    // float
    f32,
    vec2,
    vec3,
    vec4,

    pub fn getSize(self: InputTypes) u32 {
        return switch (self) {
            .bool, .i32, .u32, .f32 => 1,
            .vec2b, .vec2i, .vec2u, .vec2 => 2,
            .vec3b, .vec3i, .vec3u, .vec3 => 3,
            .vec4b, .vec4i, .vec4u, .vec4 => 4,
        };
    }

    pub fn getGLType(self: InputTypes) u32 {
        return switch (self) {
            .bool, .vec2b, .vec3b, .vec4b => gl.BOOL,
            .i32, .vec2i, .vec3i, .vec4i => gl.INT,
            .u32, .vec2u, .vec3u, .vec4u => gl.UNSIGNED_INT,
            .f32, .vec2, .vec3, .vec4 => gl.FLOAT,
        };
    }

    pub fn getByteSize(self: InputTypes) usize {
        const bSize: usize = switch (self.getGLType()) {
            gl.BOOL => @sizeOf(bool),
            gl.INT => @sizeOf(i32),
            gl.UNSIGNED_INT => @sizeOf(u32),
            gl.FLOAT => @sizeOf(f32),
            else => unreachable,
        };
        return @as(usize, self.getSize()) * bSize;
    }
};

pub const VertexInputAttributeDescription = struct {
    location: u32,
    binding: u32,
    inputType: InputTypes,
};

vertexAttributeDescription: []const VertexInputAttributeDescription,

pub fn eql(self: *const PipelineVertexInputState, other: *const PipelineVertexInputState) bool {
    if (self.vertexAttributeDescription.len != other.vertexAttributeDescription.len) {
        std.log.info("Length doesn't match: {} {}", .{ self.vertexAttributeDescription.len, other.vertexAttributeDescription.len });
        return false;
    }

    for (self.vertexAttributeDescription) |attrib| {
        if (!other.hasAttribute(attrib)) return false;
    }
    return true;
}

pub fn hasAttribute(self: PipelineVertexInputState, attribute: VertexInputAttributeDescription) bool {
    for (self.vertexAttributeDescription) |attrib| {
        if (attrib.binding == attribute.binding and attrib.location == attribute.location and attrib.inputType == attribute.inputType) return true;
    }
    return false;
}

pub fn empty() PipelineVertexInputState {
    return .{ .vertexAttributeDescription = &.{} };
}
