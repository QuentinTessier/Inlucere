# Inlucere

Inlucere (to illuminate in latin) is a wrapper around OpenGL to make use a bit more straight forward. It is the graphics layer for my up coming engin Lucens.

⚠️ I wouldn't recommend using the project currently, quite a few breaking changes are coming with the development of Lucens.
⚠️ Current efforts are put towards making Inlucere a full frame graph API ! Hopefully abstracting some of the sync/barrier work and resource management :)

Currently the code isn't documented, I'll get to it soon ! (hopefully)

## Example - [LearnOpengl Default Triangle](https://learnopengl.com/Getting-started/Hello-Triangle)

For this example zig-gamedev's [zglfw](https://github.com/zig-gamedev/zglfw) was used.

Add Inlucere has a dependency to your zig project. We currently target zig 0.14.0.

build.zig
```zig
const inlucere = b.dependency("Inlucere", .{});
exe.root_module.addImport("Inlucere", inlucere.module("Inlucere"));
```

main.zig
```zig

const std = @import("std");
const glfw = @import("zglfw");
const Inlucere = @import("Inlucere");

const vertex_shader_source =
    \\#version 330 core
    \\layout (location = 0) in vec3 aPos;
    \\
    \\void main()
    \\{
    \\    gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    \\}
;

const fragment_shader_source =
    \\#version 330 core
    \\out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    \\} 
;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    const window = try glfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    glfw.makeContextCurrent(window);
    try Inlucere.init(glfw.getProcAddress);
    var device: Inlucere.Device = undefined;
    defer {
        device.deinit();
        Inlucere.deinit();
        window.destroy();
    }

    try device.init(gpa.allocator());

    _ = try device.loadShader("DefaultTriangleProgram", &.{
        .{ .stage = .Vertex, .source = vertex_shader_source },
        .{ .stage = .Fragment, .source = fragment_shader_source },
    });

    _ = try device.createGraphicPipeline("DefaultTrianglePipeline", &.{
        .programs = &.{
            "DefaultTriangleProgram",
        },
        .vertexInputState = .{
            .vertexAttributeDescription = &.{
                .{ .location = 0, .binding = 0, .inputType = .vec3 },
            },
        },
    });

    const vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };

    const gpu_vertices = Inlucere.Device.StaticBuffer.init(
        "triangle_vertices",
        std.mem.sliceAsBytes(&vertices),
        @sizeOf(f32) * 3,
    );
    defer gpu_vertices.deinit();

    while (!window.shouldClose()) {
        glfw.pollEvents();

        device.clearSwapchain(.{
            .colorLoadOp = .clear,
            .clearColor = .{ 1, 0, 0, 1 },
        });

        if (device.bindGraphicPipeline("DefaultTrianglePipeline")) {
            device.bindVertexBuffer(0, gpu_vertices.toBuffer(), 0, null);
            device.draw(0, 3, 1, 1);
        }

        window.swapBuffers();
    }
}

```
