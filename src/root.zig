const std = @import("std");
pub const gl = @import("gl4_6.zig");
pub const Device = @import("Device.zig");
pub const DebugMessenger = @import("Debug/Messenger.zig");

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
    lib: *std.DynLib,
    loadFunc: *const fn (void, [:0]const u8) ?glFunctionPointer,
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
    const wglPtr = ctx.loadFunc(void{}, name);
    if (wglPtr) |ptr| {
        return ptr;
    } else {
        return ctx.lib.lookup(glFunctionPointer, name);
    }
}

pub fn init(comptime loadFunc: fn (void, [:0]const u8) ?glFunctionPointer) !void {
    if (env.lib != null) return;

    env.lib = try std.DynLib.open("opengl32.dll");
    try env.requiredExtensions.append(.{ .name = "GL_ARB_sparse_texture", .isSupported = false });
    try env.requiredExtensions.append(.{ .name = "GL_ARB_bindless_texture", .isSupported = false });
    try env.requiredExtensions.append(.{ .name = "GL_NV_mesh_shader", .isSupported = false });
    try env.requiredExtensions.append(.{ .name = "GL_EXT_semaphore", .isSupported = false });

    try gl.load(InternalLoadContext{ .lib = &env.lib.?, .loadFunc = loadFunc }, internalLoadFunc);
    checkExtensionSupport();

    if (env.requiredExtensions.buffer[0].isSupported) {
        try gl.GL_ARB_sparse_texture.load(InternalLoadContext{ .lib = &env.lib.?, .loadFunc = loadFunc }, internalLoadFunc);
    }

    if (env.requiredExtensions.buffer[1].isSupported) {
        try gl.GL_ARB_bindless_texture.load(InternalLoadContext{ .lib = &env.lib.?, .loadFunc = loadFunc }, internalLoadFunc);
    }

    if (env.requiredExtensions.buffer[2].isSupported) {
        try gl.GL_NV_mesh_shader.load(InternalLoadContext{ .lib = &env.lib.?, .loadFunc = loadFunc }, internalLoadFunc);
    }

    if (env.requiredExtensions.buffer[3].isSupported) {
        try gl.GL_EXT_semaphore.load(InternalLoadContext{ .lib = &env.lib.?, .loadFunc = loadFunc }, internalLoadFunc);
    }

    gl.enable(gl.DEBUG_OUTPUT);
    //gl.enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
    gl.debugMessageCallback(DebugMessenger.callback, null);
}

pub fn deinit() void {
    if (env.lib) |*lib| {
        lib.close();
    }
}
