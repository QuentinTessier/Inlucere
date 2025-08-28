const std = @import("std");
const Generation = @import("frame_graph_resource.zig").Generation;
const Access = @import("frame_graph_resource.zig").Access;

pub const ID = struct {
    handle: u16,

    pub const invalid: ID = .{ .handle = 0 };

    pub fn eq(self: *const ID, other: *const ID) bool {
        return self.handle == other.handle;
    }
};

pub const UsageHints = packed struct {
    storage: bool = false,
    uniform: bool = false,
    vertex: bool = false,
    index: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const Description = struct {
    size: u32,
    stride: u32,

    pub fn eq(self: *const Description, other: *const Description) bool {
        return self.size == other.size;
    }
};

pub const Reference = struct {
    id: ID,
    read_gen: Generation,
    write_gen: Generation,
    usage_hints: UsageHints,

    pub fn access(self: *const Reference) Access {
        return Access{
            .read = self.read_gen.is_valid(),
            .write = self.write_gen.is_valid(),
        };
    }

    pub fn read(self: *const Reference) bool {
        return self.read_gen.is_valid();
    }

    pub fn write(self: *const Reference) bool {
        return self.write_gen.is_valid();
    }
};
