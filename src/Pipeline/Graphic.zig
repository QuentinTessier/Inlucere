const std = @import("std");
const gl = @import("../gl4_6.zig");
const Program = @import("Program.zig");

const DeviceLogger = @import("../Device.zig").DeviceLogger;

pub const PipelineVertexInputState = @import("./State/VertexInput.zig");
pub const PipelineInputAssemblyState = @import("./State/InputAssembly.zig");
pub const PipelineRasterizationState = @import("./State/Rasterization.zig");
pub const PipelineDepthState = @import("./State/Depth.zig");
pub const PipelineStencilState = @import("./State/Stencil.zig");
pub const PipelineColorBlendState = @import("./State/ColorBlend.zig");

pub const GraphicPipeline = @This();

pub const GraphicPipelineCreateInfo = struct {
    programs: []const []const u8,
    vertexInputState: PipelineVertexInputState,
    inputAssemblyState: PipelineInputAssemblyState = PipelineInputAssemblyState.default(),
    rasterizationState: PipelineRasterizationState = PipelineRasterizationState.default(),
    depthState: PipelineDepthState = PipelineDepthState.default(),
    stencilState: PipelineStencilState = PipelineStencilState.default(),
    colorBlendState: PipelineColorBlendState = PipelineColorBlendState.default(),
};

handle: u32,
vao: u32,

inputAssemblyState: PipelineInputAssemblyState,
rasterizationState: PipelineRasterizationState,
depthState: PipelineDepthState,
stencilState: PipelineStencilState,
colorBlendState: PipelineColorBlendState,

fn attachProgramStage(self: *GraphicPipeline, programs: *std.StringHashMapUnmanaged(Program), toAttach: []const []const u8) !bool {
    for (toAttach) |name| {
        const program: Program = programs.get(name) orelse {
            DeviceLogger.err("Failed to find program named {s}", .{name});
            return error.FailedToFindProgram;
        };

        const stage = program.stage.toGL();

        gl.useProgramStages(self.handle, stage, program.handle);
        DeviceLogger.info("New ProgramPipeline uses {s} for stage {}", .{ name, program.stage });
    }

    gl.validateProgramPipeline(self.handle);

    var status: i32 = 0;
    gl.getProgramPipelineiv(self.handle, gl.VALIDATE_STATUS, @ptrCast(&status));

    if (status != gl.TRUE) {
        var length: i32 = 0;
        gl.getProgramPipelineiv(self.handle, gl.INFO_LOG_LENGTH, @ptrCast(&length));
        if (length > 0) {
            var buffer: [1024]u8 = undefined;
            gl.getProgramPipelineInfoLog(self.handle, 1024, null, (&buffer).ptr);
            DeviceLogger.err("Failed to create ProgramPipeline:\n[{s}]", .{buffer[0..@intCast(length)]});
            return false;
        } else {
            DeviceLogger.err("Failed to create ProgramPipeline:\n[No error message]", .{});
            return false;
        }
        var size: isize = 0;
        var buffer: [1024]u8 = undefined;
        gl.getProgramPipelineInfoLog(self.handle, 1024, @ptrCast(&size), (&buffer).ptr);
        DeviceLogger.err("Failed to create ProgramPipeline:\n[{s}]", .{buffer[0..@intCast(size)]});
        return false;
    }

    return true;
}

pub fn init(self: *GraphicPipeline, programs: *std.StringHashMapUnmanaged(Program), createInfo: *const GraphicPipelineCreateInfo, vao: u32) !void {
    gl.genProgramPipelines(1, @ptrCast(&self.handle));
    if (!(try self.attachProgramStage(programs, createInfo.programs))) {
        return error.FailedToCreateProgram;
    }

    self.inputAssemblyState = createInfo.inputAssemblyState;
    self.rasterizationState = createInfo.rasterizationState;
    self.depthState = createInfo.depthState;
    self.stencilState = createInfo.stencilState;
    self.colorBlendState = createInfo.colorBlendState;

    self.vao = vao;
}

pub inline fn deinit(self: *GraphicPipeline) void {
    gl.deleteProgramPipelines(1, @ptrCast(&self.handle));
}

pub fn update(self: *const GraphicPipeline, other: *const GraphicPipeline) void {
    _ = .{ self, other };
    self.inputAssemblyState.update(other.inputAssemblyState);
    self.rasterizationState.update(other.rasterizationState);
    self.depthState.update(other.depthState);
    self.stencilState.update(other.stencilState);
    self.colorBlendState.update(other.colorBlendState);
}

pub fn force(self: *const GraphicPipeline) void {
    self.inputAssemblyState.force();
    self.rasterizationState.force();
    self.depthState.force();
    self.stencilState.force();
    self.colorBlendState.force();
}
