const std = @import("std");
const builtin = @import("builtin");
pub const gl = @import("gl4_6.zig");
pub const Device = @import("Device.zig");
pub const DebugMessenger = @import("Debug/Messenger.zig");
//pub const Examples = @import("Examples/examples.zig");

pub const glFunctionPointer = gl.FunctionPointer;

const ExtensionSupport = struct {
    name: []const u8,
    isSupported: bool,
};

const OpenGLEnv = struct {
    lib: ?std.DynLib = null,
};

var env: OpenGLEnv = .{};

const InternalLoadContext = struct {
    loadFunc: *const fn ([*:0]const u8) callconv(.c) ?glFunctionPointer,
};

fn internalLoadFunc(ctx: InternalLoadContext, name: [:0]const u8) ?glFunctionPointer {
    const wglPtr = ctx.loadFunc(name);
    return wglPtr;
}

pub fn init(comptime loadFunc: fn ([*:0]const u8) callconv(.c) ?glFunctionPointer) !void {
    if (env.lib != null) return;

    if (builtin.target.os.tag == .windows) {
        env.lib = try std.DynLib.open("opengl32");
    } else if (builtin.target.os.tag == .linux) {
        env.lib = try std.DynLib.open("libGL.so.1");
    } else {
        @panic("Unsupported OS, file a issue or pull request to fix !");
    }
    try gl.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    gl.enable(gl.DEBUG_OUTPUT);
    //gl.enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
    //gl.debugMessageCallback(DebugMessenger.callback, null);
}

pub fn deinit() void {
    if (env.lib) |*lib| {
        lib.close();
    }
}
