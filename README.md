# Inlucere

Inlucere (to illuminate in latin) is a wrapper around OpenGL to make use a bit more straight forward. It is the graphics layer for my up coming engin Lucens.

⚠️ I wouldn't recommend using the project currently, quite a few breaking changes are coming with the development of Lucens.

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
const inlucere = @import("Inlucere");

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

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    var threaded: std.Io.Threaded = .init(init.gpa, .{});
    defer threaded.deinit();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    const window = try glfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    glfw.makeContextCurrent(window);

    try inlucere.init(glfw.getProcAddress);
    defer inlucere.deinit();

    var device: inlucere.Device = undefined;
    try device.init(init.gpa);
    defer device.deinit();

    var context: inlucere.Context = undefined;
    context.init(&device);
    defer context.deinit();

    try device.init(gpa.allocator());

    // Load the vertex shader code
    const vertex = try device.create_shader(&.{
        .source = vertex_shader_source,
        .stage = .vertex,
        .debug_name = "triangle.vert",
    });

    // Load the fragment shader code.
    const fragment = try device.create_shader(&.{
        .source = fragment_shader_source,
        .stage = .fragment,
        .debug_name = "triangle.frag",
    });

    // Create a graphics pipeline
    const pipeline = try device.create_graphics_pipeline(&.{
        .vertex_shader = vertex,
        .fragment_shader = fragment,
        .vertex_layout = .{
            .attributes = &.{
                .{ .location = 0, .binding = 0, .format = .f32x3, .offset = 0 },
            },
            .binding = &.{
                .{ .binding = 0, .stride = @sizeOf(f32) * 3, .input_rate = .vertex },
            },
        },
        .rasterizer_state = .{ .cull_mode = .none },
        .depth_stencil_state = .{
            .depth_test = false,
            .depth_write = false,
        },
        .blend_state = .{ .attachments = &.{.{}} },
        .color_attachment_formats = &.{.rgba8},
        .depth_format = null,
        .debug_name = "triangle.pipeline",
    });

    const vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };
    // We could upload the data directly from this call but we'll use a TransferEncoder.
    const vertices_buffer = try device.create_buffer(&.{
        .size = @sizeOf(f32) * 9,
        .usage = .vertex,
        .memory = .device_local,
        .debug_name = "triangle_vertices.buffer",
    });

    device.staging_buffers.begin_staging(); // This is the current pain point of using a TransferEncoder. This swap the current staging buffer ensure the next is available
    {
        // Create a TransferEncoder used to declare memory transfer from CPU -> GPU and GPU -> GPU (GPU -> CPU is planned with transform feedback, queries, ...)
        // It can be used to perform concurrent and synchronous write to a mapped GPU buffer or use staging memory and emit a GPU -> GPU copy.
        var enc = try context.begin_transfer_pass(&.{
            // Record a write to the buffer so the next pass can emit the right kind of barrier
            .buf(vertices_buffer, .update_write),
        });
        defer enc.end(threaded.io()); // Must be called to ensure that all concurrent work is done before emit OpenGL commands

        // Not very useful in this case but we can upload from a separate thread, on a single threaded build it will fallback to a simple @memcpy
        try enc.concurrent_upload_buffer(threaded.io(), vertices_buffer, 0, std.mem.sliceAsBytes(&vertices));
    }
    device.staging_buffers.end_staging();

    while (!window.shouldClose()) {
        glfw.pollEvents();

        {
            // Declare a graphics pass with its attachements (will build a framebuffer if target isn't .swapchain)
            // Framebuffer are cached on the handles of components. They require to be cleaned by hand for now.
            var enc = try context.begin_graphics_pass(.{
                .color = &.{
                    .{ .texture = .invalid, .load = .clear, .clear_value = .{ 0, 0, 0, 0 } },
                },
                .target = .swapchain,
            }, &.{});
            defer enc.end();

            enc.bind_pipeline(pipeline); // Bind a pipeline and its vertex array object
            enc.bind_vertex_buffer(0, vertices_buffer, 0); // Bind a vertex buffer at the right slot
            enc.draw(.triangle, 0, 3, 1, 0); // Request to draw 3 vertices
        }

        window.swapBuffers();
    }
}

```
