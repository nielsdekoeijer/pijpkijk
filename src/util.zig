const c = @import("c.zig").c;
const std = @import("std");
const QuadVertex = @import("types.zig").QuadVertex;
const BezierVertex = @import("types.zig").BezierVertex;
const TextVertex = @import("types.zig").TextVertex;
const Uniform = @import("types.zig").Uniform;
const WaylandHandle = @import("wayland.zig").WaylandHandle;
const handleError = @import("error.zig").handleError;

// =Generic============================================================================================================

/// Memcpy for generic non-slices, defers to zigs built in memcpy by casting pointers to slices. Likely slightly dodgy.
pub fn memcpy(dst: anytype, src: anytype, byteCount: usize) void {
    @memcpy(
        @as([*]u8, @ptrCast(dst))[0..byteCount],
        @as([*]u8, @ptrCast(@constCast(src)))[0..byteCount],
    );
}

// =VkInstance=========================================================================================================
// Creating a vulkan instance, where we are essentially registering ourselves with the vulkan libraries on the system.
// To do this, we must specify what features we wish to use, and some information about our application.

/// Debug callback injectable into vulkan
pub export fn vkDebugCallback(
    message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = message_severity;
    _ = message_type;
    _ = user_data;

    std.log.debug("\x1b[1m[validation layer]\x1b[0m {s}", .{std.mem.span(callback_data.*.pMessage)});
    return @as(c.VkBool32, 0);
}

/// Creates an arraylist of all supported vulkan extensions
fn getSupportedVkInstanceExtensions(
    allocator: std.mem.Allocator,
) !std.ArrayList([*:0]const u8) {
    std.log.debug("Trying to enumerate supported vulkan instance extensions...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan instance extensions failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateInstanceExtensionProperties(null, &count, null));
    std.log.debug("Vulkan reports '{}' instance extenions supported in total", .{count});

    const extension_properties = try allocator.alloc(c.VkExtensionProperties, count);
    defer allocator.free(extension_properties);
    try handleError(c.vkEnumerateInstanceExtensionProperties(null, &count, extension_properties.ptr));

    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, count);
    errdefer {
        for (extensions.items) |extension| allocator.free(std.mem.span(extension));
        extensions.deinit(allocator);
    }

    for (extension_properties) |extension_property| {
        const name = std.mem.sliceTo(&extension_property.extensionName, 0);
        std.log.debug("Support exists for instance extension '{s}'", .{name});
        const extension = try allocator.dupeZ(u8, name);
        errdefer allocator.free(extension);
        extensions.appendAssumeCapacity(extension);
    }

    defer std.log.debug("Trying to enumerate supported vulkan instance extensions OK", .{});
    return extensions;
}

/// Checks if the requested extensions are supported by vulkan
fn checkRequestedVkInstanceExtensionsSupported(
    allocator: std.mem.Allocator,
    requested_extensions: []const [*:0]const u8,
) !void {
    std.log.debug("Trying to check if requested vulkan instance extensions are supported...", .{});
    errdefer std.log.err("Trying to check if requested vulkan instance extensions are supported failed", .{});

    var supported_extensions = try getSupportedVkInstanceExtensions(allocator);
    defer {
        for (supported_extensions.items) |s| allocator.free(std.mem.span(s));
        supported_extensions.deinit(allocator);
    }

    // find each extension in the supported extension set
    for (requested_extensions) |requested| {
        var found = false;
        for (supported_extensions.items) |supported| {
            if (std.mem.eql(u8, std.mem.span(requested), std.mem.span(supported))) {
                found = true;
            }
        }

        if (!found) {
            std.log.err("Could not find requested instance extension with name {s}", .{requested});
            return error.VkErrorUnsupportedExtension;
        } else {
            std.log.debug("Found requested instance extension with name {s}", .{requested});
        }
    }

    defer std.log.debug("Trying to check if requested vulkan instance extensions are supported OK", .{});
}

/// Creates an arraylist of all supported instance layers
fn getSupportedVkInstanceLayers(
    allocator: std.mem.Allocator,
) !std.ArrayList([*:0]const u8) {
    std.log.debug("Trying to enumerate supported vulkan instance layers...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan instance layers failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateInstanceLayerProperties(&count, null));
    std.log.debug("Vulkan reports '{}' instance layers supported in total", .{count});

    const layer_properties = try allocator.alloc(c.VkLayerProperties, count);
    defer allocator.free(layer_properties);
    try handleError(c.vkEnumerateInstanceLayerProperties(&count, layer_properties.ptr));

    var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, count);
    errdefer {
        for (layers.items) |layer| allocator.free(std.mem.span(layer));
        layers.deinit(allocator);
    }

    for (layer_properties) |layer_property| {
        const name = std.mem.sliceTo(&layer_property.layerName, 0);
        std.log.debug("Support exists for instance layer '{s}'", .{name});
        const layer = try allocator.dupeZ(u8, name);
        errdefer allocator.free(layer);
        try layers.append(allocator, layer);
    }

    defer std.log.debug("Trying to enumerate supported vulkan instance layers OK", .{});
    return layers;
}

/// Check if requested layer extensions are supported
fn checkRequestedVkInstanceLayersSupported(
    allocator: std.mem.Allocator,
    requested_layers: []const [*:0]const u8,
) !void {
    std.log.debug("Trying to checking if requested vulkan layers are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan layers are supported failed", .{});

    var supported_layers = try getSupportedVkInstanceLayers(allocator);
    defer {
        for (supported_layers.items) |s| allocator.free(std.mem.span(s));
        supported_layers.deinit(allocator);
    }

    for (requested_layers) |requested| {
        var found = false;
        for (supported_layers.items) |supported| {
            if (std.mem.eql(u8, std.mem.span(requested), std.mem.span(supported))) {
                found = true;
            }
        }

        if (!found) {
            std.log.err("Could not find requested layer with name {s}", .{requested});
            return error.VkErrorUnsupportedLayer;
        } else {
            std.log.debug("Found requested layer with name {s}", .{requested});
        }
    }

    defer std.log.debug("Trying to checking if requested vulkan layers are supported OK", .{});
}

/// Initialize vulkan instance with our required features and details
pub fn initVkInstance(
    allocator: std.mem.Allocator,
) !c.VkInstance {
    var instance: c.VkInstance = undefined;

    std.log.info("Trying to init vulkan instance...", .{});
    errdefer std.log.err("Trying to init vulkan instance failed", .{});

    // create our list of requested instance extensions, which specifies non-standard features we wish to use
    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 0);
    defer extensions.deinit(allocator);

    try extensions.append(allocator, c.VK_KHR_SURFACE_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    if (@import("builtin").mode == .Debug) {
        try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }

    try checkRequestedVkInstanceExtensionsSupported(allocator, extensions.items);

    // create our list of requested instance layers, which can provide us debug information
    var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    if (@import("builtin").mode == .Debug) {
        try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
        try checkRequestedVkInstanceLayersSupported(allocator, layers.items);
    }

    // handler for debug, on release builds we disable the validation layers
    const debug_messenger = blk: {
        if (@import("builtin").mode == .Debug) {
            break :blk &c.VkDebugUtilsMessengerCreateInfoEXT{
                .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .pNext = null,
                .flags = 0,

                // messages we would like to let through
                .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,

                .pfnUserCallback = vkDebugCallback,

                // context for logging
                .pUserData = null,
            };
        } else {
            break :blk null;
        }
    };

    // create the instance
    try handleError(
        c.vkCreateInstance(&c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,

            // I create the logger for vulkan here
            .pNext = debug_messenger,

            // apparently this helps for portability, metalVK on macos etc.
            .flags = c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,

            // information about our app
            .pApplicationInfo = &c.VkApplicationInfo{
                .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pNext = null,
                .pApplicationName = "application",
                .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
                .pEngineName = "engine",
                .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
                .apiVersion = c.VK_API_VERSION_1_4,
            },

            // pass our layers
            .ppEnabledLayerNames = layers.items.ptr,
            .enabledLayerCount = @intCast(layers.items.len),

            // pass our extensions
            .ppEnabledExtensionNames = extensions.items.ptr,
            .enabledExtensionCount = @intCast(extensions.items.len),
        }, null, &instance),
    );
    errdefer deinitVkInstance(instance);

    defer std.log.info("Trying to init vulkan instance OK", .{});

    return instance;
}

/// Deinitialize vulkan instance
pub fn deinitVkInstance(
    instance: c.VkInstance,
) void {
    c.vkDestroyInstance(instance, null);

    defer std.log.info("Deinit vulkan instance OK", .{});
}

// =VkSurface==========================================================================================================
// The surface is the thing we draw onto.

/// Initialize vulkan surface from a wayland instance
pub fn initVkSurfaceWayland(
    instance: c.VkInstance,
    wayland_display: *c.struct_wl_display,
    wayland_surface: *c.struct_wl_surface,
) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;

    std.log.info("Trying to init vulkan surface...", .{});
    errdefer std.log.err("Trying to init vulkan surface failed", .{});

    const create_info = c.VkWaylandSurfaceCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .display = wayland_display,
        .surface = wayland_surface,
    };

    try handleError(c.vkCreateWaylandSurfaceKHR(instance, &create_info, null, &surface));

    defer std.log.info("Trying to init vulkan surface OK", .{});
    return surface;
}

/// Deinitialize vulkan surface from
pub fn deinitVkSurface(
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
) void {
    _ = instance;
    _ = surface;

    defer std.log.info("Deinit vulkan surface OK", .{});
}

// =VkPhysicalDevice===================================================================================================
// This specifies the specific gpu we want to use.

/// Initialize and select a vulkan physical device based on our requirements. If multiple GPUs meet our requirements,
/// select one based on somewhat ad-hoc criteria.
pub fn initVkPhysicalDevice(
    allocator: std.mem.Allocator,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
) !c.VkPhysicalDevice {
    var physical_device: c.VkPhysicalDevice = undefined;

    std.log.info("Trying to select vulkan physical device...", .{});
    errdefer std.log.err("Trying to select vulkan physical device failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumeratePhysicalDevices(instance, &count, null));
    std.log.debug("Vulkan reports '{}' physical devices in total", .{count});

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, count);
    defer allocator.free(physical_devices);
    try handleError(c.vkEnumeratePhysicalDevices(instance, &count, physical_devices.ptr));

    const physical_deviceScores = try allocator.alloc(usize, count);
    defer allocator.free(physical_deviceScores);

    for (0..count) |i| {
        var properties = c.VkPhysicalDeviceProperties{};
        c.vkGetPhysicalDeviceProperties(physical_devices[i], &properties);

        const typeName = blk: switch (properties.deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_OTHER => {
                break :blk "VK_PHYSICAL_DEVICE_TYPE_OTHER";
            },
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => {
                break :blk "VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU";
            },
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => {
                break :blk "VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU";
            },
            c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => {
                break :blk "VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU";
            },
            c.VK_PHYSICAL_DEVICE_TYPE_CPU => {
                break :blk "VK_PHYSICAL_DEVICE_TYPE_CPU";
            },
            else => {
                return error.VkUnknownPhysicalDeviceType;
            },
        };

        const deviceName = std.mem.sliceTo(&properties.deviceName, 0);
        const apiVersion = properties.apiVersion;
        std.log.debug(
            "Physical device found with name '{s}' of type '{s}' supporting Vulkan '{}.{}.{}'",
            .{
                deviceName,
                typeName,
                c.VK_API_VERSION_MAJOR(apiVersion),
                c.VK_API_VERSION_MINOR(apiVersion),
                c.VK_API_VERSION_PATCH(apiVersion),
            },
        );

        // we keep track of the scores to help us choose the device
        physical_deviceScores[i] = 0;

        // score based on device type
        switch (properties.deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_OTHER => {
                physical_deviceScores[i] += 0;
            },
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => {
                physical_deviceScores[i] += 2000;
            },
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => {
                physical_deviceScores[i] += 4000;
            },
            c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => {
                physical_deviceScores[i] += 1000;
            },
            c.VK_PHYSICAL_DEVICE_TYPE_CPU => {
                physical_deviceScores[i] += 1000;
            },
            else => {
                std.log.err("Unknown physical device type encountered with enum id '{}'", .{physical_deviceScores[i]});
                return error.VkUnknownPhysicalDeviceType;
            },
        }

        const queue_family_properties = try getQueueFamilyProperties(allocator, physical_devices[i]);
        defer allocator.free(queue_family_properties);

        // check for graphics bit
        var hasGraphicsBit = false;
        for (0..queue_family_properties.len) |j| {
            if (queue_family_properties[j].queueFlags & c.VK_QUEUE_GRAPHICS_BIT > 0) {
                hasGraphicsBit = true;
                break;
            }
        }

        if (!hasGraphicsBit) {
            std.log.debug("Physical with name '{s}' doesn't have VK_QUEUE_GRAPHICS_BIT", .{deviceName});
            physical_deviceScores[i] = 0;
        } else {
            std.log.debug("Physical with name '{s}' has VK_QUEUE_GRAPHICS_BIT", .{deviceName});
        }

        // check if the device can present on our surface
        var hasPresentSupport = false;
        for (0..queue_family_properties.len) |j| {
            var vkBoolHasPresentSupport: c.VkBool32 = 0;
            try handleError(
                c.vkGetPhysicalDeviceSurfaceSupportKHR(
                    physical_devices[i],
                    @intCast(j),
                    surface,
                    &vkBoolHasPresentSupport,
                ),
            );

            if (vkBoolHasPresentSupport > 0) {
                hasPresentSupport = true;
                break;
            }
        }

        if (!hasPresentSupport) {
            std.log.debug("Physical with name '{s}' doesn't support our surface", .{deviceName});
            physical_deviceScores[i] = 0;
        } else {
            std.log.debug("Physical with name '{s}' supports our surface", .{deviceName});
        }
    }

    var highestScore: usize = 0;
    var highestScoreIndex: usize = 0;
    for (0..count) |i| {
        if (physical_deviceScores[i] > highestScore) {
            highestScore = physical_deviceScores[i];
            highestScoreIndex = i;
        }
    }

    if (highestScore == 0) {
        std.log.err("No suitable physical devices found, highest score encountered was 0", .{});
        return error.VkNoSuitablePhysicalDevices;
    }

    physical_device = physical_devices[highestScoreIndex];

    // Small snippet just for printing
    var properties = c.VkPhysicalDeviceProperties{};
    c.vkGetPhysicalDeviceProperties(physical_devices[highestScoreIndex], &properties);
    std.log.info("Selecting physical device with name {s}", .{std.mem.sliceTo(&properties.deviceName, 0)});

    defer std.log.info("Trying to select vulkan physical device OK", .{});

    return physical_device;
}

// =VkSurfaceCapabilities==============================================================================================
// Describes some properties of our surface, such as the min, max and current size. Used in swapchain creation and
// window extend calculation.

pub fn getVkExtentFromWayland(
    handle: *WaylandHandle,
    capabilities: c.VkSurfaceCapabilitiesKHR,
) c.VkExtent2D {
    std.log.debug("Trying to get extent...", .{});
    errdefer std.log.err("Trying to get extent failed", .{});

    defer std.log.debug("Trying to get extent OK", .{});
    return c.VkExtent2D{
        .width = std.math.clamp(
            handle.state.width,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        ),
        .height = std.math.clamp(
            handle.state.height,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        ),
    };
}

/// Gets the surface capabilities of our physical device given the surface
pub fn getPhysicalDeviceSurfaceCapabilities(
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkSurfaceCapabilitiesKHR {
    std.log.debug("Trying to get surface capabilities...", .{});
    errdefer std.log.err("Trying to get surface capabilities failed", .{});

    var surfaceCapabilities = c.VkSurfaceCapabilitiesKHR{};
    try handleError(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        physical_device,
        surface,
        &surfaceCapabilities,
    ));

    defer std.log.debug("Trying to get surface capabilities OK", .{});
    return surfaceCapabilities;
}

// =VkSurfaceFormat====================================================================================================
// The Surface Format (VkSurfaceFormatKHR) dictates the format (layout of bits per pixel foramt) and the color space
// (the interpretation of the colors for display on the monitor). Used in swapchain, render pass, and image creation.

/// Get a list of surface formats supported by our physical device
fn getSupportedVkDeviceSurfaceFormats(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ![]c.VkSurfaceFormatKHR {
    std.log.debug("Trying to enumerate supported vulkan device surface formats...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device surface formats failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null));
    std.log.debug("Vulkan reports '{}' device surfaces formats in total", .{count});

    const surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, count);
    try handleError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, surface_formats.ptr));

    defer std.log.debug("Trying to enumerate supported vulkan device surface formats OK", .{});
    return surface_formats;
}

/// Select the preferred surface format from the supported formats. By default, we choose `VK_FORMAT_B8G8R8A8_SRGB`
/// and `VK_COLOR_SPACE_SRGB_NONLINEAR_KHR`. If the supported format is not there, we justs select the first one.
fn selectPreferredSurfaceFormat(
    supportedFormats: []c.VkSurfaceFormatKHR,
) c.VkSurfaceFormatKHR {
    std.log.debug("Trying to select vulkan surface format...", .{});
    errdefer std.log.err("Trying to select vulkan surface format failed", .{});

    for (supportedFormats) |format| {
        if (format.format == @as(c.VkFormat, @intCast(c.VK_FORMAT_B8G8R8A8_SRGB)) and
            format.colorSpace == @as(c.VkColorSpaceKHR, @intCast(c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)))
        {
            defer std.log.debug(
                "Selecting format with 'VK_FORMAT_B8G8R8A8_SRGB' and 'VK_COLOR_SPACE_SRGB_NONLINEAR_KHR'",
                .{},
            );

            defer std.log.debug("Trying to select vulkan surface format OK", .{});
            return format;
        }
    }

    defer std.log.debug("Preferred format not found, selecting first format we found", .{});

    defer std.log.debug("Trying to select vulkan surface format OK", .{});

    return supportedFormats[0];
}

/// Get a preferred surface format from the supported formats
pub fn getPreferredVkSurfaceFormat(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkSurfaceFormatKHR {
    var surface_format: c.VkSurfaceFormatKHR = undefined;

    std.log.debug("Trying to get preferred surface format...", .{});
    errdefer std.log.err("Trying to get preferred surface format failed", .{});

    const supportedSurfaceFormats = try getSupportedVkDeviceSurfaceFormats(allocator, physical_device, surface);
    defer allocator.free(supportedSurfaceFormats);

    surface_format = selectPreferredSurfaceFormat(supportedSurfaceFormats);

    defer std.log.debug("Trying to get preferred surface format OK", .{});

    return surface_format;
}

// =VkPresentMode======================================================================================================
// The Present mode dictates when and how the images you render are handed over to the monitor by the swapchain. Used
// during swapchain creation.

/// Get a list of present modes supported by our physical devices
fn getSupportedVkDeviceSurfacePresentModes(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ![]c.VkPresentModeKHR {
    std.log.info("Trying to enumerate supported vulkan device surface present modes...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device surface present modes failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null));
    std.log.debug("Vulkan reports '{}' device surfaces present modes in total", .{count});

    const surfacePresentModes = try allocator.alloc(c.VkPresentModeKHR, count);
    errdefer allocator.free(surfacePresentModes);

    try handleError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &count,
        surfacePresentModes.ptr,
    ));

    defer std.log.info("Trying to enumerate supported vulkan device surface present modes OK", .{});
    return surfacePresentModes;
}

/// Select the preferred present mode from the supported formats. By default, we choose `VK_PRESENT_MODE_MAILBOX_KHR`
/// which is triple buffering. As a backup, we choose `VK_PRESENT_MODE_FIFO_KHR` which is vsync, which should always
/// work.
fn selectPreferredSurfacePresentMode(
    supported_present_modes: []c.VkPresentModeKHR,
) c.VkPresentModeKHR {
    std.log.info("Trying to select vulkan swapchain present mode...", .{});
    errdefer std.log.err("Trying to select vulkan swapchain present mode failed", .{});

    var selected_mode: c.VkPresentModeKHR = undefined;
    for (supported_present_modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            defer std.log.debug("Selecting present mode 'VK_PRESENT_MODE_MAILBOX_KHR'", .{});
            selected_mode = mode;

            defer std.log.info("Trying to select vulkan swapchain present mode OK", .{});
            return selected_mode;
        }
    }

    // Note that this is ALWAYS availible.
    selected_mode = c.VK_PRESENT_MODE_FIFO_KHR;
    defer std.log.debug("Selecting present mode 'VK_PRESENT_MODE_FIFO_KHR'", .{});

    defer std.log.info("Trying to select vulkan swapchain present mode OK", .{});
    return selected_mode;
}

/// Get a preferred present mode
pub fn getPreferredVkPresentMode(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkPresentModeKHR {
    var present_mode: c.VkPresentModeKHR = undefined;

    std.log.debug("Trying to get preferred surface format...", .{});
    errdefer std.log.err("Trying to get preferred surface format failed", .{});

    const supported_present_modes = try getSupportedVkDeviceSurfacePresentModes(
        allocator,
        physical_device,
        surface,
    );
    defer allocator.free(supported_present_modes);

    present_mode = selectPreferredSurfacePresentMode(supported_present_modes);

    defer std.log.debug("Trying to get preferred surface format OK", .{});

    return present_mode;
}

// =VkQueueFamilies====================================================================================================
// In vulkan, if we want to interact with the physical device, it is done so through queues. We essentially submit
// commands to queues, and the queue families indicate which queues are availible. Used in device creation to tell
// vulkan which queues we want, in swapchain creation to determine the image sharing mode, and in command pool
// creation.

/// Get all availible queue family properties
fn getQueueFamilyProperties(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    std.log.debug("Trying to get all queue family properties...", .{});
    errdefer std.log.err("Trying to get all queue family properties failed", .{});

    var count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
    const queue_family_properties = try allocator.alloc(c.VkQueueFamilyProperties, count);
    errdefer allocator.free(queue_family_properties);
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, queue_family_properties.ptr);

    defer std.log.debug("Trying to get all queue family properties OK", .{});
    return queue_family_properties;
}

/// Find the first graphics queue index from the properties
pub fn findGraphicsQueueIndex(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) !u32 {
    std.log.debug("Trying to get graphics queue index...", .{});
    errdefer std.log.err("Trying to get graphics queue index failed", .{});

    const queue_family_properties = try getQueueFamilyProperties(allocator, physical_device);
    defer allocator.free(queue_family_properties);

    var graphics_queue_index: u32 = 0;
    var graphicsQueueFound = false;
    for (0..queue_family_properties.len) |i| {
        if (queue_family_properties[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT > 0) {
            graphics_queue_index = @intCast(i);
            graphicsQueueFound = true;
            break;
        }
    }

    if (!graphicsQueueFound) {
        std.log.err("Could not find queue with graphics bit set", .{});
        return error.VkQueueNotFound;
    }

    std.log.debug("Using graphics queue index '{}'", .{graphics_queue_index});

    defer std.log.debug("Trying to get graphics queue index OK", .{});
    return graphics_queue_index;
}

/// Find the first present queue index from the properties
pub fn findPresentQueueIndex(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    physical_device: c.VkPhysicalDevice,
) !u32 {
    std.log.debug("Trying to get present queue index...", .{});
    errdefer std.log.err("Trying to get present queue index failed", .{});

    const queue_family_properties = try getQueueFamilyProperties(allocator, physical_device);
    defer allocator.free(queue_family_properties);

    var present_queue_index: u32 = 0;
    var presentQueueFound = false;
    for (0..queue_family_properties.len) |j| {
        var vkBoolHasPresentSupport: c.VkBool32 = 0;
        try handleError(c.vkGetPhysicalDeviceSurfaceSupportKHR(
            physical_device,
            @intCast(j),
            surface,
            &vkBoolHasPresentSupport,
        ));
        if (vkBoolHasPresentSupport > 0) {
            present_queue_index = @intCast(j);
            presentQueueFound = true;
            break;
        }
    }

    if (!presentQueueFound) {
        std.log.err("Could not find queue with present bit set", .{});
        return error.VkQueueNotFound;
    }

    std.log.debug("Using present queue index '{}'", .{present_queue_index});

    defer std.log.debug("Trying to get present queue index OK", .{});
    return present_queue_index;
}

// =VkDevice===========================================================================================================
// This is the logical device which we use to interface with the physical device. It describes the features we want to
// use from the physical device.

/// Gets a list of all supported vulkan device layers
fn getSupportedVkDeviceLayers(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) !std.ArrayList([*:0]const u8) {
    std.log.debug("Trying to enumerate supported vulkan device layers...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device layers failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateDeviceLayerProperties(physical_device, &count, null));
    std.log.debug("Vulkan reports '{}' device layers supported in total", .{count});

    const layer_properties = try allocator.alloc(c.VkLayerProperties, count);
    defer allocator.free(layer_properties);
    try handleError(c.vkEnumerateDeviceLayerProperties(physical_device, &count, layer_properties.ptr));

    var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, count);
    errdefer {
        for (layers.items) |ext| allocator.free(std.mem.span(ext));
        layers.deinit(allocator);
    }

    for (layer_properties) |layer_property| {
        const name = try allocator.dupeZ(u8, std.mem.sliceTo(&layer_property.layerName, 0));
        errdefer allocator.free(name);

        std.log.debug("Support exists for device layer '{s}'", .{name});

        try layers.append(allocator, name);
    }

    defer std.log.debug("Trying to enumerate supported vulkan device layers OK", .{});
    return layers;
}

/// Checks if the requested device layers are supported
fn checkRequestedVkDeviceLayersSupported(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    requested_layers: []const [*:0]const u8,
) !void {
    std.log.debug("Trying to checking if requested vulkan layers are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan layers are supported failed", .{});

    // note that we own the memory here
    var supported_layers = try getSupportedVkDeviceLayers(allocator, physical_device);
    defer {
        for (supported_layers.items) |s| allocator.free(std.mem.span(s));
        supported_layers.deinit(allocator);
    }

    for (requested_layers) |requested| {
        var found = false;
        for (supported_layers.items) |supported| {
            if (std.mem.eql(u8, std.mem.span(requested), std.mem.span(supported))) {
                found = true;
            }
        }

        if (!found) {
            std.log.err("Could not find requested layer with name {s}", .{requested});
            return error.VkErrorUnsupportedLayer;
        } else {
            std.log.debug("Found requested layer with name {s}", .{requested});
        }
    }

    defer std.log.debug("Trying to checking if requested vulkan layers are supported OK", .{});
}

/// Gets a list of all supported device extensions
fn getSupportedVkDeviceExtensions(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) !std.ArrayList([*:0]const u8) {
    std.log.debug("Trying to enumerate supported vulkan device extensions...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device extensions failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateDeviceExtensionProperties(physical_device, null, &count, null));
    std.log.debug("Vulkan reports '{}' device extenions supported in total", .{count});

    const extension_properties = try allocator.alloc(c.VkExtensionProperties, count);
    defer allocator.free(extension_properties);
    try handleError(c.vkEnumerateDeviceExtensionProperties(
        physical_device,
        null,
        &count,
        extension_properties.ptr,
    ));

    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, count);
    for (extension_properties) |extension_property| {
        const name = std.mem.sliceTo(&extension_property.extensionName, 0);
        std.log.debug("Support exists for device extension '{s}'", .{name});
        try extensions.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan device extensions OK", .{});
    return extensions;
}

/// Checks if the requested device extensions are supported
fn checkRequestedVkDeviceExtensionsSupported(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    requested_extensions: []const [*:0]const u8,
) !void {
    std.log.debug("Trying to checking if requested vulkan device extensions are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan device extensions are supported failed", .{});

    // note that we own the memory here
    var supportedExtensions = try getSupportedVkDeviceExtensions(allocator, physical_device);
    defer {
        for (supportedExtensions.items) |s| allocator.free(std.mem.span(s));
        supportedExtensions.deinit(allocator);
    }

    for (requested_extensions) |requested| {
        var found = false;
        for (supportedExtensions.items) |supported| {
            if (std.mem.eql(u8, std.mem.span(requested), std.mem.span(supported))) {
                found = true;
            }
        }

        if (!found) {
            std.log.err("Could not find requested device extension with name {s}", .{requested});
            return error.VkErrorUnsupportedExtension;
        } else {
            std.log.debug("Found requested device extenion name {s}", .{requested});
        }
    }

    defer std.log.debug("Trying to checking if requested vulkan device extensions are supported OK", .{});
}

/// Initializes a handle to the physical device and create the device queues we want.
pub fn initVkDevice(
    allocator: std.mem.Allocator,
    graphics_queue_index: u32,
    present_queue_index: u32,
    physical_device: c.VkPhysicalDevice,
) !c.VkDevice {
    var device: c.VkDevice = undefined;

    std.log.info("Trying to init vulkan device...", .{});
    errdefer std.log.err("Trying to init vulkan device failed", .{});

    // create our list of requested instance extensions
    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 0);
    defer extensions.deinit(allocator);
    try extensions.append(allocator, c.VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_KHR_EXTERNAL_FENCE_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_KHR_EXTERNAL_FENCE_FD_EXTENSION_NAME);
    try checkRequestedVkDeviceExtensionsSupported(allocator, physical_device, extensions.items);

    // create our list of requested instance layers
    var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    if (@import("builtin").mode == .Debug) {
        try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
        try checkRequestedVkDeviceLayersSupported(allocator, physical_device, layers.items);
    }

    // populate queue families
    const queuePriorities: f32 = 1.0;
    var queueFamilyCreateInfos = try std.ArrayList(c.VkDeviceQueueCreateInfo).initCapacity(allocator, 0);
    defer queueFamilyCreateInfos.deinit(allocator);

    // graphics queue family
    try queueFamilyCreateInfos.append(allocator, c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = graphics_queue_index,
        .queueCount = 1,
        .pQueuePriorities = &queuePriorities,
    });

    // present queue family
    if (present_queue_index != graphics_queue_index) {
        try queueFamilyCreateInfos.append(allocator, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = present_queue_index,
            .queueCount = 1,
            .pQueuePriorities = &queuePriorities,
        });
    }

    // create device
    try handleError(c.vkCreateDevice(
        physical_device,
        &c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,

            // specify queue families to create, where we can later retrieve a handle for
            .pQueueCreateInfos = queueFamilyCreateInfos.items.ptr,
            .queueCreateInfoCount = @intCast(queueFamilyCreateInfos.items.len),

            // layers to enable
            .ppEnabledLayerNames = layers.items.ptr,
            .enabledLayerCount = @intCast(layers.items.len),

            // extensions to enable
            .ppEnabledExtensionNames = extensions.items.ptr,
            .enabledExtensionCount = @intCast(extensions.items.len),

            // features to enable
            .pEnabledFeatures = &c.VkPhysicalDeviceFeatures{
                .samplerAnisotropy = c.VK_TRUE,
            },
        },
        null,
        &device,
    ));

    defer std.log.info("Trying to init vulkan device OK", .{});
    return device;
}

/// Deinitializes a handle to the physical device
pub fn deinitVkDevice(device: c.VkDevice) void {
    c.vkDestroyDevice(device, null);

    defer std.log.info("Deinit vulkan device OK", .{});
}

// =VkSwapchain========================================================================================================
// The swapchain is the agreement between Vulkan and your operating system on how the pixels should be displayed.
// Provides the images that we draw on.

/// Initializes a vulkan swap chain with our given configuration
pub fn initVkSwapchain(
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    swap_extent: c.VkExtent2D,
    present_mode: c.VkPresentModeKHR,
    graphics_queue_index: u32,
    present_queue_index: u32,
    previous_swapchain: c.VkSwapchainKHR,
) !c.VkSwapchainKHR {
    var swapchain: c.VkSwapchainKHR = undefined;

    std.log.info("Trying to init vulkan swapchain...", .{});
    errdefer std.log.err("Trying to init vulkan swapchain failed", .{});

    //
    const image_sharing_mode: u32 = blk: {
        if (graphics_queue_index != present_queue_index) {
            break :blk c.VK_SHARING_MODE_CONCURRENT;
        } else {
            break :blk c.VK_SHARING_MODE_EXCLUSIVE;
        }
    };

    const queue_family_index_count: u32 = blk: {
        if (graphics_queue_index != present_queue_index) {
            break :blk 2;
        } else {
            break :blk 0;
        }
    };

    const queue_pair = [_]u32{ graphics_queue_index, present_queue_index };
    const queue_family_indices: [*c]const u32 = blk: {
        if (graphics_queue_index != present_queue_index) {
            break :blk &queue_pair;
        } else {
            break :blk null;
        }
    };

    // initialize
    try handleError(c.vkCreateSwapchainKHR(device, &c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = surface,
        // minimum amount of images required by the surface
        .minImageCount = surface_capabilities.minImageCount,
        // memory layout of the colors of the image
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        // size of our window
        .imageExtent = swap_extent,
        // only 2 for e.g. VR
        .imageArrayLayers = 1,
        // tell the GPU we intend to draw onto the image
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        // if we need to account (synchronization wise) for the two queues to be the same (faster if not)
        .imageSharingMode = @intCast(image_sharing_mode),
        .queueFamilyIndexCount = @intCast(queue_family_index_count),
        .pQueueFamilyIndices = queue_family_indices,
        // e.g. rotate the image or not, we leave it the same
        .preTransform = surface_capabilities.currentTransform,
        // if the window itself is see through, e.g. for a terminal with transparency
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        // triple buffering or vsync, etc.
        .presentMode = present_mode,
        // skip running fragment shader for obscured pixels
        .clipped = c.VK_TRUE,
        // for re-use of system resources
        .oldSwapchain = previous_swapchain,
    }, null, &swapchain));

    defer std.log.info("Trying to init vulkan swapchain OK", .{});
    return swapchain;
}

/// Deinitializes a vulkan swap chain
pub fn deinitVkSwapchain(
    device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
) void {
    c.vkDestroySwapchainKHR(device, swapchain, null);
    defer std.log.info("Deinit vulkan swapchain OK", .{});
}

// =VkImages===========================================================================================================
// Images are that which we draw on, an image view references a specific part of an image to be used

/// Initializes handle to the image inside the swapchain. The image can be understood to be the raw memory on the GPU.
pub fn initVkImages(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
) ![]c.VkImage {
    std.log.info("Trying to get images...", .{});
    errdefer std.log.info("Trying to get images failed", .{});

    var count: u32 = undefined;
    try handleError(c.vkGetSwapchainImagesKHR(device, swapchain, &count, null));
    const images = try allocator.alloc(c.VkImage, count);
    try handleError(c.vkGetSwapchainImagesKHR(device, swapchain, &count, images.ptr));

    std.log.info("Acquired {} images", .{count});

    defer std.log.info("Trying to get images...", .{});
    return images;
}

pub fn deinitVkImages(
    allocator: std.mem.Allocator,
    images: []c.VkImage,
) void {
    defer allocator.free(images);

    defer std.log.info("Deinit images OK", .{});
}

/// Initializes views to images. The view adds an interpretation to the image through the surface format.
pub fn initVkImageViews(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    images: []c.VkImage,
    surface_format: c.VkSurfaceFormatKHR,
) ![]c.VkImageView {
    std.log.info("Trying to get image views...", .{});
    errdefer std.log.info("Trying to get image views failed", .{});

    const image_views = try allocator.alloc(c.VkImageView, images.len);
    for (0..images.len) |i| {
        try handleError(
            c.vkCreateImageView(device, &c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .image = images[i],
                // Treat image memory as a 2D image
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                // Forward our format
                .format = surface_format.format,
                // Hot-swap the colors as you read them, can be useful e.g. for a monochrome effect apparently
                .components = c.VkComponentMapping{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = c.VkImageSubresourceRange{
                    // This is a view into the color part, could also be for example the stencil or depth parts!
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            }, null, &image_views[i]),
        );
    }

    defer std.log.info("Trying to get image views OK", .{});
    return image_views;
}

/// Deinitializes views to images
pub fn deinitVkImageViews(allocator: std.mem.Allocator, device: c.VkDevice, image_views: []c.VkImageView) void {
    for (0..image_views.len) |i| {
        c.vkDestroyImageView(device, image_views[i], null);
    }
    allocator.free(image_views);

    defer std.log.info("Deinit image views OK", .{});
}

// =VkPipeline=========================================================================================================
// Describes the configurable state of the graphics card, like the viewport size and depth buffer operation and the
// programmable state using shaders.

/// Initialize a shader
pub fn initVkShaderModule(comptime path: anytype, device: c.VkDevice) !c.VkShaderModule {
    var shader_module: c.VkShaderModule = undefined;

    std.log.info("Trying to init shader module with path '{s}'...", .{path});
    errdefer std.log.info("Trying to init shader module with path '{s}' failed", .{path});

    const code align(@alignOf(u32)) = @embedFile(path).*;

    try handleError(
        c.vkCreateShaderModule(device, &c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = code.len,
            .pCode = std.mem.bytesAsSlice(u32, &code).ptr,
        }, null, &shader_module),
    );

    defer std.log.info("Trying to init shader module with path '{s}' OK", .{path});
    return shader_module;
}

/// Deinitialize a shader
pub fn deinitVkShaderModule(
    device: c.VkDevice,
    shader_module: c.VkShaderModule,
) void {
    c.vkDestroyShaderModule(device, shader_module, null);

    defer std.log.info("Deinit vulkan shader module OK", .{});
}

/// Initializes render passes, describes how the graphics pipeline will interact with the framebuffer.
pub fn initVkRenderPass(
    device: c.VkDevice,
    surface_format: c.VkSurfaceFormatKHR,
) !c.VkRenderPass {
    var render_pass: c.VkRenderPass = undefined;

    std.log.info("Trying to init render pass...", .{});
    errdefer std.log.info("Trying to init render pass failed", .{});

    try handleError(
        c.vkCreateRenderPass(device, &c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .attachmentCount = 1,
            // Canvassas we will draw on. One can have mutliple in the case of e.g. a depth buffer, deferred
            // rendering, multi-sample anti-aliasing, or post processing like bloom.
            .pAttachments = &[_]c.VkAttachmentDescription{
                c.VkAttachmentDescription{
                    .flags = 0,
                    // Forward the format
                    .format = surface_format.format,
                    // Number of samples to write, multiple samples used e.g. for anti-aliasing
                    .samples = c.VK_SAMPLE_COUNT_1_BIT,
                    // What to do BEFORE we start drawing
                    .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                    // What to do AFTER we finish drawing
                    .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                    // Stencil buffer behaviour
                    .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                    .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                    // The layout how it starts, in this case we say we don't care
                    .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                    // The layout how it should be at the end, in this case presenting
                    .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                },
            },
            .subpassCount = 1,
            // GPU can do multiple passes, they are specified here
            .pSubpasses = &[_]c.VkSubpassDescription{
                c.VkSubpassDescription{
                    .flags = 0,
                    // Specify the type of pipeline, compute or graphics (or raytracing for example)
                    .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    // For reading from a pass before our render pass
                    .inputAttachmentCount = 0,
                    .pInputAttachments = null,
                    // Specify what attachement we will attach to, specified above
                    .colorAttachmentCount = 1,
                    .pColorAttachments = &c.VkAttachmentReference{
                        .attachment = 0,
                        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    },
                    // How to resolve e.g. 4 samples down to 1 (e.g. MSAA)
                    .pResolveAttachments = null,
                    .pDepthStencilAttachment = null,
                    .preserveAttachmentCount = 0,
                    // Attachments that the current subpass is not using, but may be used by other subpasses, thus need
                    // be preserved.
                    .pPreserveAttachments = null,
                },
            },
            .dependencyCount = 1,
            // To do with synchronization, to ensure vulkan doesn't overwrite what e.g. the monitor is still reading.
            .pDependencies = &c.VkSubpassDependency{
                .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass = 0,
                .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
                .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .srcAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                .dependencyFlags = 0,
            },
        }, null, &render_pass),
    );

    defer std.log.info("Trying to init render pass OK", .{});
    return render_pass;
}

/// Deinitializes a render pass
pub fn deinitVkRenderPass(
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
) void {
    c.vkDestroyRenderPass(device, render_pass, null);

    defer std.log.info("Deinit vulkan render pass OK", .{});
}

/// Intializes a descriptor set, which specifies the external data to be used by our shaders, e.g. UBOs, push
/// constants, and textures.
pub fn initVkDescriptorSetLayout(
    device: c.VkDevice,
) !c.VkDescriptorSetLayout {
    var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

    std.log.info("Trying to init vulkan descriptor set layout...", .{});
    errdefer std.log.err("Trying to init vulkan descriptor set layout", .{});

    try handleError(c.vkCreateDescriptorSetLayout(
        device,
        &c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .bindingCount = 2,
            .pBindings = &[_]c.VkDescriptorSetLayoutBinding{
                c.VkDescriptorSetLayoutBinding{
                    .binding = 0,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = 1,
                    .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .pImmutableSamplers = null,
                },
                c.VkDescriptorSetLayoutBinding{
                    .binding = 1,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .descriptorCount = 1,
                    .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .pImmutableSamplers = null,
                },
            },
        },
        null,
        &descriptor_set_layout,
    ));

    defer std.log.info("Trying to init vulkan descriptor set layout OK", .{});
    return descriptor_set_layout;
}

/// Deinitializes descriptor sets
pub fn deinitVkDescriptorSetLayout(device: c.VkDevice, descriptor_set_layout: c.VkDescriptorSetLayout) void {
    c.vkDestroyDescriptorSetLayout(device, descriptor_set_layout, null);
    std.log.info("Deinit descriptor set layout OK", .{});
}

/// Intialize the pipeline layout
pub fn initVkPipelineLayout(
    device: c.VkDevice,
    descriptor_set_layout: c.VkDescriptorSetLayout,
) !c.VkPipelineLayout {
    var pipeline_layout: c.VkPipelineLayout = undefined;

    std.log.info("Trying to init pipeline layout...", .{});
    errdefer std.log.info("Trying to init pipeline layout failed", .{});

    try handleError(c.vkCreatePipelineLayout(
        device,
        &c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_set_layout,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        },
        null,
        &pipeline_layout,
    ));

    defer std.log.info("Trying to init pipeline layout OK", .{});
    return pipeline_layout;
}

/// Deinitialize the pipeline layout
pub fn deinitVkPipelineLayout(
    device: c.VkDevice,
    pipeline_layout: c.VkPipelineLayout,
) void {
    c.vkDestroyPipelineLayout(device, pipeline_layout, null);
    defer std.log.info("Deinit vulkan pipeline layout OK", .{});
}

// =SpecificPipelines==================================================================================================
// We have multiple pipelines to draw our setup. They overlap greatly, but I have seperated them in seperate functions
// in order to maximize flexibility. Probably not needed though.

/// Pipeline for drawing the nodes
pub fn initQuadVertexVkGraphicsPipeline(
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
    pipeline_layout: c.VkPipelineLayout,
    shader_module_vert: c.VkShaderModule,
    shader_module_frag: c.VkShaderModule,
) !c.VkPipeline {
    var vkGraphicsPipeline: c.VkPipeline = undefined;

    std.log.info("Trying to init graphics pipeline...", .{});
    errdefer std.log.info("Trying to init graphics pipeline failed", .{});

    //
    const vertex_bind = QuadVertex.getVkBindingDiscription();
    const vertex_attr = QuadVertex.getVkAttributeDiscription();

    try handleError(c.vkCreateGraphicsPipelines(
        device,
        null,
        1,
        &c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            // Specify the stages for our shaders, e.g. vertex, fragment, wiring up the shaders
            .stageCount = 2,
            .pStages = &[_]c.VkPipelineShaderStageCreateInfo{
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .module = shader_module_vert,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = shader_module_frag,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
            },
            // Tell the GPU how to read the vertex memory
            .pVertexInputState = &c.VkPipelineVertexInputStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = vertex_bind.len,
                .pVertexBindingDescriptions = &vertex_bind,
                .vertexAttributeDescriptionCount = vertex_attr.len,
                .pVertexAttributeDescriptions = &vertex_attr,
            },
            // Essentially we specify we are doing triangles here
            .pInputAssemblyState = &c.VkPipelineInputAssemblyStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            },
            .pTessellationState = null,
            // We null the viewport state because we use the dynamics instead
            .pViewportState = &c.VkPipelineViewportStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .viewportCount = 1,
                .pViewports = null,
                .scissorCount = 1,
                .pScissors = null,
            },
            // Defines how triangles are to be transfomred to
            .pRasterizationState = &c.VkPipelineRasterizationStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = 0.0,
                // Specify how to fill the space in between (or not, wireframe-ish)
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                // Can be useful to cull "backsides" of triangles
                .cullMode = c.VK_CULL_MODE_NONE,
                .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0.0,
                .depthBiasClamp = 0.0,
                .depthBiasSlopeFactor = 0.0,
                .lineWidth = 1.0,
            },
            // We dont do mutlisampling
            .pMultisampleState = &c.VkPipelineMultisampleStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 1.0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            },
            // We dont do depth testing
            .pDepthStencilState = &c.VkPipelineDepthStencilStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = c.VK_FALSE,
                .depthWriteEnable = c.VK_FALSE,
                .depthCompareOp = c.VK_COMPARE_OP_LESS,
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = c.VK_FALSE,
                .front = .{},
                .back = .{},
                .minDepthBounds = 0,
                .maxDepthBounds = 1,
            },
            // How to merge the result of the fragment shader with the previous pixel that is already there
            .pColorBlendState = &c.VkPipelineColorBlendStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &c.VkPipelineColorBlendAttachmentState{
                    .blendEnable = c.VK_TRUE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .alphaBlendOp = c.VK_BLEND_OP_ADD,
                    .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | //
                        c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                },
                .blendConstants = [4]f32{ 0, 0, 0, 0 },
            },
            // Us stating that we will manually specify the viewport sizes before rendering. This means that we
            // dont have to recreate the GRAPHICS PIPELINES on viewport chnanges! Note that we will still need to
            // recreate the swapchain regardless.
            .pDynamicState = &c.VkPipelineDynamicStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .dynamicStateCount = 2,
                .pDynamicStates = &[_]c.VkDynamicState{
                    c.VK_DYNAMIC_STATE_VIEWPORT,
                    c.VK_DYNAMIC_STATE_SCISSOR,
                },
            },
            .layout = pipeline_layout,
            .renderPass = render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
        },
        null,
        &vkGraphicsPipeline,
    ));

    defer std.log.info("Trying to init graphics pipeline...", .{});
    return vkGraphicsPipeline;
}

/// Pipeline for drawing the connections
pub fn initBezierVertexVkGraphicsPipeline(
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
    pipeline_layout: c.VkPipelineLayout,
    shader_module_vert: c.VkShaderModule,
    shader_module_frag: c.VkShaderModule,
) !c.VkPipeline {
    var vkGraphicsPipeline: c.VkPipeline = undefined;

    std.log.info("Trying to init graphics pipeline...", .{});
    errdefer std.log.info("Trying to init graphics pipeline failed", .{});

    //
    const vertex_bind = BezierVertex.getVkBindingDiscription();
    const vertex_attr = BezierVertex.getVkAttributeDiscription();

    try handleError(c.vkCreateGraphicsPipelines(
        device,
        null,
        1,
        &c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stageCount = 2,
            .pStages = &[_]c.VkPipelineShaderStageCreateInfo{
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .module = shader_module_vert,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = shader_module_frag,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
            },
            .pVertexInputState = &c.VkPipelineVertexInputStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = vertex_bind.len,
                .pVertexBindingDescriptions = &vertex_bind,
                .vertexAttributeDescriptionCount = vertex_attr.len,
                .pVertexAttributeDescriptions = &vertex_attr,
            },
            .pInputAssemblyState = &c.VkPipelineInputAssemblyStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            },
            .pTessellationState = null,
            .pViewportState = &c.VkPipelineViewportStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .viewportCount = 1,
                .pViewports = null,
                .scissorCount = 1,
                .pScissors = null,
            },
            .pRasterizationState = &c.VkPipelineRasterizationStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = 0.0,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .cullMode = c.VK_CULL_MODE_NONE,
                .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0.0,
                .depthBiasClamp = 0.0,
                .depthBiasSlopeFactor = 0.0,
                .lineWidth = 1.0,
            },
            .pMultisampleState = &c.VkPipelineMultisampleStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 1.0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            },
            .pDepthStencilState = &c.VkPipelineDepthStencilStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = c.VK_FALSE,
                .depthWriteEnable = c.VK_FALSE,
                .depthCompareOp = c.VK_COMPARE_OP_LESS,
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = c.VK_FALSE,
                .front = .{},
                .back = .{},
                .minDepthBounds = 0,
                .maxDepthBounds = 1,
            },
            .pColorBlendState = &c.VkPipelineColorBlendStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &c.VkPipelineColorBlendAttachmentState{
                    .blendEnable = c.VK_TRUE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .alphaBlendOp = c.VK_BLEND_OP_ADD,
                    .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | //
                        c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                },
                .blendConstants = [4]f32{ 0, 0, 0, 0 },
            },
            .pDynamicState = &c.VkPipelineDynamicStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .dynamicStateCount = 2,
                .pDynamicStates = &[_]c.VkDynamicState{
                    c.VK_DYNAMIC_STATE_VIEWPORT,
                    c.VK_DYNAMIC_STATE_SCISSOR,
                },
            },
            .layout = pipeline_layout,
            .renderPass = render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
        },
        null,
        &vkGraphicsPipeline,
    ));

    defer std.log.info("Trying to init graphics pipeline...", .{});
    return vkGraphicsPipeline;
}

/// Pipeline for drawing the text
pub fn initTextVertexVkGraphicsPipeline(
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
    pipeline_layout: c.VkPipelineLayout,
    shader_module_vert: c.VkShaderModule,
    shader_module_frag: c.VkShaderModule,
) !c.VkPipeline {
    var vkGraphicsPipeline: c.VkPipeline = undefined;

    std.log.info("Trying to init graphics pipeline...", .{});
    errdefer std.log.info("Trying to init graphics pipeline failed", .{});

    //
    const vertex_bind = TextVertex.getVkBindingDiscription();
    const vertex_attr = TextVertex.getVkAttributeDiscription();

    try handleError(c.vkCreateGraphicsPipelines(
        device,
        null,
        1,
        &c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stageCount = 2,
            .pStages = &[_]c.VkPipelineShaderStageCreateInfo{
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                    .module = shader_module_vert,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = shader_module_frag,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
            },
            .pVertexInputState = &c.VkPipelineVertexInputStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = vertex_bind.len,
                .pVertexBindingDescriptions = &vertex_bind,
                .vertexAttributeDescriptionCount = vertex_attr.len,
                .pVertexAttributeDescriptions = &vertex_attr,
            },
            .pInputAssemblyState = &c.VkPipelineInputAssemblyStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            },
            .pTessellationState = null,
            .pViewportState = &c.VkPipelineViewportStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .viewportCount = 1,
                .pViewports = null,
                .scissorCount = 1,
                .pScissors = null,
            },
            .pRasterizationState = &c.VkPipelineRasterizationStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = 0.0,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .cullMode = c.VK_CULL_MODE_NONE,
                .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
                .depthBiasConstantFactor = 0.0,
                .depthBiasClamp = 0.0,
                .depthBiasSlopeFactor = 0.0,
                .lineWidth = 1.0,
            },
            .pMultisampleState = &c.VkPipelineMultisampleStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
                .sampleShadingEnable = c.VK_FALSE,
                .minSampleShading = 1.0,
                .pSampleMask = null,
                .alphaToCoverageEnable = c.VK_FALSE,
                .alphaToOneEnable = c.VK_FALSE,
            },
            .pDepthStencilState = &c.VkPipelineDepthStencilStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = c.VK_FALSE,
                .depthWriteEnable = c.VK_FALSE,
                .depthCompareOp = c.VK_COMPARE_OP_LESS,
                .depthBoundsTestEnable = c.VK_FALSE,
                .stencilTestEnable = c.VK_FALSE,
                .front = .{},
                .back = .{},
                .minDepthBounds = 0,
                .maxDepthBounds = 1,
            },
            .pColorBlendState = &c.VkPipelineColorBlendStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &c.VkPipelineColorBlendAttachmentState{
                    .blendEnable = c.VK_TRUE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                    .alphaBlendOp = c.VK_BLEND_OP_ADD,
                    .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | //
                        c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                },
                .blendConstants = [4]f32{ 0, 0, 0, 0 },
            },
            .pDynamicState = &c.VkPipelineDynamicStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .dynamicStateCount = 2,
                .pDynamicStates = &[_]c.VkDynamicState{
                    c.VK_DYNAMIC_STATE_VIEWPORT,
                    c.VK_DYNAMIC_STATE_SCISSOR,
                },
            },
            .layout = pipeline_layout,
            .renderPass = render_pass,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
        },
        null,
        &vkGraphicsPipeline,
    ));

    defer std.log.info("Trying to init graphics pipeline...", .{});
    return vkGraphicsPipeline;
}

pub fn deinitVkPipeline(device: c.VkDevice, vkPipeline: c.VkPipeline) void {
    c.vkDestroyPipeline(device, vkPipeline, null);
    defer std.log.info("Deinit vulkan pipeline OK", .{});
}

// =FrameBuffers=======================================================================================================
//  The framebuffer references image views that are to be used for color, depth and stencil targets

/// Initializes a framebuffer, which is an image view prepared to be drawn on
pub fn initFramebuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    image_views: []c.VkImageView,
    render_pass: c.VkRenderPass,
    swapchain_extent: c.VkExtent2D,
) ![]c.VkFramebuffer {
    std.log.info("Trying to init framebuffers...", .{});
    errdefer std.log.info("Trying to init framebuffers failed", .{});

    var vkFramebuffers = try allocator.alloc(c.VkFramebuffer, image_views.len);

    for (0..image_views.len) |i| {
        try handleError(c.vkCreateFramebuffer(
            device,
            &c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .renderPass = render_pass,
                .attachmentCount = 1,
                .pAttachments = &[_]c.VkImageView{
                    image_views[i],
                },
                .width = swapchain_extent.width,
                .height = swapchain_extent.height,
                .layers = 1,
            },
            null,
            &vkFramebuffers[i],
        ));
    }

    defer std.log.info("Trying to init framebuffers...", .{});
    return vkFramebuffers;
}

pub fn deinitFramebuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vkFramebuffers: []c.VkFramebuffer,
) void {
    for (0..vkFramebuffers.len) |i| {
        c.vkDestroyFramebuffer(device, vkFramebuffers[i], null);
    }

    allocator.free(vkFramebuffers);

    defer std.log.info("Deinit vulkan framebuffers OK", .{});
}

// =CommandBuffers=====================================================================================================
// Operations in Vulkan that we want to execute, like drawing operations, need to be submitted to a queue. These
// operations first need to be recorded into a VkCommandBuffer before they can be submitted.

/// Initialize a command pool, which can be used to create command buffers
pub fn initCommandPool(
    device: c.VkDevice,
    selected_graphics_queue_index: u32,
) !c.VkCommandPool {
    var command_pool: c.VkCommandPool = undefined;

    std.log.info("Trying to init command pool...", .{});
    errdefer std.log.info("Trying to init command pool failed", .{});

    try handleError(c.vkCreateCommandPool(
        device,
        &c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = selected_graphics_queue_index,
        },
        null,
        &command_pool,
    ));

    defer std.log.info("Trying to init command pool OK", .{});
    return command_pool;
}

/// Deinitializes a command pool
pub fn deinitCommandPool(device: c.VkDevice, command_pool: c.VkCommandPool) void {
    c.vkDestroyCommandPool(device, command_pool, null);
    defer std.log.info("Deinit vulkan command pool OK", .{});
}

pub fn initCommandBuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    buffer_count: usize,
) ![]c.VkCommandBuffer {
    var vkCommandBuffers: []c.VkCommandBuffer = undefined;

    std.log.info("Trying to init command buffers...", .{});
    errdefer std.log.info("Trying to init command buffers failed", .{});

    vkCommandBuffers = try allocator.alloc(c.VkCommandBuffer, buffer_count);

    try handleError(c.vkAllocateCommandBuffers(
        device,
        &c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = command_pool,
            // Secondary buffers can be issued by multiple threads, which can then be invoked by a primary. Instead,
            // we can also just write directly to the primary.
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(buffer_count),
        },
        vkCommandBuffers.ptr,
    ));

    defer std.log.info("Trying to init command buffers OK", .{});
    return vkCommandBuffers;
}

pub fn deinitCommandBuffers(
    allocator: std.mem.Allocator,
    vkCommandBuffers: []c.VkCommandBuffer,
) void {
    std.log.info("Trying to free command buffers...", .{});
    allocator.free(vkCommandBuffers);
    defer std.log.info("Trying to free command buffer OK", .{});
}

pub fn begOneTimeCommand(
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
) !c.VkCommandBuffer {
    var vkCommandBuffer: c.VkCommandBuffer = undefined;
    try handleError(c.vkAllocateCommandBuffers(device, &c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    }, &vkCommandBuffer));

    try handleError(c.vkBeginCommandBuffer(vkCommandBuffer, &c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    }));

    return vkCommandBuffer;
}

pub fn endOneTimeCommand(
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    vkCommandBuffer: c.VkCommandBuffer,
    command_pool: c.VkCommandPool,
) !void {
    try handleError(c.vkEndCommandBuffer(vkCommandBuffer));

    try handleError(c.vkQueueSubmit(graphics_queue, 1, &c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .commandBufferCount = 1,
        .pCommandBuffers = &vkCommandBuffer,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    }, null));

    try handleError(c.vkQueueWaitIdle(graphics_queue));

    c.vkFreeCommandBuffers(device, command_pool, 1, &vkCommandBuffer);
}

pub fn resetCommandBuffer(
    cmd: c.VkCommandBuffer,
) !void {
    try handleError(c.vkResetCommandBuffer(cmd, 0));
}

pub fn beginCommandBuffer(
    cmd: c.VkCommandBuffer,
) !void {
    try handleError(
        c.vkBeginCommandBuffer(cmd, &c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = 0,
            .pInheritanceInfo = null,
        }),
    );
}

pub fn bufferCopy(
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    srcBuffer: c.VkBuffer,
    dstBuffer: c.VkBuffer,
    deviceSize: c.VkDeviceSize,
) !void {
    const vkCommandBuffer: c.VkCommandBuffer = try begOneTimeCommand(device, command_pool);

    {
        c.vkCmdCopyBuffer(vkCommandBuffer, srcBuffer, dstBuffer, 1, &c.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = deviceSize,
        });
    }

    try endOneTimeCommand(device, graphics_queue, vkCommandBuffer, command_pool);
}

fn findMemoryType(
    physical_device: c.VkPhysicalDevice,
    vkTypeFilter: u32,
    vkMemoryPropertyFlags: c.VkMemoryPropertyFlags,
) !u32 {
    var physical_deviceMemoryProperties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &physical_deviceMemoryProperties);

    for (0..physical_deviceMemoryProperties.memoryTypeCount) |i| {
        const mask = @as(u32, 1) << @as(u5, @intCast(i));
        if ((vkTypeFilter & mask) > 0 and
            (physical_deviceMemoryProperties.memoryTypes[i].propertyFlags & vkMemoryPropertyFlags) == //
                vkMemoryPropertyFlags)
        {
            return @intCast(i);
        }
    }

    return error.VkError;
}

fn initBuffer(
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    deviceSize: c.VkDeviceSize,
    vkBufferUsageFlags: c.VkBufferUsageFlags,
    vkMemoryPropertyFlags: c.VkMemoryPropertyFlags,
    vkBuffer: *c.VkBuffer,
    vkBufferMemory: *c.VkDeviceMemory,
) !void {
    std.log.info("Trying to init buffer...", .{});
    errdefer std.log.info("Trying to init buffer failed", .{});

    try handleError(c.vkCreateBuffer(
        device,
        &c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = deviceSize,
            .usage = vkBufferUsageFlags,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        },
        null,
        vkBuffer,
    ));

    var vkMemoryRequirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(device, vkBuffer.*, &vkMemoryRequirements);

    try handleError(c.vkAllocateMemory(device, &c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = vkMemoryRequirements.size,
        .memoryTypeIndex = try findMemoryType(
            physical_device,
            vkMemoryRequirements.memoryTypeBits,
            vkMemoryPropertyFlags,
        ),
    }, null, vkBufferMemory));

    try handleError(c.vkBindBufferMemory(device, vkBuffer.*, vkBufferMemory.*, 0));

    defer std.log.info("Trying to init buffer OK", .{});
}

fn deinitBuffer(
    device: c.VkDevice,
    vkBuffer: c.VkBuffer,
    vkBufferMemory: c.VkDeviceMemory,
) void {
    c.vkDestroyBuffer(device, vkBuffer, null);
    c.vkFreeMemory(device, vkBufferMemory, null);

    defer std.log.info("Deinit vulkan buffer OK", .{});
}

// =QuadVertexBufferSet===================================================================================================

pub const VertexBufferSet = struct {
    vkBuffers: []c.VkBuffer,
    vkBuffersMemory: []c.VkDeviceMemory,
    vkBuffersMapped: []*anyopaque,
    max_vertices: usize,
};

pub fn initVertexBufferSet(
    T: type,
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    max_vertices: usize,
    buffer_count: usize,
) !VertexBufferSet {
    std.log.info("Trying to init dynamic vertex buffers...", .{});
    errdefer std.log.info("Trying to init dynamic vertex buffers failed", .{});

    var vertex_buffer_set: VertexBufferSet = undefined;
    vertex_buffer_set.max_vertices = max_vertices;
    vertex_buffer_set.vkBuffers = try allocator.alloc(c.VkBuffer, buffer_count);
    vertex_buffer_set.vkBuffersMemory = try allocator.alloc(c.VkDeviceMemory, buffer_count);
    vertex_buffer_set.vkBuffersMapped = try allocator.alloc(*anyopaque, buffer_count);

    const buffer_size = @sizeOf(T) * max_vertices;

    for (0..buffer_count) |i| {
        try initBuffer(
            device,
            physical_device,
            buffer_size,
            c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &vertex_buffer_set.vkBuffers[i],
            &vertex_buffer_set.vkBuffersMemory[i],
        );

        try handleError(c.vkMapMemory(
            device,
            vertex_buffer_set.vkBuffersMemory[i],
            0,
            buffer_size,
            0,
            @ptrCast(&vertex_buffer_set.vkBuffersMapped[i]),
        ));
    }

    defer std.log.info("Trying to init dynamic vertex buffers OK", .{});
    return vertex_buffer_set;
}

pub fn deinitVertexBufferSet(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vertex_buffer_set: VertexBufferSet,
) void {
    for (0..vertex_buffer_set.vkBuffers.len) |i| {
        deinitBuffer(device, vertex_buffer_set.vkBuffers[i], vertex_buffer_set.vkBuffersMemory[i]);
    }
    allocator.free(vertex_buffer_set.vkBuffers);
    allocator.free(vertex_buffer_set.vkBuffersMemory);
    allocator.free(vertex_buffer_set.vkBuffersMapped);
    defer std.log.info("Deinit vulkan dynamic vertex buffers OK", .{});
}

// =UniformBufferSet===================================================================================================

pub const UniformBufferSet = struct {
    vkUniformBuffers: []c.VkBuffer,
    vkUniformBuffersMemory: []c.VkDeviceMemory,
    vkUniformBuffersMapped: []*anyopaque,
};

pub fn initUniformBufferSet(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    buffer_count: usize,
) !UniformBufferSet {
    std.log.info("Trying to init uniform buffers...", .{});
    errdefer std.log.info("Trying to init uniform buffers failed", .{});

    var uniform_buffer_set: UniformBufferSet = undefined;
    uniform_buffer_set.vkUniformBuffers = try allocator.alloc(c.VkBuffer, buffer_count);
    uniform_buffer_set.vkUniformBuffersMemory = try allocator.alloc(c.VkDeviceMemory, buffer_count);
    uniform_buffer_set.vkUniformBuffersMapped = try allocator.alloc(*anyopaque, buffer_count);

    for (0..buffer_count) |i| {
        try initBuffer(
            device,
            physical_device,
            @sizeOf(Uniform),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &uniform_buffer_set.vkUniformBuffers[i],
            &uniform_buffer_set.vkUniformBuffersMemory[i],
        );

        try handleError(c.vkMapMemory(
            device,
            uniform_buffer_set.vkUniformBuffersMemory[i],
            0,
            @sizeOf(Uniform),
            0,
            @ptrCast(&uniform_buffer_set.vkUniformBuffersMapped[i]),
        ));
    }

    defer std.log.info("Trying to init uniform buffers OK", .{});
    return uniform_buffer_set;
}

pub fn deinitUniformBufferSet(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    uniform_buffer_set: UniformBufferSet,
) void {
    for (0..uniform_buffer_set.vkUniformBuffers.len) |i| {
        deinitBuffer(device, uniform_buffer_set.vkUniformBuffers[i], uniform_buffer_set.vkUniformBuffersMemory[i]);
    }
    allocator.free(uniform_buffer_set.vkUniformBuffers);
    allocator.free(uniform_buffer_set.vkUniformBuffersMemory);
    allocator.free(uniform_buffer_set.vkUniformBuffersMapped);

    defer std.log.info("Deinit vulkan uniform buffers OK", .{});
}

// =Semaphores=========================================================================================================
pub fn initVkSemaphore(device: c.VkDevice) !c.VkSemaphore {
    var semaphore: c.VkSemaphore = undefined;

    std.log.info("Trying to init semaphore...", .{});
    errdefer std.log.info("Trying to init semaphore failed", .{});

    try handleError(c.vkCreateSemaphore(
        device,
        &c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        },
        null,
        &semaphore,
    ));

    defer std.log.info("Trying to init semaphore OK", .{});
    return semaphore;
}

pub fn deinitVkSemaphore(
    device: c.VkDevice,
    semaphore: c.VkSemaphore,
) void {
    c.vkDestroySemaphore(
        device,
        semaphore,
        null,
    );

    errdefer std.log.info("Deinit vulkan semaphore OK", .{});
}

pub fn initVkSemaphores(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    count: usize,
) ![]c.VkSemaphore {
    var semaphores: []c.VkSemaphore = undefined;

    std.log.info("Trying to init {} semaphores...", .{count});
    errdefer std.log.info("Trying to init {} semaphores failed", .{count});

    semaphores = try allocator.alloc(c.VkSemaphore, count);
    for (semaphores) |*semaphore| {
        semaphore.* = try initVkSemaphore(device);
    }

    defer std.log.info("Trying to init {} semaphores OK", .{count});
    return semaphores;
}

pub fn deinitVkSemaphores(allocator: std.mem.Allocator, device: c.VkDevice, semaphores: []c.VkSemaphore) void {
    for (semaphores) |semaphore| {
        deinitVkSemaphore(device, semaphore);
    }
    allocator.free(semaphores);

    defer std.log.info("Deinit {} semaphores OK", .{semaphores.len});
}

// =Fences=============================================================================================================

pub fn initVkFence(device: c.VkDevice) !c.VkFence {
    var vkFence: c.VkFence = undefined;

    std.log.info("Trying to init fence...", .{});
    errdefer std.log.info("Trying to init fence failed", .{});

    try handleError(c.vkCreateFence(
        device,
        &c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = &c.VkExportFenceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_EXPORT_FENCE_CREATE_INFO,
                .pNext = null,
                .handleTypes = c.VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_FD_BIT,
            },
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        },
        null,
        &vkFence,
    ));

    defer std.log.info("Trying to init fence OK", .{});
    return vkFence;
}

pub fn deinitVkFence(device: c.VkDevice, vkFence: c.VkFence) void {
    c.vkDestroyFence(
        device,
        vkFence,
        null,
    );
    defer std.log.info("Deinit vulkan fence OK", .{});
}

pub fn initVkFences(allocator: std.mem.Allocator, device: c.VkDevice, count: usize) ![]c.VkFence {
    var vkFences: []c.VkFence = undefined;

    std.log.info("Trying to init {} fences...", .{count});
    errdefer std.log.info("Trying to init {} fences failed", .{count});

    vkFences = try allocator.alloc(c.VkFence, count);
    for (vkFences) |*vkFence| {
        vkFence.* = try initVkFence(device);
    }

    defer std.log.info("Trying to init {} fences OK", .{count});
    return vkFences;
}

pub fn deinitVkFences(allocator: std.mem.Allocator, device: c.VkDevice, vkFences: []c.VkFence) void {
    for (vkFences) |vkFence| {
        deinitVkFence(device, vkFence);
    }
    allocator.free(vkFences);

    defer std.log.info("Deinit {} fences OK", .{vkFences.len});
}

// =DescriptorPool=====================================================================================================

pub fn initVkDescriptorPool(
    device: c.VkDevice,
    vkUniformBuffers: []c.VkBuffer,
) !c.VkDescriptorPool {
    var vkDescriptorPool: c.VkDescriptorPool = undefined;

    std.log.info("Trying to init descriptor pool with capacity {}...", .{vkUniformBuffers.len});
    errdefer std.log.info("Trying to init descriptor pool with capacity {} failed", .{vkUniformBuffers.len});

    try handleError(c.vkCreateDescriptorPool(
        device,
        &c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .maxSets = @intCast(vkUniformBuffers.len),
            .poolSizeCount = 2,
            .pPoolSizes = &[_]c.VkDescriptorPoolSize{
                c.VkDescriptorPoolSize{
                    .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = @intCast(vkUniformBuffers.len),
                },
                c.VkDescriptorPoolSize{
                    .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .descriptorCount = @intCast(vkUniformBuffers.len),
                },
            },
        },
        null,
        &vkDescriptorPool,
    ));

    defer std.log.info("Trying to init descriptor pool with capacity {} OK", .{vkUniformBuffers.len});
    return vkDescriptorPool;
}

pub fn deinitVkDescriptorPool(
    device: c.VkDevice,
    vkDescriptorPool: c.VkDescriptorPool,
) void {
    c.vkDestroyDescriptorPool(device, vkDescriptorPool, null);

    defer std.log.info("Deinit descriptor pool OK", .{});
}

// =DescriptorSets=====================================================================================================

pub fn initVkDescriptorSets(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    vkDescriptorPool: c.VkDescriptorPool,
    vkUniformBuffers: []c.VkBuffer,
    font_texture_view: c.VkImageView,
    font_sampler: c.VkSampler,
) ![]c.VkDescriptorSet {
    var descriptor_sets: []c.VkDescriptorSet = undefined;

    std.log.info("Trying to init descriptor sets...", .{});
    errdefer std.log.info("Trying to init descriptor sets failed", .{});

    const layouts = try allocator.alloc(c.VkDescriptorSetLayout, vkUniformBuffers.len);
    defer allocator.free(layouts);
    for (layouts) |*layout| {
        layout.* = descriptor_set_layout;
    }

    descriptor_sets = try allocator.alloc(c.VkDescriptorSet, vkUniformBuffers.len);
    try handleError(c.vkAllocateDescriptorSets(device, &c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = vkDescriptorPool,
        .descriptorSetCount = @intCast(vkUniformBuffers.len),
        .pSetLayouts = layouts.ptr,
    }, descriptor_sets.ptr));

    for (0..@intCast(vkUniformBuffers.len)) |i| {
        c.vkUpdateDescriptorSets(
            device,
            2,
            &[_]c.VkWriteDescriptorSet{
                c.VkWriteDescriptorSet{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_sets[i],
                    .dstBinding = 0,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .pImageInfo = null,
                    .pBufferInfo = &c.VkDescriptorBufferInfo{
                        .buffer = vkUniformBuffers[i],
                        .offset = 0,
                        .range = @sizeOf(Uniform),
                    },
                    .pTexelBufferView = null,
                },
                c.VkWriteDescriptorSet{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = descriptor_sets[i],
                    .dstBinding = 1,
                    .dstArrayElement = 0,
                    .descriptorCount = 1,
                    .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .pImageInfo = &c.VkDescriptorImageInfo{
                        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                        .imageView = font_texture_view,
                        .sampler = font_sampler,
                    },
                    .pBufferInfo = null,
                    .pTexelBufferView = null,
                },
            },
            0,
            null,
        );
    }

    defer std.log.info("Trying to init descriptor sets OK", .{});
    return descriptor_sets;
}

pub fn deinitVkDescriptorSets(
    allocator: std.mem.Allocator,
    descriptor_sets: []c.VkDescriptorSet,
) void {
    allocator.free(descriptor_sets);

    defer std.log.info("Deinit descriptor sets OK", .{});
}

// =TextureSampler=====================================================================================================

pub fn initTextureSampler(
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
) !c.VkSampler {
    var vkTextureSampler: c.VkSampler = undefined;

    std.log.info("Trying to init texture sampler...", .{});
    errdefer std.log.info("Trying to init texture sampler failed", .{});

    var properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(physical_device, &properties);

    try handleError(c.vkCreateSampler(device, &c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = c.VK_FILTER_LINEAR,
        .minFilter = c.VK_FILTER_LINEAR,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .mipLodBias = 0.0,
        .anisotropyEnable = c.VK_FALSE,
        .maxAnisotropy = properties.limits.maxSamplerAnisotropy,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .minLod = 0.0,
        .maxLod = 0.0,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
    }, null, &vkTextureSampler));

    std.log.info("Trying to init texture sampler OK", .{});
    return vkTextureSampler;
}

pub fn deinitTextureSampler(
    device: c.VkDevice,
    vkTextureSampler: c.VkSampler,
) void {
    std.log.info("Trying to free vulkan buffer...", .{});

    c.vkDestroySampler(device, vkTextureSampler, null);

    defer std.log.info("Trying to free vulkan buffer OK", .{});
}

// =TextureImage=======================================================================================================

pub const Image = struct {
    image: c.VkImage,
    image_memory: c.VkDeviceMemory,
};

pub fn initImage(
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    textureH: u32,
    textureW: u32,
    vkFormat: c.VkFormat,
    imageTiling: c.VkImageTiling,
    imageUsageFlags: c.VkImageUsageFlags,
    vkMemoryPropertyFlags: c.VkMemoryPropertyFlags,
) !Image {
    var image: Image = undefined;

    std.log.info("Trying to init image...", .{});
    errdefer std.log.info("Trying to init image failed", .{});

    try handleError(c.vkCreateImage(
        device,
        &c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .format = vkFormat,
            .extent = c.VkExtent3D{ .width = textureW, .height = textureH, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .tiling = imageTiling,
            .usage = imageUsageFlags,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        },
        null,
        &image.image,
    ));

    var memRequirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(device, image.image, &memRequirements);

    try handleError(c.vkAllocateMemory(device, &c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = try findMemoryType(
            physical_device,
            memRequirements.memoryTypeBits,
            vkMemoryPropertyFlags,
        ),
    }, null, &image.image_memory));

    try handleError(c.vkBindImageMemory(device, image.image, image.image_memory, 0));

    std.log.info("Trying to init image OK", .{});
    return image;
}

pub fn transitionImageLayout(
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    image: c.VkImage,
    format: c.VkFormat,
    oldLayout: c.VkImageLayout,
    newLayout: c.VkImageLayout,
) !void {
    const commandBuffer = try begOneTimeCommand(device, command_pool);

    var srcStage: c.VkPipelineStageFlags = undefined;
    var dstStage: c.VkPipelineStageFlags = undefined;
    var srcAccessMask: c.VkAccessFlags = undefined;
    var dstAccessMask: c.VkAccessFlags = undefined;

    // dunno what this does
    if (oldLayout == c.VK_IMAGE_LAYOUT_UNDEFINED and //
        newLayout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
    {
        srcAccessMask = 0;
        dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;

        srcStage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dstStage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and //
        newLayout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    {
        srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;

        srcStage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dstStage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else {
        return error.VkError;
    }

    c.vkCmdPipelineBarrier(
        commandBuffer,
        srcStage,
        dstStage,
        0,
        0,
        null,
        0,
        null,
        1,
        &c.VkImageMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .pNext = null,
            .srcAccessMask = srcAccessMask,
            .dstAccessMask = dstAccessMask,
            .oldLayout = oldLayout,
            .newLayout = newLayout,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        },
    );

    _ = format;

    try endOneTimeCommand(device, graphics_queue, commandBuffer, command_pool);
}

pub fn copyBufferToImage(
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    imageW: u32,
    imageH: u32,
    vkBuffer: c.VkBuffer,
    image: c.VkImage,
) !void {
    const commandBuffer = try begOneTimeCommand(device, command_pool);

    c.vkCmdCopyBufferToImage(
        commandBuffer,
        vkBuffer,
        image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &c.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = c.VkImageSubresourceLayers{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageOffset = c.VkOffset3D{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .imageExtent = c.VkExtent3D{
                .width = imageW,
                .height = imageH,
                .depth = 1,
            },
        },
    );

    try endOneTimeCommand(device, graphics_queue, commandBuffer, command_pool);
}

pub fn initTextureImage(
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    command_pool: c.VkCommandPool,
    graphics_queue: c.VkQueue,
    bytes: []const u8,
) !Image {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    // stbi_load_from_memory expects (buffer, len, &w, &h, &channels, desired_channels)
    // We pass 4 to force STBI_rgb_alpha (RGBA 32-bit)
    const pixels = c.stbi_load_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );

    if (pixels == null) {
        std.log.err("Failed to load image via stb_image", .{});
        return error.ImageLoadFailed; // Be sure to add this to your error.zig or handle accordingly
    }
    defer c.stbi_image_free(pixels);

    const texW: u32 = @intCast(width);
    const texH: u32 = @intCast(height);
    const imageSize: usize = @as(usize, texW) * @as(usize, texH) * 4;

    var vkStagingBuffer: c.VkBuffer = undefined;
    defer c.vkDestroyBuffer(device, vkStagingBuffer, null);
    var vkStagingBufferMemory: c.VkDeviceMemory = undefined;
    defer c.vkFreeMemory(device, vkStagingBufferMemory, null);
    try initBuffer(
        device,
        physical_device,
        imageSize,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkStagingBuffer,
        &vkStagingBufferMemory,
    );

    var data: *anyopaque = undefined;
    try handleError(c.vkMapMemory(device, vkStagingBufferMemory, 0, imageSize, 0, @ptrCast(&data)));
    const pixel_ptr: [*]const u8 = @ptrCast(pixels);
    memcpy(data, pixel_ptr, imageSize);
    c.vkUnmapMemory(device, vkStagingBufferMemory);

    const image = try initImage(
        device,
        physical_device,
        texW,
        texH,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    try transitionImageLayout(
        device,
        command_pool,
        graphics_queue,
        image.image,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );

    try copyBufferToImage(
        device,
        command_pool,
        graphics_queue,
        texW,
        texH,
        vkStagingBuffer,
        image.image,
    );

    try transitionImageLayout(
        device,
        command_pool,
        graphics_queue,
        image.image,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );

    return image;
}

pub fn deinitTextureImage(
    device: c.VkDevice,
    image: c.VkImage,
    image_memory: c.VkDeviceMemory,
) void {
    std.log.info("Trying to free vulkan texture image...", .{});

    c.vkDestroyImage(device, image, null);
    c.vkFreeMemory(device, image_memory, null);

    defer std.log.info("Trying to free vulkan texture image OK", .{});
}
