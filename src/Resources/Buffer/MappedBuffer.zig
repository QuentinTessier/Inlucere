const std = @import("std");
const gl = @import("../../gl4_6.zig");
const Buffer = @import("../Buffer.zig");

const DeviceLogger = @import("../../Device.zig").DeviceLogger;

pub const MappedBuffer = @This();

pub const Kind = enum {
    Coherent,
    ExplicitFlushed,

    pub fn getFlags(self: Kind) u32 {
        return switch (self) {
            .Coherent => gl.MAP_COHERENT_BIT,
            .ExplicitFlushed => gl.MAP_FLUSH_EXPLICIT_BIT,
        };
    }

    pub fn getMapFlags(self: Kind, flags: Flags) u32 {
        return switch (self) {
            .Coherent => gl.MAP_COHERENT_BIT | flags.getFlags(),
            .ExplicitFlushed => blk: {
                const f = flags.getFlags();
                break :blk gl.MAP_FLUSH_EXPLICIT_BIT | if (flags.read) f & ~@as(u32, gl.MAP_READ_BIT) else f;
            },
        };
    }
};

pub const Flags = packed struct {
    read: bool = false,
    write: bool = true,
    persistent: bool = true,
    unsynchronized: bool = false,

    pub fn getFlags(self: Flags) u32 {
        std.debug.assert(!(self.read and self.unsynchronized)); // We can't read and be unsyn at the same time

        var flags: u32 = 0;
        if (self.read) {
            flags |= gl.MAP_READ_BIT;
        }
        if (self.write) {
            flags |= gl.MAP_WRITE_BIT;
        }
        if (self.persistent) {
            flags |= gl.MAP_PERSISTENT_BIT;
        }
        if (self.unsynchronized) {
            flags |= gl.MAP_UNSYNCHRONIZED_BIT;
        }

        return flags;
    }
};

kind: Kind,
handle: u32,
size: usize,
stride: usize = 0,
ptr: [*]u8,

pub fn init(name: ?[]const u8, comptime T: type, data: []const T, kind: Kind, flags: Flags) !MappedBuffer {
    var buffer: MappedBuffer = undefined;
    buffer.kind = kind;
    buffer.size = data.len * @sizeOf(T);
    buffer.stride = @sizeOf(T);

    gl.createBuffers(1, @ptrCast(&buffer.handle));
    gl.namedBufferStorage(
        buffer.handle,
        @intCast(data.len * @sizeOf(T)),
        data.ptr,
        flags.getFlags(),
    );

    const ptr = gl.mapNamedBufferRange(
        buffer.handle,
        0,
        @intCast(buffer.size),
        kind.getMapFlags(flags),
    );
    if (ptr == null) {
        gl.deleteBuffers(1, @ptrCast(&buffer.handle));
        return error.FailedToMap;
    }

    buffer.ptr = @ptrCast(ptr.?);
    if (name) |label| {
        gl.objectLabel(gl.BUFFER, buffer.handle, @intCast(label.len), label.ptr);
    }

    DeviceLogger.info("Successfuly created MappedBuffer {?s}:(size: {}, stride: {})", .{ name, buffer.size, @sizeOf(T) });
    return buffer;
}

pub fn initEmpty(name: ?[]const u8, comptime T: type, count: usize, kind: Kind, flags: Flags) !MappedBuffer {
    var buffer: MappedBuffer = undefined;
    buffer.kind = kind;
    buffer.size = count * @sizeOf(T);
    buffer.stride = @sizeOf(T);

    gl.createBuffers(1, @ptrCast(&buffer.handle));
    gl.namedBufferStorage(
        buffer.handle,
        @intCast(buffer.size),
        null,
        flags.getFlags(),
    );

    const ptr = gl.mapNamedBufferRange(
        buffer.handle,
        0,
        @intCast(buffer.size),
        kind.getMapFlags(flags),
    );
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

pub fn flushRange(self: MappedBuffer, offset: u32, size: u32) void {
    std.debug.assert(self.kind == .ExplicitFlushed);
    gl.flushMappedNamedBufferRange(self.handle, offset, size);
}
