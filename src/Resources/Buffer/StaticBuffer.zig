const std = @import("std");
const gl = @import("../../gl4_6.zig");
const Buffer = @import("Buffer.zig");

const DeviceLogger = @import("../../Device.zig").DeviceLogger;

pub const StaticBuffer = @This();

handle: u32,
size: usize,
stride: usize = 0,

pub fn init(name: ?[]const u8, data: []const u8, stride: usize) StaticBuffer {
    var buffer: StaticBuffer = std.mem.zeroInit(StaticBuffer, .{
        .size = data.len,
        .stride = stride,
    });

    gl.createBuffers(1, @ptrCast(&buffer.handle));
    gl.namedBufferStorage(buffer.handle, @intCast(data.len), data.ptr, 0);

    if (name) |label| {
        gl.objectLabel(gl.BUFFER, buffer.handle, @intCast(label.len), label.ptr);
    }

    DeviceLogger.info("Successfuly created StaticBuffer {?s}:(size: {}, stride: {})", .{ name, data.len, stride });
    return buffer;
}

pub fn deinit(self: StaticBuffer) void {
    gl.deleteBuffers(1, @ptrCast(&self.handle));
}

pub fn toBuffer(self: StaticBuffer) Buffer {
    return .{
        .handle = self.handle,
        .size = self.size,
        .stride = self.stride,
    };
}
