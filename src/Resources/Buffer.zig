const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const Buffer = @This();

pub const Error = error{
    OutOfMemory,
    FailedToMap,
};

handle: u32,
size: usize,
stride: usize,

pub const Binding = union(enum) {
    _whole: void,
    _range: [2]u32,

    pub fn whole() Binding {
        return .{ ._whole = void{} };
    }

    pub fn range(offset: u32, size: u32) Binding {
        return .{ ._range = .{ offset, size } };
    }
};
