const std = @import("std");
const Inlucere = @import("../root.zig");

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

const cpu_vertices = [_]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };

vertices: Inlucere.Device.StaticBuffer,

pub fn init(device: *Inlucere.Device) !@This() {
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

    const gpu_vertices = Inlucere.Device.StaticBuffer.init(
        "triangle_vertices",
        std.mem.sliceAsBytes(&cpu_vertices),
        @sizeOf(f32) * 3,
    );

    return .{
        .vertices = gpu_vertices,
    };
}

pub fn deinit(self: *const @This()) void {
    self.vertices.deinit();
}

pub fn draw(self: *const @This(), device: *Inlucere.Device) void {
    if (device.bindGraphicPipeline("DefaultTrianglePipeline")) {
        device.bindVertexBuffer(0, self.vertices.toBuffer(), 0, null);
        device.draw(0, 3, 1, 1);
    }
}
