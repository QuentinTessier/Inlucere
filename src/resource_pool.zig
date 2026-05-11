const std = @import("std");

pub const Handle = packed struct(u32) {
    index: u24,
    generation: u8,
};

pub fn ResourcePool(comptime T: type, comptime S: usize) type {
    std.debug.assert(S < std.math.maxInt(u24));

    return struct {
        items: []T,
        generations: []u8,
        free_slots: std.bit_set.ArrayBitSet(u32, S),

        pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
            self.items = try allocator.alloc(T, S);
            self.generations = try allocator.alloc(u8, S);
            self.free_slots = .initEmpty();
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, deinit_resource: ?*const fn (*T, std.mem.Allocator) void) void {
            if (deinit_resource) |callback| {
                for (self.items, 0..) |*slot, i| {
                    if (self.free_slots.isSet(i)) {
                        callback(slot, allocator);
                    }
                }
            }
            allocator.free(self.items);
            allocator.free(self.generations);
        }

        pub fn set(self: *@This()) !struct { Handle, *T } {
            var ite = self.free_slots.iterator(.{ .kind = .unset });
            const index = ite.next() orelse return error.PoolFull;

            const item_ptr = &self.items[index];
            const generation_ptr = &self.generations[index];
            self.free_slots.set(index);

            generation_ptr.* += 1;
            return .{
                Handle{ .index = @intCast(index), .generation = generation_ptr.* },
                item_ptr,
            };
        }

        pub fn get(self: *@This(), handle: Handle) ?*T {
            const index: usize = @intCast(handle.index);

            if (!self.free_slots.isSet(index) or self.generations[index] != handle.index) {
                return null;
            }

            return &self.items[index];
        }
    };
}
