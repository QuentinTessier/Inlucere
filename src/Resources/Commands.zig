const std = @import("std");

pub const CmdPushDebugGroupData = struct {
    id: i32,
    message: []const u8,
};

pub const CmdPopDebugGroupData = void;

pub const CmdClearData = struct {
    mask: u32,
};

pub fn CmdClearBuffer(comptime T: type) type {
    return struct {
        buffer: u32,
        draw_buffer: i32,
        values: [*]const T,
    };
}

pub fn CmdClearNamedFrameBuffer(comptime T: type) type {
    return struct {
        framebuffer: u32,
        buffer: u32,
        draw_buffer: i32,
        values: [*]const T,
    };
}

pub const CmdClearBufferIV = CmdClearBuffer(i32);
pub const CmdClearBufferUV = CmdClearBuffer(u32);
pub const CmdClearBufferFV = CmdClearBuffer(f32);

pub const CmdClearNamedFrameBufferIV = CmdClearNamedFrameBuffer(i32);
pub const CmdClearNamedFrameBufferUV = CmdClearNamedFrameBuffer(u32);
pub const CmdClearNamedFrameBufferFV = CmdClearNamedFrameBuffer(f32);
