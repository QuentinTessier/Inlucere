const gl = @import("gl4_6.zig");

pub const Limits = @This();

max_uniform_buffer_bindings: i32,
max_uniform_block_size: i32,

uniform_buffer_offset_alignment: usize,
max_combined_uniform_block: i32,

max_shader_storage_buffer_bindings: i32,
max_shader_storage_block_size: i32,
shader_storage_buffer_offset_alignment: usize,

max_combined_shader_output_resources: i32,
max_combined_texture_image_units: i32,

pub fn query() Limits {
    var max_uniform_buffer_bindings: i32 = 0;
    var max_uniform_block_size: i32 = 0;
    var uniform_buffer_offset_alignment: i32 = 0;
    var max_combined_uniform_block: i32 = 0;
    var max_shader_storage_buffer_bindings: i32 = 0;
    var max_shader_storage_block_size: i32 = 0;
    var shader_storage_buffer_offset_alignment: i32 = 0;
    var max_combined_shader_output_resources: i32 = 0;
    var max_combined_texture_image_units: i32 = 0;

    gl.getIntegerv(gl.MAX_UNIFORM_BUFFER_BINDINGS, @ptrCast(&max_uniform_buffer_bindings));
    gl.getIntegerv(gl.MAX_UNIFORM_BLOCK_SIZE, @ptrCast(&max_uniform_block_size));
    gl.getIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, @ptrCast(&uniform_buffer_offset_alignment));
    gl.getIntegerv(gl.MAX_COMBINED_UNIFORM_BLOCKS, @ptrCast(&max_combined_uniform_block));
    gl.getIntegerv(gl.MAX_SHADER_STORAGE_BUFFER_BINDINGS, @ptrCast(&max_shader_storage_buffer_bindings));
    gl.getIntegerv(gl.MAX_SHADER_STORAGE_BLOCK_SIZE, @ptrCast(&max_shader_storage_block_size));
    gl.getIntegerv(gl.SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT, @ptrCast(&shader_storage_buffer_offset_alignment));
    gl.getIntegerv(gl.MAX_COMBINED_SHADER_OUTPUT_RESOURCES, @ptrCast(&max_combined_shader_output_resources));
    gl.getIntegerv(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS, @ptrCast(&max_combined_texture_image_units));

    return .{
        .max_uniform_buffer_bindings = max_uniform_buffer_bindings,
        .max_uniform_block_size = max_uniform_block_size,
        .uniform_buffer_offset_alignment = @intCast(uniform_buffer_offset_alignment),
        .max_combined_uniform_block = max_combined_uniform_block,
        .max_shader_storage_buffer_bindings = max_shader_storage_buffer_bindings,
        .max_shader_storage_block_size = max_shader_storage_block_size,
        .shader_storage_buffer_offset_alignment = @intCast(shader_storage_buffer_offset_alignment),
        .max_combined_shader_output_resources = max_combined_shader_output_resources,
        .max_combined_texture_image_units = max_combined_texture_image_units,
    };
}
