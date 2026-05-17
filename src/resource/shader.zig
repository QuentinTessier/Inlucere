const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const Shader = @This();

pub const Stage = enum(u32) {
    vertex = gl.VERTEX_SHADER,
    fragment = gl.FRAGMENT_SHADER,
    tess_control = gl.TESS_CONTROL_SHADER,
    tess_evaluation = gl.TESS_EVALUATION_SHADER,

    compute = gl.COMPUTE_SHADER,
};

handle: u32,
stage: Stage,

pub const ShaderDesc = struct {
    source: []const u8,
    stage: Stage,
    debug_name: ?[]const u8,
};

pub fn init(self: *Shader, desc: *const ShaderDesc) !void {
    const stage = desc.stage;
    const source = desc.source;
    self.handle = gl.createShader(@intFromEnum(stage));

    var length: i32 = @intCast(source.len);
    gl.shaderSource(self.handle, 1, @ptrCast(&source.ptr), &length);
    gl.compileShader(self.handle);

    var success: i32 = 0;
    gl.getShaderiv(self.handle, gl.COMPILE_STATUS, @ptrCast(&success));
    if (success != gl.TRUE) {
        var buffer: [1024]u8 = undefined;
        var l: i32 = 0;
        gl.getShaderInfoLog(self.handle, 1024, &l, (&buffer).ptr);
        std.log.err("{s}", .{buffer[0..@intCast(l)]});
        return error.failed_to_compile_shader;
    }

    if (desc.debug_name) |label| {
        gl.objectLabel(gl.SHADER, self.handle, @intCast(label.len), label.ptr);
    }
}

pub fn deinit(self: *Shader, _: std.mem.Allocator) void {
    gl.deleteShader(self.handle);
}
