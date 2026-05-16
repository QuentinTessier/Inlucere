const std = @import("std");
const builtin = @import("builtin");
pub const gl = @import("gl4_6.zig");
pub const Device = @import("device.zig");
pub const Context = @import("context.zig");

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
    try gl.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    gl.enable(gl.DEBUG_OUTPUT);
    //gl.enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
    //gl.debugMessageCallback(DebugMessenger.callback, null);
}

pub fn deinit() void {
    // if (env.lib) |*lib| {
    //     lib.close();
    // }
}
