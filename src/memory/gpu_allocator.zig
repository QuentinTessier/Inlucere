const std = @import("std");
const Device = @import("device.zig");

pub const GPUAllocator = @This();

device: *Device,
buffer: Device.BufferHandle,
size: u32,
used: u32,
free_blocks: std.array_list.Aligned(Block, null),

const Block = struct {
    offset: u32,
    size: u32,

    pub fn order(lhs: Block, rhs: Block) std.math.Order {
        return std.math.order(lhs.offset, rhs.offset);
    }
};

pub const Allocation = struct {
    buffer: Device.BufferHandle,
    offset: u32,
    size: u32,
};

pub const GPUAllocatorDesc = struct {
    size: u32,
    usage: Device.Buffer.BufferUsage = .storage,
    host_coherent: bool = false,
    debug_name: ?[]const u8 = null,
    default_block_count: usize = 64,
};

pub fn init(self: *GPUAllocator, device: *Device, desc: *const GPUAllocatorDesc) !void {
    self.buffer = device.create_buffer(&.{
        .size = desc.size,
        .usage = desc.usage,
        .memory = if (desc.host_coherent) .host_coherent else .device_local,
        .debug_name = desc.debug_name,
    });

    self.size = desc.size;
    self.used = 0;
    self.free_blocks = try .initCapacity(device.allocator, desc.default_block_count);
    self.free_blocks.appendAssumeCapacity(.{ .offset = 0, .size = desc.size });
    self.device = device;
}

pub fn deinit(self: *GPUAllocator) void {
    self.device.destroy_buffer(self.buffer);
    self.free_blocks.deinit(self.device.allocator);
}

fn alloc_from_free_list(self: *GPUAllocator, aligned_size: u32) ?u32 {
    for (self.free_blocks.items, 0..) |*b, i| {
        if (b.size >= aligned_size) {
            const offset = b.offset;

            if (b.size == aligned_size) {
                _ = self.free_blocks.orderedRemove(i);
            } else {
                b.offset += @intCast(aligned_size);
                b.size -= @intCast(aligned_size);
            }

            return offset;
        }
    }

    return null;
}

fn insert_and_merge_free(self: *GPUAllocator, block: Block) !void {
    const index = std.sort.lowerBound(Block, self.free_blocks.items, block, Block.order);
    try self.free_blocks.insert(self.device.allocator, index, block);

    const next = index + 1;
    const next_offset = self.free_blocks.items[index].offset + self.free_blocks.items[index].size;
    if (next < self.free_blocks.items.len and next_offset == self.free_blocks.items[next].offset) {
        self.free_blocks.items[index].size += self.free_blocks.items[next].size;
        self.free_blocks.orderedRemove(next);
    }

    if (index != 0) {
        const prev = index - 1;
        const block_offset = self.free_blocks.items[prev].offset + self.free_blocks.items[prev].size;
        if (block_offset == self.free_blocks.items[index].offset) {
            self.free_blocks.items[prev].size += self.free_blocks.items[index].size;
            self.free_blocks.orderedRemove(index);
        }
    }
}

pub fn alloc(self: *GPUAllocator, size: u32) !Allocation {
    const aligned_size = std.mem.alignForward(u32, size, 16);
    const offset = self.alloc_from_free_list(aligned_size) orelse return .out_of_memory;

    const allocation: Allocation = .{
        .buffer = self.buffer,
        .offset = offset,
        .size = aligned_size,
    };

    self.used += aligned_size;
    return allocation;
}

pub fn free(self: *GPUAllocator, a: Allocation) !void {
    if (@as(u32, @bitCast(self.buffer)) != @as(u32, @bitCast(a.buffer))) {
        std.log.warn("Trying to free block with parent buffer {} in allocator with parent buffer {}", .{ a.buffer, self.buffer });
        return error.invalid_free;
    }

    const block: Block = .{ .offset = a.offset, .size = a.size };
    try self.insert_and_merge_free(block);
    self.used -= a.size;
}
