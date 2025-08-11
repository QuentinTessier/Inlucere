const std = @import("std");
const builtin = @import("builtin");
pub const GenericResource = @import("generic_resource.zig");

pub const ResourceReference = struct {
    id: u32,
    version: u32,
};

// ------- Example -------
// const ResourceKind = enum { buffer, texture, color_attachment, depth_attachment, depth_stencil_attachment };
// const Buffer = struct { ... };
// const BufferDescription = struct {
//      pub fn create_resource(std.mem.Allocator, *const @This()) !Buffer {...}
//      pub fn destroy_resource(std.mem.Allocator, *const Buffer) void {...}
// };
//
// const Texture = struct { ... };
// const TextureDescription = struct {
//      pub fn create_resource(std.mem.Allocator, *const @This()) !Texture {...}
//      pub fn destroy_resource(std.mem.Allocator, *const Texture) void {...}
// };
//
// const ColorAttachment = struct { ... };
// const ColorAttachmentDescription = struct {
//      pub fn create_resource(std.mem.Allocator, *const @This()) !ColorAttachment {...}
//      pub fn destroy_resource(std.mem.Allocator, *const ColorAttachment) void {...}
// };
//
// const FrameGraph = FrameGraph(ResourceKind, &.{
//      GenericResource(ResourceKind, .buffer, Buffer, BufferDescription),
//      GenericResource(ResourceKind, .texture, Texture, TextureDescription),
// }, .{ .automatic_framebuffer_creation = true }); // If .automatic_framebuffer_creation is turned on, will look for resources type ColorAttachment, DepthAttachment and DepthStencilAttachment
//
// void main() {
//      ...
//      var fg:FrameGraph = .init(allocator);
//
//      const uniform_buffer_id = try fg.declare_managed(.buffer, .{ .size = 128, .stride = 16 });
//      const uniform_buffer_v1 = try fg.current_version(uniform_buffer_id);
//      const uniform_buffer_v2 = try fg.new_version(uniform_buffer_id);
//      const color_id = try fg.declare_managed(.color_attachment, .{ .texture_id = ... });
//      const pass_builder: PassBuilder = .init(allocator, "geometry");
//      try pass_builder.read(shadow_map);
//      try pass_builder.read_color_attachment(0, albedo_gbuffer_v1, .keep());
//      try pass_builder.read_color_attachment(1, normal_gbuffer_v1, .keep());
//      try pass_builder.read_depth_attachment(2, depth_gbuffer_v1, .keep());
//
//      try pass_builder.write_color_attachment(0, albedo_gbuffer_v2, .keep());
//      try pass_builder.write_color_attachment(1, normal_gbuffer_v2, .keep());
//      try pass_builder.write_depth_attachment(2, depth_gbuffer_v2, .keep());
//      fg.declare_pass(&pass_builder);
//      fg.compile(.{ .build_fbos = true });
// }
//------- Example -------

// TODO: Add a PassBuilder type responsible to create the underlying pass representation and gather all needed resources. (see example above)
pub const Pass = struct {
    name: []u8,
    read_resources: std.ArrayListUnmanaged(ResourceReference),
    write_resources: std.ArrayListUnmanaged(ResourceReference),
    v_table: struct {
        deinit: *const fn (*Pass, std.mem.Allocator) void,
        execute: *const fn (*Pass) anyerror!void,
    },

    pub fn does_read(self: *const Pass, ref: ResourceReference) bool {
        for (self.read_resources.items) |item| {
            if (item.id == ref.id and item.version == ref.version) {
                return true;
            }
        }
        return false;
    }

    pub fn does_write(self: *const Pass, ref: ResourceReference) bool {
        for (self.write_resources.items) |item| {
            if (item.id == ref.id and item.version == ref.version) {
                return true;
            }
        }
        return false;
    }

    pub fn init(allocator: std.mem.Allocator, name: []const u8, reads: []const ResourceReference, writes: []const ResourceReference) !Pass {
        var read_resources: std.ArrayListUnmanaged(ResourceReference) = try .initCapacity(allocator, reads.len);
        for (reads) |r| {
            read_resources.appendAssumeCapacity(r);
        }
        var write_resources: std.ArrayListUnmanaged(ResourceReference) = try .initCapacity(allocator, writes.len);
        for (writes) |w| {
            write_resources.appendAssumeCapacity(w);
        }

        return .{
            .name = try allocator.dupe(u8, name),
            .read_resources = read_resources,
            .write_resources = write_resources,
            .v_table = undefined,
        };
    }

    pub fn deinit(self: *Pass, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.read_resources.deinit(allocator);
        self.write_resources.deinit(allocator);
        self.v_table.deinit(self, allocator);
    }
};

pub fn GenericFrameGraph(comptime ResourceEnum: type, comptime ResourceArray: std.EnumArray(ResourceEnum, type)) type {
    return struct {
        pub const ResourceStorage = GenericResource.GenericResourceStorage(ResourceEnum, ResourceArray);

        allocator: std.mem.Allocator,
        next_id: u32 = 1,

        // Resources
        storage_: ResourceStorage,
        resource_version: std.AutoHashMapUnmanaged(u32, u32),
        resource_kind: if (builtin.mode == .Debug) std.AutoHashMapUnmanaged(u32, ResourceEnum) else void,

        // Pass
        passes: std.AutoArrayHashMapUnmanaged(u32, *Pass),

        // Compiled data
        execution_order: ?[][]u32,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .allocator = allocator,
                .storage_ = try .init(allocator),
                .resource_version = .empty,
                .resource_kind = if (builtin.mode == .Debug) std.AutoHashMapUnmanaged(u32, ResourceEnum).empty else void{},
                .passes = .empty,
                .execution_order = null,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.storage_.deinit(self.allocator);
            self.resource_version.deinit(self.allocator);
            if (builtin.mode == .Debug) self.resource_kind.deinit(self.allocator);

            var ite = self.passes.iterator();
            while (ite.next()) |entry| {
                entry.value_ptr.*.deinit(self.allocator);
            }
            self.passes.deinit(self.allocator);
            self.release_execution_order();
        }

        pub fn release_execution_order(self: *@This()) void {
            if (self.execution_order == null) {
                return;
            }

            for (self.execution_order.?) |item| {
                self.allocator.free(item);
            }
            self.allocator.free(self.execution_order.?);
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
            if (builtin.mode == .Debug) {
                try self.resource_kind.put(self.allocator, i, kind);
            }
            return i;
        }

        pub fn get_resource(self: *@This(), comptime kind: ResourceEnum, i: u32) !*ResourceStorage.GetResourceTypeByEnum(kind).DataType {
            if (builtin.mode == .Debug) {
                const stored_kind = self.resource_kind.get(i) orelse @panic("Not such resource");
                std.debug.assert(stored_kind == kind);
            }

            const s = self.storage(kind);
            if (s.descriptions.contains(i)) {
                if (s.managed_resources.getPtr(i)) |ptr| {
                    return ptr;
                } else {
                    try s.create(self.allocator, i);
                    return s.managed_resources.getPtr(i).?;
                }
            } else if (s.imported_resources.getPtr(i)) |ptr| {
                return ptr;
            }
            return error.NoSuchResource;
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
                    .version = version.*,
                };
            } else {
                return error.NotSuchResource;
            }
        }

        pub fn declare_pass(self: *@This(), comptime PassType: type, name: []const u8, reads: []const ResourceReference, writes: []const ResourceReference) !struct {
            id: u32,
            pass: *PassType,
        } {
            std.debug.assert(@hasField(PassType, "pass"));
            std.debug.assert(@FieldType(PassType, "pass") == Pass);

            const i = self.id();
            var ptr = try self.allocator.create(PassType);

            const base_ptr: *Pass = &ptr.pass;
            base_ptr.* = try Pass.init(self.allocator, name, reads, writes);
            base_ptr.v_table.deinit = PassType.deinit;

            try self.passes.put(self.allocator, i, &ptr.pass);

            return .{
                .id = i,
                .pass = ptr,
            };
        }

        pub fn compile(self: *@This()) !bool {
            if (try self.topological_sort()) |result| {
                self.execution_order = result;
                return true;
            } else {
                return false;
            }
        }

        fn topological_sort(self: *@This()) !?[][]u32 {
            var in_degree: std.AutoHashMap(u32, u32) = .init(self.allocator);
            defer in_degree.deinit();

            var adj_list: std.AutoHashMap(u32, std.ArrayList(u32)) = .init(self.allocator);
            defer {
                var ite = adj_list.iterator();
                while (ite.next()) |entry| {
                    entry.value_ptr.deinit();
                }
                adj_list.deinit();
            }

            for (self.passes.keys()) |pass_id| {
                try in_degree.put(pass_id, 0);
                try adj_list.put(pass_id, std.ArrayList(u32).init(self.allocator));
            }

            for (self.passes.keys(), @as([]*Pass, self.passes.values())) |pass_id, pass| {
                for (pass.write_resources.items) |written_resource| {
                    for (self.passes.keys(), @as([]*Pass, self.passes.values())) |other_pass_id, other_pass| {
                        if (pass_id != other_pass_id and other_pass.does_read(written_resource)) {
                            const adj_ptr = adj_list.getPtr(pass_id) orelse @panic("");
                            try adj_ptr.append(other_pass_id);

                            const in_degree_ptr = in_degree.getPtr(other_pass_id) orelse @panic("");
                            in_degree_ptr.* += 1;
                        }
                    }
                }
            }

            var current_level: std.ArrayList(u32) = .init(self.allocator);
            defer current_level.deinit();

            var next_level: std.ArrayList(u32) = .init(self.allocator);
            defer next_level.deinit();

            var execution_order: std.ArrayList([]u32) = .init(self.allocator);
            var total_processed: usize = 0;

            var in_degree_ite = in_degree.iterator();
            while (in_degree_ite.next()) |entry| {
                if (entry.value_ptr.* == 0) {
                    try current_level.append(entry.key_ptr.*);
                }
            }

            while (current_level.items.len > 0) {
                var level: std.ArrayListUnmanaged(u32) = .empty;

                while (current_level.items.len > 0) {
                    const current = current_level.orderedRemove(0);
                    try level.append(self.allocator, current);
                    total_processed += 1;

                    const neighbor_list = adj_list.get(current) orelse @panic("");
                    for (neighbor_list.items) |neighbor| {
                        const in_degree_ptr = in_degree.getPtr(neighbor) orelse @panic("");
                        in_degree_ptr.* -= 1;
                        if (in_degree_ptr.* == 0) {
                            try next_level.append(neighbor);
                        }
                    }
                }

                try execution_order.append(try level.toOwnedSlice(self.allocator));
                std.mem.swap(std.ArrayList(u32), &current_level, &next_level);
            }

            if (total_processed == self.passes.count()) {
                return try execution_order.toOwnedSlice();
            } else {
                for (execution_order.items) |item| {
                    self.allocator.free(item);
                }
                execution_order.deinit();
                return null;
            }
        }
    };
}
