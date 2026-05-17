const std = @import("std");
const Device = @import("../device.zig");

pub const RingBuffer = @This();

const Allocation = @import("gpu_allocator.zig").Allocation;

const PendingFree = struct {
    offset: u32,
    size: u32,
    padded_size: u32,
    frame: u32,
};

device: *Device,
buffer: Device.BufferHandle,
size: u32,
head: u32,
used: u32,

pub const RingBufferDesc = struct {
    size: usize,
    usage: Device.Buffer.BufferUsage = .storage,
    host_coherent: bool = false,
    debug_name: ?[]const u8 = null,
};

pub fn init(self: *RingBuffer, device: *Device, desc: *const RingBufferDesc) !void {
    self.buffer = device.create_buffer(&.{
        .size = desc.size,
        .usage = desc.usage,
        .memory = if (desc.host_coherent) .host_coherent else .device_local,
        .debug_name = desc.debug_name,
    });

    self.device = device;
    self.size = @intCast(desc.size);
    self.head = 0;
    self.used = 0;
}

pub fn deinit(self: *RingBuffer) void {
    self.device.destroy_buffer(self.buffer);
}

pub fn retire(self: *RingBuffer, size: u32) void {
    std.debug.assert(size <= self.used);
    self.used -= size;
}

pub fn alloc(self: *RingBuffer, size: u32) !Allocation {
    const aligned_size = std.mem.alignForward(u32, size, 16);
    const offset, const padded_size = self.find_offset(aligned_size) orelse return error.out_of_memory;

    self.used += padded_size;
    self.head = (offset + aligned_size) % self.size;

    return .{
        .buffer = self.buffer,
        .offset = offset,
        .size = aligned_size,
    };
}

fn find_offset(self: *RingBuffer, aligned_size: u32) ?struct { u32, u32 } {
    if (aligned_size > self.size - self.used) return null;

    const tail = (self.head + self.used) % self.size;

    if (self.head >= tail) {
        const contiguous = self.size - self.head;
        if (aligned_size <= contiguous) return .{ self.head, aligned_size };
        if (aligned_size <= tail) return .{ 0, aligned_size + contiguous };
        return null;
    } else {
        if (aligned_size <= tail - self.head) return .{ self.head, aligned_size };
        return null;
    }
}
