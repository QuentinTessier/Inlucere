const std = @import("std");
const gl = @import("gl4_6.zig");

pub const StagingBuffers = @This();

const StagingBuffer = struct {
    handle: u32,
    mapped_memory: []u8,
    fence: ?gl.GLsync = null,
};

pub const PendingWrite = struct {
    src_offset: u32,
    dst_buffer: u32,
    dst_offset: u32,
    len: u32,
};

io: std.Io,
buffers: std.array_list.Aligned(StagingBuffer, null),
pending_async_writes: std.array_list.Aligned(PendingWrite, null),
async_group: std.Io.Group,
size: u32,
offset: u32,
current_frame: u32,

pub const Options = struct {
    size: usize = 64 * 1024 * 1024,
    max_async_transfer: usize = 8,
    count: usize = 2,
    defines_debug_names: bool = false,
};

pub fn init(self: *StagingBuffers, io: std.Io, allocator: std.mem.Allocator, options: *const Options) !void {
    self.io = io;
    self.buffers = try .initCapacity(allocator, options.count);
    self.pending_async_writes = try .initCapacity(allocator, options.max_async_transfer);
    errdefer {
        for (self.buffers.items) |buffer| {
            gl.deleteBuffers(1, @ptrCast(&buffer.handle));
            self.buffers.deinit(allocator);
        }
    }
    for (0..options.count) |i| {
        const ptr = self.buffers.addOneAssumeCapacity();
        ptr.handle = 0;
        ptr.fence = null;

        const flags: u32 = gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_COHERENT_BIT;
        gl.createBuffers(1, @ptrCast(&ptr.handle));
        gl.namedBufferStorage(
            ptr.handle,
            @intCast(options.size),
            null,
            flags,
        );

        const mapped_opaque_ptr = gl.mapNamedBufferRange(
            ptr.handle,
            0,
            @intCast(options.size),
            flags,
        ) orelse return error.failed_to_map;
        ptr.mapped_memory = @as([*]u8, @ptrCast(mapped_opaque_ptr))[0..options.size];

        if (options.defines_debug_names) {
            var name_buffer: [32]u8 = [1]u8{0} ** 32;
            const result = std.fmt.bufPrint(&name_buffer, "staging_{}", .{i}) catch &.{};

            gl.objectLabel(gl.BUFFER, ptr.handle, @intCast(result.len), result.ptr);
        }
    }
}

pub fn deinit(self: *StagingBuffers, allocator: std.mem.Allocator) void {
    for (self.buffers.items) |buffer| {
        gl.deleteBuffers(1, @ptrCast(&buffer.handle));
        if (buffer.fence) |fence| {
            gl.deleteSync(fence);
        }
    }
    self.buffers.deinit(allocator);
    self.async_group.await(self.io);
    self.pending_async_writes.deinit(allocator);
}

pub fn begin_staging(self: *StagingBuffers) void {
    self.current_frame = @mod(self.current_frame + 1, @as(u32, @intCast(self.buffers.items.len)));
    self.offset = 0;

    if (self.buffers.items[@intCast(self.current_frame)].fence) |fence| {
        _ = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 10000000);
        gl.deleteSync(fence);
        self.buffers.items[@intCast(self.current_frame)].fence = null;
    }
}

pub fn end_staging(self: *StagingBuffers) void {
    for (self.pending_async_writes.items) |copy| {
        gl.copyNamedBufferSubData(
            self.buffers.items[@intCast(self.current_frame)].handle,
            copy.dst_buffer,
            @intCast(copy.src_offset),
            @intCast(copy.dst_offset),
            @intCast(copy.len),
        );
    }
    self.pending_async_writes.clearRetainingCapacity();
    self.buffers.items[@intCast(self.current_frame)].fence = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
}

pub fn upload(self: *StagingBuffers, dst_buffer: u32, dst_offset: usize, data: []const u8) bool {
    if (self.offset + @as(u32, @intCast(data.len)) > self.size) {
        return false;
    }

    const slice = self.buffers.items[@intCast(self.current_frame)].mapped_memory[@intCast(self.offset) .. @as(usize, @intCast(self.offset)) + data.len];
    @memcpy(slice, data);

    gl.copyNamedBufferSubData(
        self.buffers.items[@intCast(self.current_frame)].handle,
        dst_buffer,
        @intCast(self.offset),
        @intCast(dst_offset),
        @intCast(data.len),
    );

    self.offset += @intCast(data.len);
    return true;
}

pub fn async_upload(self: *StagingBuffers, dst_buffer: u32, dst_offset: usize, data: []const u8) bool {
    if (self.offset + @as(u32, @intCast(data.len)) > self.size) {
        return false;
    }

    const slot = self.pending_async_writes.addOneBounded() catch return false;
    slot.src_offset = self.offset;
    slot.dst_buffer = dst_buffer;
    slot.dst_offset = dst_offset;
    slot.len = @intCast(data.len);

    const slice = self.buffers.items[@intCast(self.current_frame)].mapped_memory[@intCast(self.offset) .. @as(usize, @intCast(self.offset)) + data.len];
    self.offset += @intCast(data.len);

    try self.async_group.concurrent(self.io, struct {
        fn run(dst: []u8, src: []const u8) void {
            @memcpy(dst, src);
        }
    }.run, .{ slice, data });
    return true;
}

pub fn wait_all(self: *StagingBuffers) !void {
    return self.async_group.await(self.io);
}
