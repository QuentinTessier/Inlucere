const std = @import("std");
const gl = @import("../gl4_6.zig");

const DeviceLogger = @import("../Device.zig").DeviceLogger;

pub const MessageSource = enum(u32) {
    api = gl.DEBUG_SOURCE_API,
    window_system = gl.DEBUG_SOURCE_WINDOW_SYSTEM,
    shader_compiler = gl.DEBUG_SOURCE_SHADER_COMPILER,
    third_party = gl.DEBUG_SOURCE_THIRD_PARTY,
    application = gl.DEBUG_SOURCE_APPLICATION,
    other = gl.DEBUG_SOURCE_OTHER,
};

pub const MessageType = enum(u32) {
    @"error" = gl.DEBUG_TYPE_ERROR,
    deprecated_behavior = gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR,
    undefined_behavior = gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR,
    portability = gl.DEBUG_TYPE_PORTABILITY,
    performance = gl.DEBUG_TYPE_PERFORMANCE,
    marker = gl.DEBUG_TYPE_MARKER,
    push_group = gl.DEBUG_TYPE_PUSH_GROUP,
    pop_group = gl.DEBUG_TYPE_POP_GROUP,
    other = gl.DEBUG_TYPE_OTHER,
};

pub const MessageSeverity = enum(u32) {
    high = gl.DEBUG_SEVERITY_HIGH,
    medium = gl.DEBUG_SEVERITY_MEDIUM,
    low = gl.DEBUG_SEVERITY_LOW,
    notification = gl.DEBUG_SEVERITY_NOTIFICATION,
};

pub fn callback(_source: gl.GLenum, _type: gl.GLenum, id: gl.GLuint, _severity: gl.GLenum, _: gl.GLsizei, message: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
    const source: []const u8 = switch (@as(MessageSource, @enumFromInt(_source))) {
        .api => "Api",
        .window_system => "WindowSystem",
        .shader_compiler => "ShaderCompiler",
        .third_party => "Third Party",
        .application => "Application",
        .other => "Other",
    };
    const t: []const u8 = switch (@as(MessageType, @enumFromInt(_type))) {
        .@"error" => "Error",
        .deprecated_behavior => "DeprecatedBehavior",
        .undefined_behavior => "UndefinedBehavior",
        .portability => "Protability",
        .performance => "Performance",
        .marker => "Marker",
        .push_group => "PushGroup",
        .pop_group => "PopGroup",
        .other => "Other",
    };
    DeviceLogger.info("{s} {s} {} {s}: {s}", .{ source, t, id, @tagName(@as(MessageSeverity, @enumFromInt(_severity))), message });

    // switch (@as(MessageSeverity, @enumFromInt(_severity))) {
    //     .high, .medium => {
    //         const severity = if (@as(MessageSeverity, @enumFromInt(_severity)) == .high) "High" else "Medium";
    //         DeviceLogger.err("{s} {s} {} {s}: {s}", .{ source, t, id, severity, message });
    //     },
    //     .low => {
    //         DeviceLogger.warn("{s} {s} {} {s}: {s}", .{ source, t, id, "Low", message });
    //     },
    //     .notification => {
    //         DeviceLogger.info("{s} {s} {} {s} : {s}", .{ source, t, id, "Notification", message });
    //     },
    // }
}
