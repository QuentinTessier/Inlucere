const std = @import("std");
const gl = @import("gl4_6.zig");

pub const BarrierBits = packed struct(u32) {
    vertex_attrib: bool = false,
    index: bool = false,
    uniform: bool = false,
    texture_fetch: bool = false,
    image_access: bool = false,
    command: bool = false,
    pixel_buffer: bool = false,
    texture_update: bool = false,
    buffer_update: bool = false,
    framebuffer: bool = false,
    client_mapped: bool = false,
    ssbo: bool = false,
    _padding: u20 = 0,

    pub fn is_empty(self: BarrierBits) bool {
        return @as(u32, @bitCast(self)) == 0;
    }

    pub fn merge(self: BarrierBits, other: BarrierBits) BarrierBits {
        return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
    }

    pub fn flags(self: BarrierBits) u32 {
        var f: u32 = 0;

        f |= if (self.vertex_attrib) gl.VERTEX_ATTRIB_ARRAY_BARRIER_BIT else 0;
        f |= if (self.index) gl.ELEMENT_ARRAY_BARRIER_BIT else 0;
        f |= if (self.uniform) gl.UNIFORM_BARRIER_BIT else 0;
        f |= if (self.texture_fetch) gl.TEXTURE_FETCH_BARRIER_BIT else 0;
        f |= if (self.image_access) gl.SHADER_IMAGE_ACCESS_BARRIER_BIT else 0;
        f |= if (self.command) gl.COMMAND_BARRIER_BIT else 0;
        f |= if (self.pixel_buffer) gl.PIXEL_BUFFER_BARRIER_BIT else 0;
        f |= if (self.texture_update) gl.TEXTURE_UPDATE_BARRIER_BIT else 0;
        f |= if (self.buffer_update) gl.BUFFER_UPDATE_BARRIER_BIT else 0;
        f |= if (self.framebuffer) gl.FRAMEBUFFER_BARRIER_BIT else 0;
        f |= if (self.ssbo) gl.SHADER_STORAGE_BARRIER_BIT else 0;
        f |= if (self.client_mapped) gl.CLIENT_MAPPED_BUFFER_BARRIER_BIT else 0;

        return f;
    }
};
