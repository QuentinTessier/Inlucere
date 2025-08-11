const std = @import("std");
const Device = @import("../Device.zig");

pub const ResourceKind = enum(u16) {
    buffer,
    texture2d,
    custom,
};

pub const Resource = union(ResourceKind) {
    buffer: Device.DynamicBuffer,
    texture2d: Device.Texture2D,
    custom: ?*anyopaque,
};

pub const BufferDescription = struct {
    name: ?[]const u8,
    size: u32,
    stride: u32,
    default_data: ?[]const u8 = null,

    pub fn fromBytes(name: ?[]const u8, default_data: []const u8, stride: u32) BufferDescription {
        return .{
            .name = name,
            .size = @intCast(default_data.len),
            .stride = stride,
            .default_data = default_data,
        };
    }

    pub fn empty(name: ?[]const u8, size: u32, stride: u32) BufferDescription {
        return .{
            .name = name,
            .size = size,
            .stride = stride,
            .default_data = null,
        };
    }

    pub fn construct(self: *const BufferDescription) !Device.Buffer {
        if (self.default_data) |default_data| {
            std.debug.assert(default_data.len == self.size);
            const b = try Device.DynamicBuffer.init(self.name, default_data, self.stride);
            return b.toBuffer();
        } else {
            std.debug.assert(self.size != 0 and self.stride != 0);
            const b = try Device.DynamicBuffer.initEmpty(self.name, self.size, self.stride);
            return b.toBuffer();
        }
    }
};

pub const Texture2DDescription = struct {
    name: ?[]const u8,
    width: u32,
    height: u32,
    format: Device.Texture.Format,
    levelCount: u32,

    pub fn construct(self: *const Texture2DDescription) !Device.Texture2D {
        var tex: Device.Texture2D = undefined;
        tex.init(&.{
            .name = self.name,
            .extent = .{ .width = self.width, .height = self.height },
            .format = self.format,
            .level = self.levelCount,
        });
        return tex;
    }
};

pub const ResourceDescription = union(ResourceKind) {
    buffer: BufferDescription,
    texture2d: Texture2DDescription,
    custom: ?*anyopaque,
};

pub const VirtualResource = struct {
    id: u16,
    version: u16,
    kind: ResourceKind,
};

pub fn Storage(comptime Enum: ResourceKind, comptime ResourceType: type, comptime ResourceDesc: type) type {
    return struct {
        pub const tag: ResourceKind = Enum;

        pub const Description = union(enum) {
            managed: ResourceDesc,
            imported: ResourceDesc,
        };

        aliasing: std.AutoHashMapUnmanaged(u16, u16),
        descriptions: std.AutoHashMapUnmanaged(u16, Description),
        resources: std.AutoArrayHashMapUnmanaged(u16, ResourceType),

        pub fn init() @This() {
            return .{
                .aliasing = .empty,
                .descriptions = .empty,
                .resources = .empty,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (@typeInfo(ResourceType) == .@"struct" and @hasDecl(ResourceType, "deinit")) {
                var desc_ite = self.descriptions.iterator();
                while (desc_ite.next()) |entry| {
                    if (std.meta.activeTag(entry.value_ptr.*) == .managed) {
                        if (self.resources.getPtr(entry.key_ptr.*)) |ptr| {
                            ptr.deinit();
                        }
                    }
                }
            }
            self.descriptions.deinit(allocator);
            self.resources.deinit(allocator);
            self.aliasing.deinit(allocator);
        }

        pub fn declare_managed(self: *@This(), allocator: std.mem.Allocator, id: u16, description: ResourceDesc) !void {
            try self.descriptions.put(allocator, id, .{ .managed = description });
        }

        pub fn declare_imported(self: *@This(), allocator: std.mem.Allocator, id: u16, resource: ResourceType, description: ?ResourceDesc) !void {
            try self.resources.put(allocator, id, resource);
            if (description) |_| {
                try self.descriptions.put(allocator, id, .{ .imported = void{} });
            }
        }

        pub fn get_resource(self: *@This(), id: u16) ?ResourceType {
            if (self.aliasing.get(id)) |aliased_id| {
                return self.resources.get(aliased_id);
            } else {
                return self.resources.get(id);
            }
        }

        pub fn get_description(self: *@This(), id: u16) ?*ResourceDescription {
            return self.descriptions.getPtr(id);
        }

        pub fn clear_aliasing(self: *@This()) void {
            self.aliasing.clearRetainingCapacity();
        }

        pub fn clear_resources(self: *@This()) void {
            if (@typeInfo(ResourceType) == .@"struct" and @hasDecl(ResourceType, "deinit")) {
                var desc_ite = self.descriptions.iterator();
                while (desc_ite.next()) |entry| {
                    if (std.meta.activeTag(entry.value_ptr.*) == .managed) {
                        if (self.resources.getPtr(entry.key_ptr.*)) |ptr| {
                            ptr.deinit();
                        }
                        self.resources.swapRemove(entry.key_ptr.*);
                    }
                }
            }
        }

        pub fn is_managed(self: *@This(), id: u16) bool {
            return if (self.descriptions.get(id)) |desc| desc == .managed else false;
        }

        pub fn is_imported(self: *@This(), id: u16) bool {
            return if (self.descriptions.get(id)) |desc| desc == .imported else false;
        }

        pub fn build_resource(self: *@This(), allocator: std.mem.Allocator, id: u16) !bool {
            const actual_id = if (self.aliasing.get(id)) |i| i else id;
            if (self.resources.contains(actual_id)) {
                return true;
            }

            const desc = self.descriptions.get(actual_id) orelse @panic("");

            const resource: ResourceType = try ResourceDesc.construct(&desc.managed);
            try self.resources.put(allocator, actual_id, resource);
            return true;
        }
    };
}
