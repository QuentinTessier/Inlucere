const gl = @import("../gl4_6.zig");

pub const MemoryBarrier = @This();

pub const Flags = packed struct(u32) {
    VertexAttribArrayBarrier: bool = false,
    ElementArrayBarrier: bool = false,
    UniformBarrier: bool = false,
    TextureFetchBarrier: bool = false,
    UNUSED: bool = false,
    ShaderImageAccessBarrier: bool = false,
    CommandBarrier: bool = false,
    PixelBufferBarrier: bool = false,
    TextureUpdateBarrier: bool = false,
    BufferUpdateBarrier: bool = false,
    FramebufferBarrier: bool = false,
    TransformFeedbackBarrier: bool = false,
    AtomicCounterBarrier: bool = false,
    ShaderStorageBarrier: bool = false,
    ClientMappedBufferBarrier: bool = false,
    QueryBufferBarrier: bool = false,
    _padding: u16 = 0,

    pub fn all() Flags {
        const value: u32 = 0xFFFFFFFF;
        return @bitCast(value);
    }
};
