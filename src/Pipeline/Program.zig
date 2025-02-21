const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const Stage = enum(u32) {
    Vertex = gl.VERTEX_SHADER,
    Fragment = gl.FRAGMENT_SHADER,
    TesselationControl = gl.TESS_CONTROL_SHADER,
    TesselationEvaluation = gl.TESS_EVALUATION_SHADER,

    Mesh = gl.GL_NV_mesh_shader.MESH_SHADER_NV,

    Compute = gl.COMPUTE_SHADER,
};

pub const StageBit = packed struct(u32) {
    Vertex: bool = false,
    Fragment: bool = false,
    TesselationControl: bool = false,
    TesselationEvaluation: bool = false,
    Mesh: bool = false,
    Compute: bool = false,
    _padding: u26 = 0,

    pub fn eql(self: StageBit, other: StageBit) bool {
        const s: u32 = @bitCast(self);
        const o: u32 = @bitCast(other);

        return s == o;
    }

    pub fn toGL(self: StageBit) u32 {
        var stages: u32 = 0;
        if (self.Vertex) stages |= gl.VERTEX_SHADER_BIT;
        if (self.Fragment) stages |= gl.FRAGMENT_SHADER_BIT;
        if (self.TesselationControl) stages |= gl.TESS_CONTROL_SHADER_BIT;
        if (self.TesselationEvaluation) stages |= gl.TESS_EVALUATION_SHADER_BIT;
        if (self.Mesh) stages |= gl.GL_NV_mesh_shader.MESH_SHADER_BIT_NV;

        return stages;
    }
};

pub const Program = @This();

handle: u32,
stage: StageBit,

pub const ShaderSource = struct {
    stage: Stage,
    source: []const u8,
};

pub fn compileShader(handle: u32, source: []const u8) !void {
    var length: i32 = @intCast(source.len);
    gl.shaderSource(handle, 1, @ptrCast(&source.ptr), &length);
    gl.compileShader(handle);

    var success: i32 = 0;
    gl.getShaderiv(handle, gl.COMPILE_STATUS, @ptrCast(&success));
    if (success != gl.TRUE) {
        var buffer: [1024]u8 = undefined;
        var l: i32 = 0;
        gl.getShaderInfoLog(handle, 1024, &l, (&buffer).ptr);
        std.log.err("{s}", .{buffer[0..@intCast(l)]});
        return error.FailedShaderCompilation;
    }
}

fn setStageBitField(self: *Program, stage: Stage) void {
    switch (stage) {
        .Vertex => self.stage.Vertex = true,
        .Fragment => self.stage.Fragment = true,
        .TesselationControl => self.stage.TesselationControl = true,
        .TesselationEvaluation => self.stage.TesselationEvaluation = true,
        .Mesh => self.stage.Mesh = true,
        .Compute => self.stage.Compute = true,
    }
}

pub fn init(self: *Program, shaders: []const ShaderSource) !void {
    self.handle = gl.createProgram();
    self.stage = .{};

    gl.programParameteri(self.handle, gl.PROGRAM_SEPARABLE, gl.TRUE);

    var tmp = std.BoundedArray(u32, 16){};
    defer {
        for (tmp.constSlice()) |handle| {
            gl.deleteShader(handle);
        }
    }
    for (shaders) |sh| {
        const n = gl.createShader(@intFromEnum(sh.stage));

        try compileShader(n, sh.source);
        self.setStageBitField(sh.stage);
        try tmp.append(n);

        gl.attachShader(self.handle, n);
    }

    gl.linkProgram(self.handle);
    {
        var success: i32 = 0;
        gl.getProgramiv(self.handle, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            var size: isize = 0;
            var buffer: [1024]u8 = undefined;
            gl.getProgramInfoLog(self.handle, 1024, @ptrCast(&size), (&buffer).ptr);
            std.log.err("Failed to link program: {s}", .{buffer[0..@intCast(size)]});
            return error.ProgramLinkingFailed;
        }
    }
}
