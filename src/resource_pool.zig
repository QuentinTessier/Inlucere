const std = @import("std");

pub const Handle = packed struct(u32) {
    index: u24,
    generation: u8,

    pub const invalid: Handle = .{ .index = 0, .generation = 0 };

    pub fn is_valid(self: Handle) bool {
        return self.generation != 0;
    }
};

pub fn ResourcePool(comptime T: type, comptime capacity: usize) type {
    std.debug.assert(capacity < std.math.maxInt(u24));

    return struct {
        const Self = @This();
        const OccupiedSet = std.bit_set.ArrayBitSet(u32, capacity);

        items: [capacity]T,
        generations: [capacity]u8,
        occupied: OccupiedSet,

        pub fn init(self: *@This()) void {
            self.items = undefined;
            self.generations = [1]u8{0} ** capacity;
            self.occupied = .initEmpty();
        }

        pub fn deinit(self: *@This(), ctx: anytype, deinit_resource: ?*const fn (*T, @TypeOf(ctx)) void) void {
            if (deinit_resource) |callback| {
                var ite = self.occupied.iterator(.{});
                while (ite.next()) |i| {
                    callback(&self.items[i], ctx);
                }
            }
            self.occupied = .initEmpty();
        }

        pub fn new(self: *@This()) !struct { Handle, *T } {
            var ite = self.occupied.iterator(.{ .kind = .unset });
            const index = ite.next() orelse return error.pool_full;

            self.occupied.set(index);

            const gen = blk: {
                self.generations[index] +%= 1;
                if (self.generations[index] == 0) self.generations[index] = 1;
                break :blk self.generations[index];
            };

            return .{
                .{ .index = @intCast(index), .generation = gen },
                &self.items[index],
            };
        }

        pub fn release(self: *@This(), handle: Handle) void {
            std.debug.assert(self.is_valid_handle(handle));
            self.occupied.unset(handle.index);
        }

        pub fn destroy(self: *@This(), handle: Handle, ctx: anytype, c: *const fn (*T, @TypeOf(ctx)) void) void {
            std.debug.assert(self.is_valid_handle(handle));
            c(&self.items[handle.index], ctx);
            self.occupied.unset(handle.index);
        }

        pub fn get(self: *@This(), handle: Handle) ?*T {
            if (!self.is_valid_handle(handle)) return null;
            return &self.items[handle.index];
        }

        pub const Iterator = struct {
            pool: *Self,
            inner: OccupiedSet.Iterator(.{}),

            pub fn next(self: *Iterator) ?struct { handle: Handle, ptr: *T } {
                const index = self.inner.next() orelse return null;

                const gen = self.pool.generations[index];
                return .{
                    .handle = .{ .index = @intCast(index), .generation = gen },
                    .ptr = &self.pool.items[index],
                };
            }
        };

        pub fn iterator(self: *@This()) Iterator {
            return .{ .pool = self, .inner = self.occupied.iterator(.{}) };
        }

        pub fn count(self: *const @This()) usize {
            return self.occupied.count();
        }

        pub fn is_full(self: *const @This()) bool {
            return self.occupied.count() == capacity;
        }

        fn is_valid_handle(self: *const @This(), handle: Handle) bool {
            if (handle.generation == 0) return false;

            const index: usize = handle.index;
            if (index >= capacity) return false;
            if (!self.occupied.isSet(index)) return false;
            if (self.generations[index] != handle.generation) return false;
            return true;
        }
    };
}
