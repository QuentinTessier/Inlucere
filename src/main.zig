const std = @import("std");
const glfw = @import("glfw");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window = try glfw.createWindow(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    defer glfw.destroyWindow(window);

    glfw.makeContextCurrent(window);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        window.swapBuffers();
    }
}
