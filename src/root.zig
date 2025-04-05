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
    requiredExtensions: std.BoundedArray(ExtensionSupport, 64) = .{},
};

var env: OpenGLEnv = .{};

const InternalLoadContext = struct {
    loadFunc: *const fn ([*:0]const u8) ?glFunctionPointer,
};

fn checkExtensionSupport() void {
    var n: i32 = 0;
    gl.getIntegerv(gl.NUM_EXTENSIONS, @ptrCast(&n));

    for (0..@intCast(n)) |index| {
        const ext = gl.getStringi(gl.EXTENSIONS, @intCast(index));
        if (ext) |name| {
            const len = std.mem.len(name);
            for (env.requiredExtensions.slice()) |*required| {
                if (std.mem.eql(u8, name[0..len], required.name)) {
                    required.isSupported = true;
                }
            }
        }
    }
}

fn internalLoadFunc(ctx: InternalLoadContext, name: [:0]const u8) ?glFunctionPointer {
    const wglPtr = ctx.loadFunc(name);
    return wglPtr;
}

pub fn init(comptime loadFunc: fn ([*:0]const u8) ?glFunctionPointer) !void {
    if (env.lib != null) return;

    if (builtin.target.os.tag == .windows) {
        env.lib = try std.DynLib.open("opengl32");
    } else if (builtin.target.os.tag == .linux) {
        env.lib = try std.DynLib.open("libGL.so.1");
    } else {
        @panic("Unsupported OS, file a issue or pull request to fix !");
    }
    try env.requiredExtensions.append(.{ .name = "GL_ARB_sparse_texture", .isSupported = false });
    try env.requiredExtensions.append(.{ .name = "GL_ARB_bindless_texture", .isSupported = false });
    // try env.requiredExtensions.append(.{ .name = "GL_NV_mesh_shader", .isSupported = false });
    // try env.requiredExtensions.append(.{ .name = "GL_EXT_semaphore", .isSupported = false });

    try gl.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    checkExtensionSupport();

    if (env.requiredExtensions.buffer[0].isSupported) {
        try gl.GL_ARB_sparse_texture.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    }

    if (env.requiredExtensions.buffer[1].isSupported) {
        try gl.GL_ARB_bindless_texture.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    }

    // if (env.requiredExtensions.buffer[2].isSupported) {
    //     try gl.GL_NV_mesh_shader.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    // }

    // if (env.requiredExtensions.buffer[3].isSupported) {
    //     try gl.GL_EXT_semaphore.load(InternalLoadContext{ .loadFunc = loadFunc }, internalLoadFunc);
    // }

    gl.enable(gl.DEBUG_OUTPUT);
    //gl.enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
    gl.debugMessageCallback(DebugMessenger.callback, null);
}

pub fn deinit() void {
    if (env.lib) |*lib| {
        lib.close();
    }
}
