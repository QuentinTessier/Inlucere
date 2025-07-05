const std = @import("std");

pub const Commands = @import("Commands.zig");

pub const Configuration = struct {
    command_buffer_capacity: usize = 8,
    commands_memory_pool_preheat_size: usize = 128,
    commands_memory_pool_options: std.heap.MemoryPoolOptions,
};

pub fn CommandPool(comptime config: Configuration) type {
    return struct {
        pub const Self = @This();

        pub const Command = union(enum) {
            cmd_exec_secondary: *CommandBuffer,
            cmd_push_debug_group: Commands.CmdPushDebugGroupData,
            cmd_pop_debug_group: Commands.CmdPopDebugGroupData,
        };

        pub const CommandBuffer = struct {
            pub const Kind = enum(u32) {
                Primary,
                Secondary,
            };

            pub const State = enum(u32) {
                Idle,
                Recording,
                Executing,
            };

            kind: Kind,
            state: std.atomic.Value(State),
            command_pool: *Self,
            commands: std.DoublyLinkedList(Command),

            pub const CommandNode = std.DoublyLinkedList(Command).Node;

            pub fn primary(command_pool: *Self) CommandBuffer {
                return CommandBuffer{
                    .kind = .Primary,
                    .state = .Idle,
                    .command_pool = command_pool,
                    .commands = .{},
                };
            }

            pub fn secondary(command_pool: *Self) CommandBuffer {
                return CommandBuffer{
                    .kind = .Secondary,
                    .state = .Idle,
                    .command_pool = command_pool,
                    .commands = .{},
                };
            }

            pub fn begin(self: *CommandBuffer) void {
                std.debug.assert(self.state.load(.acquire) == .Idle);
                self.commands.first = null;
                self.state.store(.Recording, .monotonic);
            }

            pub fn end(self: *CommandBuffer) void {
                std.debug.assert(self.state.load(.acquire) == .Recording);
                self.state.store(.Idle, .monotonic);
            }

            pub fn push_debug_group(self: *CommandBuffer, id: u32, message: []const u8) !void {
                const cmd = try self.command_pool.acquireCommandNode();

                cmd.data = .{ .cmd_push_debug_group = .{
                    .id = id,
                    .message = message,
                } };
                self.commands.append(cmd);
            }

            pub fn pop_debug_group(self: *CommandBuffer) !void {
                const cmd = try self.command_pool.acquireCommandNode();

                cmd.data = .{ .cmd_pop_debug_group = void{} };
                self.commands.append(cmd);
            }
        };

        allocator: std.mem.Allocator,

        available_command_buffers: [config.command_buffer_capacity]bool,
        command_buffers: [config.command_buffer_capacity]CommandBuffer,
        command_buffers_mutex: std.Thread.Mutex,

        command_nodes: std.heap.MemoryPoolExtra(CommandBuffer.CommandNode, config.commands_memory_pool_options),
        command_nodes_mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .available_command_buffers = [1]bool{true} ** config.command_buffer_capacity,
                .command_buffer = undefined,
                .command_buffers_mutex = .{},
                .command_nodes = try .initPreheat(allocator, config.commands_memory_pool_preheat_size),
                .command_nodes_mutex = .{},
            };
        }

        pub fn deinit(self: *@This()) void {
            self.command_nodes.deinit();
        }

        pub fn findAvailableIndex(self: *const @This()) ?usize {
            return std.mem.indexOfScalar(bool, self.available_command_buffers, true);
        }

        pub fn findCommandBufferIndex(self: *const @This(), command_buffer: *CommandBuffer) ?usize {
            for (self.command_buffers, 0..) |*item, index| {
                if (item == command_buffer) {
                    return index;
                }
            }
            if (std.debug.runtime_safety) {
                @panic("This should never append, trying to release a commandbuffer allocated using another command pool");
            }
            return null;
        }

        pub fn acquireBuffer(self: *@This()) ?*CommandBuffer {
            self.command_buffers_mutex.lock();
            defer self.command_buffers_mutex.unlock();
            const opt_index = self.findAvailableIndex();
            return if (opt_index) |index| &self.command_buffers[index] else null;
        }

        pub fn releaseBuffer(self: *@This(), command_buffer: *CommandBuffer) void {
            self.command_buffers_mutex.lock();
            defer self.command_buffers_mutex.unlock();

            if (self.findCommandBufferIndex(command_buffer)) |index| {
                std.debug.assert(self.available_command_buffers[index] == false);
                self.available_command_buffers[index] = true;
            }
        }

        pub fn acquireCommandNode(self: *@This()) !*CommandBuffer.CommandNode {
            self.command_nodes_mutex.lock();
            defer self.command_nodes_mutex.unlock();

            return self.command_nodes.create();
        }

        pub fn releaseCommandNode(self: *@This(), node: *CommandBuffer.CommandNode) void {
            self.command_nodes_mutex.lock();
            defer self.command_nodes_mutex.unlock();

            self.command_nodes.destroy(node);
        }
    };
}
