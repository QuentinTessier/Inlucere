const std = @import("std");
const gl = @import("../gl4_6.zig");
const Device = @import("../device.zig");

pub const Buffered = @This();

const Allocation = @import("gpu_allocator.zig").Allocation;

device: *Device,
buffer: Device.BufferHandle,

pool_size: u32,

frame_count: u32,
current_frame: u32,
syncs: std.array_list.Aligned(?gl.GLsync, null),

pub const BufferedDesc = struct {
    bytes_per_pool: u32,
    pool_count: u32,
    usage: Device.Buffer.BufferUsage = .storage,
    host_coherent: bool = false,
    debug_name: ?[]const u8 = null,
};

pub fn init(self: *Buffered, device: *Device, desc: *const BufferedDesc) !void {
    self.buffer = device.create_buffer(&.{
        .size = @intCast(desc.bytes_per_pool * desc.pool_count),
        .usage = desc.usage,
        .memory = if (desc.host_coherent) .host_coherent else .device_local,
        .debug_name = desc.debug_name,
    });

    self.frame_count = desc.pool_count;
    self.current_frame = 0;
    self.pool_size = desc.bytes_per_pool;
    self.syncs = try .initCapacity(device.allocator, @intCast(desc.pool_count));
    self.syncs.appendNTimesAssumeCapacity(null, @intCast(desc.pool_count));
}

pub fn deinit(self: *Buffered) void {
    for (self.syncs.items) |sync| {
        if (sync) |s| gl.deleteSync(s);
    }

    self.syncs.deinit(self.device.allocator);
    self.device.destroy_buffer(self.buffer);
}

fn wait(fence: gl.GLsync, timeout: ?u64) bool {
    if (timeout) |t| {
        const res = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, t);
        return res == gl.ALREADY_SIGNALED or res == gl.CONDITION_SATISFIED;
    } else while (true) {
        const r = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 1000000);
        if (r == gl.ALREADY_SIGNALED or r == gl.CONDITION_SATISFIED) break;
    }
    return true;
}

fn frame_range(self: *const Buffered, frame: u32) [2]u32 {
    const offset = self.pool_size * frame;
    return .{ offset, self.pool_size };
}

pub fn acquire(self: *Buffered, timeout: ?u64) ?Allocation {
    const next_frame = @mod(self.current_frame + 1, self.frame_count);

    if (self.syncs.items[@intCast(self.current_frame)]) |fence| {
        if (!wait(fence, timeout)) {
            return null;
        }
        gl.deleteSync(fence);
        self.syncs.items[@intCast(self.current_frame)] = null;
    }

    self.current_frame = next_frame;
    const range = self.frame_range(self.current_frame);
    return .{
        .handle = self.buffer,
        .offset = range[0],
        .size = range[1],
    };
}

pub fn release(self: *Buffered) void {
    self.syncs.items[@intCast(self.current_frame)] = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
}

pub fn is_next_pool_ready(self: *const Buffered) bool {
    const idx = @mod(self.current_frame + 1, self.frame_count);
    if (self.syncs.items[@intCast(idx)]) |fence| {
        const res = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 0);
        return res == gl.ALREADY_SIGNALED or res == gl.CONDITION_SATISFIED;
    } else {
        return true;
    }
}
