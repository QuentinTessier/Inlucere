const std = @import("std");
const gl = @import("../gl4_6.zig");

const ShaderHandle = @import("../device.zig").ShaderHandle;
const Device = @import("../device.zig");

pub const ComputePipeline = @This();

handle: u32,
workgroup_size: [3]u32,

pub const ComputePipelineDesc = struct {
    shader: ShaderHandle,
    workgroup_size: [3]u32,
    debug_name: ?[]const u8 = null,
};

pub fn init(self: *ComputePipeline, device: *Device, desc: *const ComputePipelineDesc) !void {
    self.handle = gl.createProgram();
    self.workgroup_size = desc.workgroup_size;

    const compute_shader = device.shaders.get(desc.shader.to_untyped()) orelse return error.missing_shader;

    gl.attachShader(self.handle, compute_shader.handle);
    gl.linkProgram(self.handle);
    {
        var success: i32 = 0;
        gl.getProgramiv(self.handle, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            var size: isize = 0;
            var buffer: [1024]u8 = undefined;
            gl.getProgramInfoLog(self.handle, 1024, @ptrCast(&size), (&buffer).ptr);
            std.log.err("Failed to link program: {s}", .{buffer[0..@intCast(size)]});
            return error.program_linking_failed;
        }
    }

    gl.detachShader(self.handle, compute_shader.handle);

    // var local_size: [3]i32 = undefined;
    // gl.getProgramiv(self.handle, gl.MAX_COMPUTE_WORK_GROUP_SIZE, &local_size);
    // std.log.info("{} {} {}", .{ local_size[0], local_size[1], local_size[2] });
    // self.workgroup_size = .{
    //     @intCast(local_size[0]),
    //     @intCast(local_size[1]),
    //     @intCast(local_size[2]),
    // };

    if (desc.debug_name) |label| {
        gl.objectLabel(gl.PROGRAM, self.handle, @intCast(label.len), label.ptr);
    }
}

pub fn deinit(self: *ComputePipeline, _: std.mem.Allocator) void {
    gl.deleteProgram(self.handle);
}
