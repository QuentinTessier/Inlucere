const gl = @import("../../gl4_6.zig");

pub const CompareOp = enum(u32) {
    never = gl.NEVER,
    less = gl.LESS,
    equal = gl.EQUAL,
    lessOrEqual = gl.LEQUAL,
    greater = gl.GREATER,
    notEqual = gl.NOTEQUAL,
    greaterOrEqual = gl.GEQUAL,
    always = gl.ALWAYS,
};

pub fn enableOrDisable(option: gl.GLenum, b: bool) void {
    if (b) {
        gl.enable(option);
    } else {
        gl.disable(option);
    }
}
