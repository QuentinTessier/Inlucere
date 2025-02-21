const std = @import("std");
const gl = @import("../gl4_6.zig");
const Program = @import("./Program.zig");

pub const ComputePipeline = @This();

handle: u32,

pub fn init(self: *ComputePipeline, shader: []const u8) !void {
    self.handle = gl.createProgram();

    const s = gl.createShader(gl.COMPUTE_SHADER);
    try Program.compileShader(s, shader);
    defer gl.deleteShader(s);

    gl.attachShader(self.handle, s);
    gl.linkProgram(self.handle);

    {
        var success: i32 = 0;
        gl.getProgramiv(self.handle, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            var size: isize = 0;
            var buffer: [1024]u8 = undefined;
            gl.getProgramInfoLog(self.handle, 1024, @ptrCast(&size), (&buffer).ptr);
            std.log.err("Failed to link program: {s}", .{buffer[0..@intCast(size)]});
            return error.ProgramLinkingFailed;
        }
    }
}

pub fn deinit(self: *ComputePipeline) void {
    gl.deleteProgram(self.handle);
}
