const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vk.zig");
const Inlucere = @import("Inlucere");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

extern fn glfwGetInstanceProcAddress(vk.Instance, [*:0]const u8) ?*anyopaque;
extern fn glfwCreateWindowSurface(vk.Instance, *glfw.Window, *const vk.AllocationCallbacks, *vk.SurfaceKHR) vk.Result;

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    const window = try glfw.createWindow(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    defer glfw.destroyWindow(window);

    const required = try glfw.getRequiredInstanceExtensions();

    var context: Inlucere.GPUContext = .init(allocator, &Inlucere.InitData{
        .application_name = "testbed",
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .engine_name = "testbed",
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .user_data = window,
        .requested_extensions = required,
        .get_instance_proc_address = glfwGetInstanceProcAddress,
        .create_surface = struct {
            pub fn inline_create_surface(user_data: *anyopaque, instance: vk.Instance, alloc_callback: *const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result {
                const w: *glfw.Window = @ptrCast(user_data);
                return glfwCreateWindowSurface(instance, w, alloc_callback, surface);
            }
        }.inline_create_surface,
    });

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
