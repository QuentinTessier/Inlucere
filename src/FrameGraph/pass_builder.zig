const std = @import("std");
const Device = @import("../Device.zig");
const Resource = @import("resources.zig");
const FrameGraph = @import("root.zig").FrameGraph;

pub const PassBuilder = @This();

pub const ColorAttachment = struct {
    location: u32,
    virtual_resource: Resource.VirtualResource,
};

name: []u8,
virtual_resource_read: std.ArrayListUnmanaged(Resource.VirtualResource),
virtual_resource_write: std.ArrayListUnmanaged(Resource.VirtualResource),
virtual_color_attachment: std.ArrayListUnmanaged(ColorAttachment),
virtual_depth_attachment: ?Resource.VirtualResource,
execution_callback: *const fn (*FrameGraph, *Device, *Pass) anyerror!void,
attached_data: ?*anyopaque,

pub const Pass = struct {
    name: []u8,
    virtual_resource_read: []Resource.VirtualResource,
    virtual_resource_write: []Resource.VirtualResource,
    virtual_color_attachment: []ColorAttachment,
    virtual_depth_attachment: ?Resource.VirtualResource,
    execution_callback: *const fn (*FrameGraph, *Device, *Pass) anyerror!void,
    attached_data: ?*anyopaque,

    pub fn writes_to(self: *const Pass, vresource: Resource.VirtualResource) bool {
        for (self.virtual_resource_write) |item| {
            if (item.id == vresource.id and item.version == vresource.version) {
                return true;
            }
        }
        return false;
    }

    pub fn reads_from(self: *const Pass, vresource: Resource.VirtualResource) bool {
        for (self.virtual_resource_read) |item| {
            if (item.id == vresource.id and item.version == vresource.version) {
                return true;
            }
        }
        return false;
    }
};

pub fn init(allocator: std.mem.Allocator, name: []const u8, execution_callback: *const fn (*FrameGraph, *Device, *Pass) anyerror!void) !PassBuilder {
    return .{
        .name = try allocator.dupe(u8, name),
        .virtual_resource_read = .empty,
        .virtual_resource_write = .empty,
        .virtual_color_attachment = .empty,
        .virtual_depth_attachment = null,
        .execution_callback = execution_callback,
        .attached_data = null,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.virtual_resource_read.deinit(allocator);
    self.virtual_resource_write.deinit(allocator);
    self.virtual_color_attachment.deinit(allocator);
}

pub fn userdata(self: *@This(), data: *anyopaque) void {
    self.attached_data = data;
}

pub fn read(self: *@This(), allocator: std.mem.Allocator, virtual_resource: Resource.VirtualResource) !bool {
    for (self.virtual_resource_read.items) |item| {
        if (item.id == virtual_resource.id) {
            std.log.warn("Pass {s} is already reading virtual resource {}", .{ self.name, item.id });
            return false;
        }
    }

    try self.virtual_resource_read.append(allocator, virtual_resource);
    return true;
}

pub fn write(self: *@This(), allocator: std.mem.Allocator, virtual_resource: Resource.VirtualResource) !bool {
    for (self.virtual_resource_write.items) |item| {
        if (item.id == virtual_resource.id) {
            std.log.warn("Pass {s} is already writing virtual resource {}", .{ self.name, item.id });
            return false;
        }
    }

    try self.virtual_resource_write.append(allocator, virtual_resource);
    return true;
}

pub fn read_write(self: *@This(), allocator: std.mem.Allocator, virtual_resource: Resource.VirtualResource) !bool {
    for (self.virtual_resource_read.items) |item| {
        if (item.id == virtual_resource.id) {
            std.log.warn("Pass {s} is already reading virtual resource {}", .{ self.name, item.id });
            return false;
        }
    }

    for (self.virtual_resource_write.items) |item| {
        if (item.id == virtual_resource.id) {
            std.log.warn("Pass {s} is already writing virtual resource {}", .{ self.name, item.id });
            return false;
        }
    }

    try self.virtual_resource_read.append(allocator, virtual_resource);
    try self.virtual_resource_write.append(allocator, virtual_resource);
    return true;
}

pub fn color_attachment(self: *@This(), allocator: std.mem.Allocator, location: u32, virtual_resource: Resource.VirtualResource) !bool {
    for (self.virtual_color_attachment.items) |item| {
        if (item.location == location) {
            std.log.warn("Pass {s} already has a color attachment at location {}", .{ self.name, item.location });
            return false;
        }
    }

    if (!try self.read_write(allocator, virtual_resource)) {
        return false;
    }

    try self.virtual_color_attachment.append(allocator, .{
        .location = location,
        .virtual_resource = virtual_resource,
    });
    return true;
}

pub fn depth_attachment(self: *@This(), allocator: std.mem.Allocator, virtual_resource: Resource.VirtualResource) !bool {
    if (self.virtual_depth_attachment != null) {
        std.log.warn("Pass {s} already has a depth attachment", .{self.name});
        return false;
    }

    if (!try self.read_write(allocator, virtual_resource)) {
        return false;
    }

    self.virtual_depth_attachment = virtual_resource;
    return true;
}

pub fn finalize(self: *@This(), allocator: std.mem.Allocator) !Pass {
    var p: Pass = undefined;
    p.name = self.name;
    p.virtual_resource_read = try self.virtual_resource_read.toOwnedSlice(allocator);
    p.virtual_resource_write = try self.virtual_resource_write.toOwnedSlice(allocator);
    p.virtual_color_attachment = try self.virtual_color_attachment.toOwnedSlice(allocator);
    p.virtual_depth_attachment = self.virtual_depth_attachment;
    p.execution_callback = self.execution_callback;
    p.attached_data = self.attached_data;

    self.reset();
    return p;
}

pub fn reset(self: *@This()) void {
    self.virtual_resource_read.clearRetainingCapacity();
    self.virtual_resource_write.clearRetainingCapacity();
    self.virtual_color_attachment.clearRetainingCapacity();
    self.virtual_depth_attachment = null;
    self.attached_data = null;
}

// TODO: ColorAttachments
