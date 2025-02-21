const gl = @import("../gl4_6.zig");

pub const Fence = @This();

handle: gl.GLSync,

pub fn init() Fence {
    return .{
        .handle = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0),
    };
}

pub fn deinit(self: Fence) void {
    gl.deleteSync(self.handle);
}

pub const Error = error{
    WaitFailed,
};

pub const Status = enum {
    Timeout,
    Success,
};

pub fn wait(self: Fence, timeout: u64) Error!Status {
    const res = gl.clientWaitSync(self.handle, 0, timeout);
    return switch (res) {
        gl.ALREADY_SIGNALED => .Success,
        gl.CONDITION_SATISFIED => .Success,
        gl.TIMEOUT_EXPIRED => .Timeout,
        gl.WAIT_FAILED => error.WaitFailed,
        else => unreachable,
    };
}
