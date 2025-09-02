const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");

pub const GPUContext = @This();

pub const InitData = struct {
    application_name: [*:0]const u8,
    application_version: u32,
    engine_name: [*:0]const u8,
    engine_version: u32,

    requested_extensions: []const [*:0]const u8,

    user_data: *anyopaque,
    get_instance_proc_address: *const fn (vk.Instance, [*:0]const u8) ?*anyopaque,
    create_surface: *const fn (*anyopaque, vk.Instance, *const vk.AllocationCallbacks, *vk.SurfaceKHR) vk.Result,
};

pub const PhysicalDeviceBundle = struct {
    device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    mem_properties: vk.PhysicalDeviceMemoryProperties,
};

pub const LogicalDeviceBundle = struct {
    device: vk.Device,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    transfer_queue: vk.Queue,
};

allocator: std.mem.Allocator,
base_wrapper: vk.BaseWrapper,
instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,

surface: vk.SurfaceKHR,

physical: PhysicalDeviceBundle,
logical: LogicalDeviceBundle,

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });

    return .false;
}

pub fn init(allocator: std.mem.Allocator, init_data: *const InitData) !GPUContext {
    var self: GPUContext = undefined;
    self.allocator = allocator;
    self.base_wrapper = vk.BaseWrapper.load(init_data.get_instance_proc_address);

    var extensions: std.ArrayList([*:0]const u8) = .empty;
    defer extensions.deinit(allocator);

    for (init_data.requested_extensions) |ext_name| {
        try extensions.append(allocator, ext_name);
    }
    try extensions.append(allocator, vk.extensions.ext_debug_utils.name);
    try extensions.append(allocator, vk.extensions.khr_portability_enumeration.name);
    try extensions.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);

    const instance = try self.base_wrapper.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = init_data.application_name,
            .application_version = init_data.application_version,
            .p_engine_name = init_data.engine_name,
            .engine_version = init_data.engine_version,
            .api_version = @bitCast(vk.API_VERSION_1_4),
        },
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = extensions.items.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
    }, null);

    const vki: *vk.InstanceWrapper = try allocator.create(vk.InstanceWrapper);
    errdefer allocator.destroy(vki);
    vki.* = vk.InstanceWrapper.load(instance, self.base_wrapper.dispatch.vkGetInstanceProcAddr);
    self.instance = vk.InstanceProxy.init(instance, vki);
    errdefer self.instance.destroyInstance(null);

    self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{
            //.verbose_bit_ext = true,
            //.info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
        .p_user_data = null,
    }, null);

    if (init_data.create_surface(init_data.user_data, instance, null, &self.surface) != .success) {
        return error.FailedToCreateSurface;
    }
    errdefer self.instance.destroySurfaceKHR(self.surface, null);
}
