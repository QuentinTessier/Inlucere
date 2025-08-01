const std = @import("std");
const builtin = @import("builtin");
const GenericResource = @import("generic_resource.zig");

pub const ResourceReference = struct {
    id: u32,
    version: u32,
};

pub fn GenericFrameGraph(comptime ResourceEnum: type, comptime ResourceArray: std.EnumArray(ResourceEnum, type)) type {
    return struct {
        pub const ResourceStorage = GenericResource.GenericResourceStorage(ResourceEnum, ResourceArray);

        allocator: std.mem.Allocator,
        storage_: ResourceStorage,
        resource_version: std.AutoHashMapUnmanaged(u32, u32),
        resource_kind: if (builtin.mode == .Debug) std.AutoHashMapUnmanaged(u32, ResourceEnum) else void,
        next_id: u32 = 1,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .allocator = allocator,
                .storage_ = .init(allocator),
                .resource_version = .empty,
                .resource_kind = if (builtin.mode == .Debug) std.AutoHashMapUnmanaged(u32, ResourceEnum).empty else void{},
            };
        }

        pub fn deinit(self: *@This()) void {
            self.storage_.deinit(self.allocator);
        }

        pub fn storage(self: *@This(), comptime kind: ResourceEnum) *ResourceStorage.GetStorageTypeByEnum(kind) {
            return self.storage_.getStorage(kind);
        }

        pub fn id(self: *@This()) u32 {
            const i = self.next_id;
            self.next_id += 1;
            return i;
        }

        pub fn declare_managed(self: *@This(), comptime kind: ResourceEnum, desc: ResourceStorage.GetResourceTypeByEnum(kind).DescriptionType) !u32 {
            const i = self.id();
            try self.storage(kind).add_managed_resource(self.allocator, i, desc);
            try self.resource_version.put(self.allocator, i, 0);
            if (builtin.mode == .Debug) {
                try self.resource_kind.put(self.allocator, i, kind);
            }
            return i;
        }

        pub fn declare_imported(self: *@This(), comptime kind: ResourceEnum, data: ResourceStorage.GetResourceTypeByEnum(kind).DataType) !u32 {
            const i = self.id();
            try self.storage(kind).import_resource(self.allocator, i, data);
            try self.resource_version.put(i, 0);
            return i;
        }

        pub fn current_version(self: *@This(), identifier: u32) !ResourceReference {
            if (self.resource_version.get(identifier)) |version| {
                return ResourceReference{
                    .id = identifier,
                    .version = version,
                };
            } else {
                return error.NotSuchResource;
            }
        }

        pub fn new_version(self: *@This(), identifier: u32) !ResourceReference {
            if (self.resource_version.getPtr(identifier)) |version| {
                version.* += 1;
                return ResourceReference{
                    .id = identifier,
                    .version = version,
                };
            } else {
                return error.NotSuchResource;
            }
        }
    };
}
