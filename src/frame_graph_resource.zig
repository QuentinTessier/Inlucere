const std = @import("std");
pub const Image = @import("frame_graph_image.zig");
pub const Buffer = @import("frame_graph_buffer.zig");
const Pass = @import("frame_graph_pass.zig");

pub const Access = packed struct {
    read: bool = false,
    write: bool = false,
};

pub const Generation = struct {
    handle: u32,

    pub const invalid: Generation = .{ .handle = 0 };
    pub const default: Generation = .{ .handle = 1 };

    pub fn is_valid(self: Generation) bool {
        return self.handle != 0;
    }

    pub fn next(self: *const Generation) Generation {
        return .{ .handle = self.handle + 1 };
    }

    pub fn previous(self: *const Generation) Generation {
        return .{ .handle = self.handle - 1 };
    }

    pub fn eq(self: *const Generation, other: *const Generation) bool {
        return self.handle == other.handle;
    }
};

pub const Lifetime = struct {
    start_level: u32,
    end_level: u32,

    pub fn can_alias(self: *const Lifetime, other: *const Lifetime) bool {
        return self.end_level < other.start_level or other.end_level < self.start_level;
    }
};

pub const Base = struct {
    debug_name: ?[]const u8,
    imported: bool = false,
    lifetime: Lifetime,

    pub fn init(debug_name: ?[]const u8) Base {
        return Base{
            .debug_name = debug_name,
            .generation = .default,
        };
    }
};
