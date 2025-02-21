const std = @import("std");
const gl = @import("../gl4_6.zig");

pub const DeviceLimit = @This();

maxUniformBufferBindings: i32,
maxUniformBlockSize: i32,
uniformBufferOffsetAligment: i32,
maxCombinedUniformBlock: i32,

maxShaderStorageBufferBindings: i32,
maxShaderStorageBlockSize: i32,
shaderStorageBufferOffsetAlignment: i32,

maxCombinedShaderOutputResources: i32,
maxCombinedTextureImageUnits: i32,

pub fn init() DeviceLimit {
    var self: DeviceLimit = undefined;

    gl.getIntegerv(gl.MAX_UNIFORM_BUFFER_BINDINGS, @ptrCast(&self.maxUniformBufferBindings));
    gl.getIntegerv(gl.MAX_UNIFORM_BLOCK_SIZE, @ptrCast(&self.maxUniformBlockSize));
    gl.getIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, @ptrCast(&self.uniformBufferOffsetAligment));
    gl.getIntegerv(gl.MAX_COMBINED_UNIFORM_BLOCKS, @ptrCast(&self.maxCombinedUniformBlock));
    gl.getIntegerv(gl.MAX_SHADER_STORAGE_BUFFER_BINDINGS, @ptrCast(&self.maxShaderStorageBufferBindings));
    gl.getIntegerv(gl.MAX_SHADER_STORAGE_BLOCK_SIZE, @ptrCast(&self.maxShaderStorageBlockSize));
    gl.getIntegerv(gl.SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT, @ptrCast(&self.shaderStorageBufferOffsetAlignment));
    gl.getIntegerv(gl.MAX_COMBINED_SHADER_OUTPUT_RESOURCES, @ptrCast(&self.maxCombinedShaderOutputResources));
    gl.getIntegerv(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS, @ptrCast(&self.maxCombinedTextureImageUnits));

    return self;
}
