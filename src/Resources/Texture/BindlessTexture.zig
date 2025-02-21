const std = @import("std");
const gl = @import("../../gl4_6.zig");

const DeviceLogger = @import("../../Device.zig").DeviceLogger;

pub const BindlessTexture = @This();

handle: u64,

pub fn makeResident(self: BindlessTexture) void {
    DeviceLogger.info("Making bindless texture {} resident", .{self.handle});
    gl.GL_ARB_bindless_texture.makeTextureHandleResidentARB(self.handle);
}

pub fn makeNonResident(self: BindlessTexture) void {
    DeviceLogger.info("Making bindless texture {} non-resident", .{self.handle});
    gl.GL_ARB_bindless_texture.makeTextureHandleNonResidentARB(self.handle);
}

pub fn isResident(self: BindlessTexture) bool {
    return gl.GL_ARB_bindless_texture.isTextureHandleResidentARB(self.handle) == gl.TRUE;
}
