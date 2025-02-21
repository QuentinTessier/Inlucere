const gl = @import("../gl4_6.zig");

pub const Element = enum(u32) {
    u16 = gl.UNSIGNED_SHORT,
    u32 = gl.UNSIGNED_INT,

    pub fn byteSize(self: Element) usize {
        return switch (self) {
            .u16 => @sizeOf(u16),
            .u32 => @sizeOf(u32),
        };
    }

    pub fn toGL(self: Element) u32 {
        return @intFromEnum(self);
    }
};
