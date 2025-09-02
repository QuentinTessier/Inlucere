const std = @import("std");

// To perform aliasing we can look into "Interval Scheduling" class of algorithm
// In our case, we can get away with a more but force line sweep approach (see minimal implementation below)
//
// Group all resource that can be aliased together into have an array of interval
// Sort the array of interval by its start_level
// Perform line sweep algorithm
// Get back a slot per resource
//
//
// This approach will produce very strict aliasing, image/buffer must have the same description
// Doesn't work with mega-texture and sparse texture since it isn't "subresource" aware

// const std = @import("std");
// const builtin = @import("builtin");

// var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

// pub const Interval = struct {
//     start: u32,
//     end: u32,

//     pub fn lessThan(_: void, lhs: Interval, rhs: Interval) bool {
//         return lhs.start < rhs.start;
//     }
// };

// pub const Slot = struct {
//     id: usize,
//     free_after: u32,

//     pub fn priority(_: void, a: Slot, b: Slot) std.math.Order {
//         return std.math.order(a.free_after, b.free_after);
//     }
// };

// pub fn main() !void {
//     const allocator, const is_debug = gpa: {
//         break :gpa switch (builtin.mode) {
//             .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
//             .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
//         };
//     };
//     defer if (is_debug) {
//         _ = debug_allocator.deinit();
//     };

//     const test_intervals = [_]Interval{
//         .{ .start = 0, .end = 4 }, // R0
//         .{ .start = 1, .end = 3 }, // R1
//         .{ .start = 2, .end = 6 }, // R2
//         .{ .start = 5, .end = 7 }, // R3
//         .{ .start = 3, .end = 5 }, // R4
//         .{ .start = 6, .end = 8 }, // R5
//         .{ .start = 7, .end = 9 }, // R6
//         .{ .start = 8, .end = 10 }, // R7
//         .{ .start = 0, .end = 2 }, // R8
//         .{ .start = 9, .end = 11 }, // R9
//     };

//     var resource_intervals: std.ArrayList(Interval) = .init(allocator);
//     defer resource_intervals.deinit();

//     try resource_intervals.appendSlice(&test_intervals);

//     var physical_slot: std.ArrayList(usize) = .init(allocator);
//     defer physical_slot.deinit();

//     try physical_slot.appendNTimes(std.math.maxInt(usize), (&test_intervals).len);

//     Sort intervals by start time
//     std.sort.block(Interval, resource_intervals.items, void{}, Interval.lessThan);

//     var free_slots: std.PriorityQueue(Slot, void, Slot.priority) = .init(allocator, void{});
//     defer free_slots.deinit();

//     var reusable_list: std.ArrayList(Slot) = .init(allocator);
//     defer reusable_list.deinit();

//     var next_slot_id: usize = 0;

//     for (resource_intervals.items, 0..) |interval, i| {
//         std.debug.print("Processing interval [{}, {}]\n", .{ interval.start, interval.end });

//         while (free_slots.peek()) |item| {
//             if (item.free_after < interval.start) {
//                 const expired = free_slots.remove();
//                 std.debug.print("  Reclaiming slot {} (expired at {})\n", .{ expired.id, expired.free_after });
//                 try reusable_list.append(expired);
//             } else {
//                 break;
//             }
//         }

//         var slot: Slot = undefined;
//         if (reusable_list.pop()) |s| {
//             slot = s;
//             std.debug.print("  Taking slot {} from heap (free_after={})\n", .{ slot.id, slot.free_after });
//         } else {
//             slot.id = next_slot_id;
//             std.debug.print("  Allocating new slot {}\n", .{slot.id});
//             next_slot_id += 1;
//         }

//         physical_slot.items[i] = slot.id;
//         slot.free_after = interval.end;
//         try free_slots.add(slot);

//         std.debug.print("  Assigned interval [{}, {}] to slot {}\n", .{ interval.start, interval.end, slot.id });
//     }

//     std.debug.print("\nFinal assignment:\n", .{});
//     for (0..physical_slot.items.len) |assigned| {
//         std.debug.print("  [{}, {}] => slot {}\n", .{
//             resource_intervals.items[assigned].start,
//             resource_intervals.items[assigned].end,
//             physical_slot.items[assigned],
//         });
//     }
// }
