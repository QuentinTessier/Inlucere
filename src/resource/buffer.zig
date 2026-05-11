const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const BufferUsage = enum(u3) {
    vertex,
    index,
    uniform,
    storage,
    indirect,
};

pub const MemoryType = enum(u2) {
    device_local,
    host_visible,
    host_coherent,
};

pub const AccessUsage = enum(u2) {
    read_only,
    write_only,
    read_write,
};

const Flags = packed struct(u8) {
    usage: BufferUsage,
    memory: MemoryType,
    access: AccessUsage,
    padding: u1 = 0,
};

pub const BufferDesc = struct {
    size: usize,
    usage: BufferUsage,
    memory: MemoryType,
    access: AccessUsage = .read_write,
    debug_name: ?[]const u8 = null,

    pub fn storage_flags(self: *const BufferDesc) u32 {
        return switch (self.memory) {
            .device_local => 0,
            .host_visible => switch (self.access) {
                .read_only => gl.MAP_READ_BIT | gl.MAP_PERSISTENT_BIT,
                .write_only => gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT,
                .read_write => gl.MAP_READ_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT,
            },
            .host_coherent => switch (self.access) {
                .read_only => gl.MAP_READ_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
                .write_only => gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
                .read_write => gl.MAP_READ_BIT | gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT,
            },
        };
    }

    pub fn mapping_flags(self: *const BufferDesc) u32 {
        return self.storage_flags();
    }
};

pub const Buffer = @This();

handle: u32,
size: usize,
ptr: ?[*]u8 = null,
flags: Flags,

pub fn init(self: *Buffer, desc: *const BufferDesc) !void {
    gl.createBuffers(1, &self.handle);

    self.size = desc.size;
    self.flags.usage = desc.usage;
    self.flags.memory = desc.memory;
    self.flags.access = desc.access;

    gl.namedBufferStorage(
        self.handle,
        @intCast(desc.size),
        null,
        desc.storage_flags(),
    );

    if (desc.memory != .device_local) {
        const ptr = gl.mapNamedBufferRange(
            self.handle,
            0,
            @intCast(desc.size),
            desc.mapping_flags(),
        );

        if (ptr == null) {
            gl.deleteBuffers(1, @ptrCast(&self.handle));
            return error.failed_to_map_buffer;
        }

        self.ptr = @ptrCast(ptr);

        if (desc.debug_name) |label| {
            gl.objectLabel(gl.BUFFER, self.handle, @intCast(label.len), label.ptr);
        }
    }
}

pub fn deinit(self: *Buffer) void {
    if (self.ptr != null) {
        _ = gl.unmapNamedBuffer(self.handle);
    }
    gl.deleteBuffers(1, @ptrCast(&self.handle));
}

// Alignment can be record into type T, such as '[3]f32 align(16)'
pub fn cast(self: *const Buffer, comptime T: type) ![]T {
    std.debug.assert(self.flags.access != .write_only);
    if (self.ptr) |ptr| {
        const count = @divExact(self.size, @sizeOf(T));
        const casted: [*]T = @ptrCast(@alignCast(ptr));

        return casted[0..count];
    } else return error.not_mapped_buffer;
}
