const std = @import("std");

pub fn Storage(comptime DataType_: type, comptime DescriptionType_: type) type {
    return struct {
        const Self = @This();

        managed_resources: std.AutoArrayHashMapUnmanaged(u32, DataType_),
        imported_resources: std.AutoArrayHashMapUnmanaged(u32, DataType_),
        descriptions: std.AutoHashMapUnmanaged(u32, DescriptionType_),

        pub fn init() @This() {
            return .{
                .managed_resources = .empty,
                .imported_resources = .empty,
                .descriptions = .empty,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            var ite = self.managed_resources.iterator();
            while (ite.next()) |entry| {
                DescriptionType_.destroy_resource(allocator, entry.value_ptr);
            }
            self.managed_resources.deinit(allocator);
            self.imported_resources.deinit(allocator);
            self.descriptions.deinit(allocator);
        }

        pub fn add_managed_resource(self: *@This(), allocator: std.mem.Allocator, id: u32, desc: DescriptionType_) !void {
            try self.descriptions.put(allocator, id, desc);
        }

        pub fn import_resource(self: *@This(), allocator: std.mem.Allocator, id: u32, data: DataType_) !void {
            try self.imported_resources.put(allocator, id, data);
        }

        pub fn create(self: *@This(), allocator: std.mem.Allocator, id: u32) !void {
            if (self.descriptions.getPtr(id)) |desc| {
                try self.managed_resources.put(allocator, id, try DescriptionType_.create_resource(allocator, desc));
            } else {
                return error.NoSuchResource;
            }
        }
    };
}

pub const TypedEraseStorage = struct {
    erased_storage_ptr: *anyopaque,
    destructor: *const fn (*anyopaque, std.mem.Allocator) void,

    pub fn init(comptime DataType_: type, comptime DescriptionType_: type, allocator: std.mem.Allocator) !TypedEraseStorage {
        const typed_ptr = try allocator.create(Storage(DataType_, DescriptionType_));
        typed_ptr.* = .init();

        return .{
            .erased_storage_ptr = typed_ptr,
            .destructor = struct {
                pub fn inline_destructor(opaque_self: *anyopaque, a: std.mem.Allocator) void {
                    const self: *Storage(DataType_, DescriptionType_) = @ptrCast(@alignCast(opaque_self));
                    self.deinit(a);
                    a.destroy(self);
                }
            }.inline_destructor,
        };
    }

    pub fn cast(self: *TypedEraseStorage, comptime DataType_: type, comptime DescriptionType_: type) *Storage(DataType_, DescriptionType_) {
        return @ptrCast(@alignCast(self.erased_storage_ptr));
    }

    pub fn deinit(self: *TypedEraseStorage, allocator: std.mem.Allocator) void {
        self.destructor(self.erased_storage_ptr, allocator);
    }
};

pub fn GenericResource(comptime ResourceEnum: type, comptime Tag_: ResourceEnum, comptime DataType_: type, comptime DescriptionType_: type) type {
    std.debug.assert(@typeInfo(ResourceEnum) == .@"enum");
    std.debug.assert(@hasDecl(DescriptionType_, "create_resource"));
    std.debug.assert(@hasDecl(DescriptionType_, "destroy_resource"));
    return struct {
        pub const Tag: ResourceEnum = Tag_;
        pub const DataType: type = DataType_;
        pub const DescriptionType: type = DescriptionType_;
        pub const StorageType = Storage(DataType_, DescriptionType_);
    };
}

// TODO:    Rework to have a level of indirection from handles to physical resource. So the implementation of aliasing isn't to painful.
//          Only managed resource can be aliased, for debugging should add quite a bit of logging.
// Revision:    Predefine resources type (StaticBuffer, RingBuffer, Texture2D, ...), if the user wants to define a resource type, he can use the type UnknownResource{ ptr: ?*anyopaque = null }
//              This allows to know what type we are working on and how to access them (ZLS can help user better). Let complexity at comptime.
//              Simplify FBO creation and resource aliasing.
pub fn GenericResourceStorage(comptime ResourceEnum: type, comptime ResourceArray: std.EnumArray(ResourceEnum, type)) type {
    return struct {
        storages: std.EnumArray(ResourceEnum, TypedEraseStorage),

        pub fn GetResourceTypeByEnum(comptime Kind: ResourceEnum) type {
            return ResourceArray.get(Kind);
        }

        pub fn init(allocator: std.mem.Allocator) !@This() {
            var storages: std.EnumArray(ResourceEnum, TypedEraseStorage) = .initUndefined();

            inline for (std.meta.fields(ResourceEnum)) |f| {
                const field = @as(std.builtin.Type.EnumField, f);
                const resource_type = ResourceArray.get(@enumFromInt(field.value));

                storages.getPtr(@enumFromInt(field.value)).* = try TypedEraseStorage.init(
                    resource_type.DataType,
                    resource_type.DescriptionType,
                    allocator,
                );
            }

            return .{
                .storages = storages,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            inline for (std.meta.fields(ResourceEnum)) |f| {
                const field = @as(std.builtin.Type.EnumField, f);

                const type_erased = self.storages.getPtr(@enumFromInt(field.value));
                type_erased.deinit(allocator);
            }
        }

        pub fn GetStorageTypeByEnum(comptime Kind: ResourceEnum) type {
            const data_type: type = ResourceArray.get(Kind).DataType;
            const desc_type: type = ResourceArray.get(Kind).DescriptionType;

            return Storage(data_type, desc_type);
        }

        pub fn getStorage(self: *@This(), comptime kind: ResourceEnum) *GetStorageTypeByEnum(kind) {
            return self.storages.getPtr(kind).cast(ResourceArray.get(kind).DataType, ResourceArray.get(kind).DescriptionType);
        }
    };
}
