const std = @import("std");
const gl = @import("../gl4_6.zig");
const VertexLayout = @import("graphic_pipeline.zig").VertexLayout;

pub fn hash(vertex_layout: *const VertexLayout) u64 {
    var h: std.hash.Wyhash = .init(0x0129302);

    h.update(std.mem.sliceAsBytes(vertex_layout.attributes));
    h.update(std.mem.sliceAsBytes(vertex_layout.binding));

    return h.final();
}

pub fn init(layout: *const VertexLayout) u32 {
    if (layout.attributes.len == 0 or layout.binding.len == 0) return 0;

    var handle: u32 = 0;
    gl.createVertexArrays(1, @ptrCast(&handle));

    for (layout.binding) |b| {
        gl.vertexArrayBindingDivisor(handle, b.binding, switch (b.input_rate) {
            .vertex => 0,
            .instance => 1,
        });
    }

    for (layout.attributes) |attr| {
        gl.enableVertexArrayAttrib(handle, attr.location);
        gl.vertexArrayAttribFormat(
            handle,
            attr.location,
            @intCast(attr.format.component_count),
            attr.format.component_type,
            if (attr.format.normalized) gl.TRUE else gl.FALSE,
            attr.offset,
        );
        gl.vertexArrayAttribBinding(handle, attr.location, attr.binding);
    }

    return handle;
}

pub fn destroy(handle: u32) void {
    gl.deleteVertexArrays(1, &handle);
}
