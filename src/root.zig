const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");

pub const GPUContext = @This();

allocator: std.mem.Allocator,
base_wrapper: vk.BaseWrapper,
instance: vk.Instance,

pub fn init(allocator: std.mem.Allocator, name: [*:0]const u8, loader: *const fn (vk.Instance, [*]const u8) ?*anyopaque) !GPUContext {
    var self: GPUContext = undefined;
    self.allocator = allocator;
    self.base_wrapper = vk.BaseWrapper.load(loader);
}
