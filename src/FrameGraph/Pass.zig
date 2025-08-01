const std = @import("std");
const Resource = @import("Resource.zig");
const ResourceReference = @import("frame_graph.zig").ResourceReference;
const Device = @import("../Device.zig");

pub const PassDesc = struct {
    name: []const u8,
    inputs: []const ResourceReference,
    outputs: []const ResourceReference,
};

pub const Pass = @This();

name: []const u8,
read_resources: std.ArrayListUnmanaged(ResourceReference),
write_resources: std.ArrayListUnmanaged(ResourceReference),

pub fn init(allocator: std.mem.Allocator, name: []const u8) !Pass {
    return .{
        .name = try allocator.dupe(u8, name),
        .read_resources = .empty,
        .write_resources = .empty,
    };
}

pub fn deinit(self: *Pass, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    self.read_resources.deinit(allocator);
    self.write_resources.deinit(allocator);
}

pub fn read(self: *Pass, allocator: std.mem.Allocator, ref: ResourceReference) !void {
    try self.read_resources.append(allocator, ref);
}

pub fn write(self: *Pass, allocator: std.mem.Allocator, ref: ResourceReference) !void {
    try self.write_resources.append(allocator, ref);
}

pub const ReadWriteReference = struct {
    read: ResourceReference,
    write: ResourceReference,
};

pub fn read_write(self: *Pass, allocator: std.mem.Allocator, rw: ReadWriteReference) !void {
    std.debug.assert(rw.read.id == rw.write.id);
    std.debug.assert(rw.read.version != rw.write.version);

    try self.read_resources.append(allocator, rw.read);
    try self.write_resources.append(allocator, rw.write);
}

pub fn is_reading_from(self: *const Pass, ref: ResourceReference) bool {
    for (self.read_resources.items) |resource| {
        if (resource.id == ref.id and resource.version == ref.version) {
            return true;
        }
    }
    return false;
}

pub fn is_writing_to(self: *const Pass, ref: ResourceReference) bool {
    for (self.write_resources.items) |resource| {
        if (resource.id == ref.id and resource.version == ref.version) {
            return true;
        }
    }
    return false;
}
