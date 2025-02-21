const std = @import("std");
const gl = @import("../gl4_6.zig");
const Buffer = @import("./Buffer.zig");

const DeviceLogger = @import("../Device.zig").DeviceLogger;

pub const MappedBuffer = @This();

pub const Flags = packed struct(u8) {
    read: bool = false,
    write: bool = false,
    explicitFlush: bool = false,
    unsynchronized: bool = false,
    __unused: u4 = 0,

    pub fn toNamedBufferStorage(self: Flags) u32 {
        var flagsGL: u32 = gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT | gl.DYNAMIC_STORAGE_BIT;

        if (self.read) {
            flagsGL |= gl.MAP_READ_BIT;
        }
        if (self.write) {
            flagsGL |= gl.MAP_WRITE_BIT;
        }
        if (self.explicitFlush) {
            flagsGL |= gl.MAP_FLUSH_EXPLICIT_BIT;
        }
        return flagsGL;
    }

    pub fn toMapNamedBuffer(self: Flags) u32 {
        var flagsGL: u32 = 0;

        if (self.read and self.write) {
            flagsGL = gl.READ_WRITE;
        } else if (self.read) {
            flagsGL = gl.READ_ONLY;
        } else {
            flagsGL = gl.WRITE_ONLY;
        }
        if (self.unsynchronized) {
            flagsGL |= gl.MAP_UNSYNCHRONIZED_BIT;
        }
        return flagsGL;
    }
};

handle: u32,
size: usize,
stride: usize = 0,
flags: Flags,
ptr: [*]u8,

pub fn init(name: ?[]const u8, comptime T: type, data: []const T, flags: Flags) Buffer.Error!MappedBuffer {
    var buffer: MappedBuffer = undefined;
    buffer.flags = flags;
    buffer.size = data.len * @sizeOf(T);
    buffer.stride = @sizeOf(T);

    gl.createBuffers(1, @ptrCast(&buffer.handle));
    gl.namedBufferStorage(buffer.handle, @intCast(data.len * @sizeOf(T)), data.ptr, flags.toNamedBufferStorage());

    const ptr = gl.mapNamedBuffer(buffer.handle, flags.toMapNamedBuffer());
    if (ptr == null) {
        gl.deleteBuffers(1, @ptrCast(&buffer.handle));
        return Buffer.Error.FailedToMap;
    }

    buffer.ptr = @ptrCast(ptr.?);
    if (name) |label| {
        gl.objectLabel(gl.BUFFER, buffer.handle, @intCast(label.len), label.ptr);
    }

    DeviceLogger.info("Successfuly created MappedBuffer {?s}:(size: {}, stride: {})", .{ name, data.len, @sizeOf(T) });
    return buffer;
}

pub fn initEmpty(name: ?[]const u8, comptime T: type, count: usize, flags: Flags) !MappedBuffer {
    var buffer: MappedBuffer = undefined;
    buffer.flags = flags;
    buffer.size = count * @sizeOf(T);
    buffer.stride = @sizeOf(T);

    gl.createBuffers(1, @ptrCast(&buffer.handle));
    gl.namedBufferStorage(buffer.handle, @intCast(count * @sizeOf(T)), null, flags.toNamedBufferStorage());

    const ptr = gl.mapNamedBuffer(buffer.handle, flags.toMapNamedBuffer());
    if (ptr == null) {
        gl.deleteBuffers(1, @ptrCast(&buffer.handle));
        return error.FailedToMap;
    }

    buffer.ptr = @ptrCast(ptr.?);
    if (name) |label| {
        gl.objectLabel(gl.BUFFER, buffer.handle, @intCast(label.len), label.ptr);
    }

    DeviceLogger.info("Successfuly created MappedBuffer {?s}:(size: {}, stride: {})", .{ name, count * @sizeOf(T), @sizeOf(T) });
    return buffer;
}

pub fn deinit(self: MappedBuffer) void {
    _ = gl.unmapNamedBuffer(self.handle);
    gl.deleteBuffers(1, @ptrCast(&self.handle));
}

pub fn cast(self: MappedBuffer, comptime T: type) []T {
    const count = @divExact(self.size, @sizeOf(T));

    const ptr: [*]T = @ptrCast(@alignCast(self.ptr));
    return ptr[0..count];
}

pub fn toBuffer(self: MappedBuffer) Buffer {
    return .{
        .handle = self.handle,
        .size = self.size,
        .stride = self.stride,
    };
}

pub fn update(self: *MappedBuffer, data: []const u8, offset: usize) void {
    std.debug.assert(offset + data.len <= self.size);

    gl.namedBufferSubData(self.handle, @intCast(offset), @intCast(data.len), data.ptr);
}
