const std = @import("std");
const gl = @import("../../gl4_6.zig");

pub fn BufferedBuffer(comptime FrameCount: usize) type {
    return struct {
        handle: u32,
        memory: [*]u8,
        buffers: [FrameCount][]u8,
        fences: [FrameCount]?gl.GLsync,
        current_buffer: u32, // TODO: Probably not worth it, but couldn't be a std.atomic.Value(u32)

        pub const Operation = enum(u8) {
            NonBlocking,
            Blocking,
        };

        pub fn init(size_per_frame: usize) !@This() {
            var handle: u32 = 0;

            gl.createBuffers(1, @ptrCast(&handle));
            gl.namedBufferStorage(
                handle,
                @intCast(FrameCount * size_per_frame),
                null,
                gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_UNSYNCHRONIZED_BIT,
            );

            const ptr = gl.mapNamedBuffer(
                handle,
                gl.MAP_WRITE_BIT | gl.MAP_PERSISTENT_BIT | gl.MAP_UNSYNCHRONIZED_BIT | gl.MAP_FLUSH_EXPLICIT_BIT,
            );
            if (ptr == null) {
                gl.deleteBuffers(1, @ptrCast(&handle));
                return error.FailedToMap;
            }

            return .{
                .handle = handle,
                .memory = @ptrCast(ptr.?),
                .buffers = build_buffers: {
                    var buffers: [FrameCount][]u8 = undefined;
                    for (0..FrameCount) |i| {
                        const offset = i * size_per_frame;
                        buffers[i] = @as([*]u8, @ptrCast(ptr.?))[offset .. offset + size_per_frame];
                    }
                    break :build_buffers buffers;
                },
                .fences = [1]gl.GLsync{null} ** FrameCount,
                .current_buffer = 0,
            };
        }

        pub fn deinit(self: @This()) void {
            for (self.fences) |fence| {
                if (fence != null) {
                    gl.clientWaitSync(fence.?, gl.SYNC_FLUSH_COMMANDS_BIT, gl.TIMEOUT_IGNORED);
                    gl.deleteSync(fence.?);
                }
            }
            _ = gl.unmapNamedBuffer(self.handle);
            gl.deleteBuffers(1, @ptrCast(&self.handle));
        }

        pub fn isCurrentReady(self: *const @This()) bool {
            if (self.fences[self.current_buffer]) |fence| {
                const status = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, 0);
                return status == gl.ALREADY_SIGNALED or status == gl.CONDITION_SATISFIED;
            } else {
                return true;
            }
        }

        pub fn waitCurrentReady(self: *const @This(), timeout: u64) !void {
            if (self.fences[self.current_buffer]) |fence| {
                const status = gl.clientWaitSync(fence, gl.SYNC_FLUSH_COMMANDS_BIT, timeout);
                if (status == gl.WAIT_FAILED) {
                    return error.WaitFailed;
                }
            }
        }

        pub fn getCurrent(self: *const @This()) []u8 {
            return self.buffers[self.current_buffer];
        }

        pub fn getCurrentAsSliceOf(self: *const @This(), comptime T: type) []T {
            return @ptrCast(@alignCast(self.buffers[self.current_buffer]));
        }

        pub fn getCurrentAsStruct(self: *const @This(), comptime S: type) *S {
            return std.mem.bytesAsValue(S, self.buffers[self.current_buffer]);
        }

        pub fn flushAndNext(self: *@This()) void {
            if (self.fences[self.current_buffer]) |*fence| {
                gl.deleteSync(fence.*);
                fence.* = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
            }
            self.current_buffer += (self.current_buffer + 1) % FrameCount;
        }
    };
}
