const c = @import("c.zig").c;
const std = @import("std");
const Vertex = @import("types.zig").Vertex;
const Uniform = @import("types.zig").Uniform;
const handleError = @import("error.zig").handleError;

// =SDL3Initialization=================================================================================================

/// Helper function to initialize SDL3 with the given flags
pub fn sdlInit(options: struct {
    flags: c.SDL_InitFlags = c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO,
}) !void {
    std.log.info("Trying to init SDL3...", .{});
    errdefer std.log.err("Trying to init SDL3 failed", .{});

    try handleError(
        c.SDL_Init(options.flags),
    );

    defer std.log.info("Trying to init SDL3 OK", .{});
}

/// Helper function to deinitialize SDL3
pub fn sdlQuit() void {
    c.SDL_Quit();

    defer std.log.info("Deinit SDL3 OK", .{});
}

// =SDL3Window=========================================================================================================

/// Helper function to initialize SDL3 window given some options
pub fn sdlInitWindow(options: struct {
    cname: [*:0]const u8 = "window",
    w: usize,
    h: usize,
    flags: c.SDL_WindowFlags = c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
}) !*c.SDL_Window {
    std.log.info("Trying to init SDL3 window...", .{});
    errdefer std.log.err("Trying to SDL3 window failed", .{});

    const window = try handleError(
        c.SDL_CreateWindow(
            options.cname,
            @intCast(options.w),
            @intCast(options.h),
            options.flags,
        ),
    );

    defer std.log.info("Trying to init SDL3 window OK", .{});

    return window;
}

/// Helper function to destroy an SDL3 window
pub fn sdlDestroyWindow(window: *c.SDL_Window) void {
    c.SDL_DestroyWindow(window);

    defer std.log.info("Deinit SDL3 window OK", .{});
}

// =ValidationLayers===================================================================================================

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

// =VkInstanceExtensions===============================================================================================

/// Creates an arraylist of the vulkan extensions requested by SDL3
fn getSDLRequestedVkInstanceExtensions(
    allocator: std.mem.Allocator,
) !std.ArrayList([*:0]const u8) {
    std.log.debug("Trying to enumerate SDL3 requested vulkan extensions...", .{});
    errdefer std.log.err("Trying to enumerate SDL3 requested vulkan extensions failed", .{});

    var count: u32 = 0;
    const extensions_base = c.SDL_Vulkan_GetInstanceExtensions(&count);
    std.log.debug("SDL requests '{}' extensions in total", .{count});

    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, count);
    errdefer extensions.deinit(allocator);

    for (0..count) |i| {
        std.log.debug("SDL requests extension '{s}'", .{extensions_base[i]});
        extensions.appendAssumeCapacity(extensions_base[i]);
    }

    defer std.log.debug("Trying to enumerate SDL3 requested vulkan extensions OK", .{});

    return extensions;
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
    std.log.debug("Trying to checking if requested vulkan instance extensions are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan instance extensions are supported failed", .{});

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

    defer std.log.debug("Trying to checking if requested vulkan instance extensions are supported OK", .{});
}

// =VkInstanceLayers===================================================================================================

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

// =VkInstance=========================================================================================================

/// Initialize vulkan instance
pub fn initVkInstance(
    allocator: std.mem.Allocator,
) !c.VkInstance {
    var instance: c.VkInstance = undefined;

    std.log.info("Trying to init vulkan instance...", .{});
    errdefer std.log.err("Trying to init vulkan instance failed", .{});

    // create our list of requested instance extensions
    var extensions = try getSDLRequestedVkInstanceExtensions(allocator);
    defer extensions.deinit(allocator);
    try extensions.append(allocator, c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    try checkRequestedVkInstanceExtensionsSupported(allocator, extensions.items);

    // create our list of requested instance layers
    var layers = try std.ArrayList([*:0]const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
    try checkRequestedVkInstanceLayersSupported(allocator, layers.items);

    // create the instance
    try handleError(
        c.vkCreateInstance(&c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,

            // I create the logger for vulkan here
            .pNext = &c.VkDebugUtilsMessengerCreateInfoEXT{
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
            },

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

/// Initialize vulkan surface from SDL3
pub fn initVkSurface(
    window: *c.SDL_Window,
    instance: c.VkInstance,
) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;

    std.log.info("Trying to init vulkan surface...", .{});
    errdefer std.log.err("Trying to init vulkan surface failed", .{});

    try handleError(c.SDL_Vulkan_CreateSurface(window, instance, null, &surface));
    errdefer deinitVkSurface(surface);

    defer std.log.info("Trying to init vulkan surface OK", .{});
    return surface;
}

/// Deinitialize vulkan surface from SDL3
pub fn deinitVkSurface(
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
) void {
    c.SDL_Vulkan_DestroySurface(instance, surface, null);

    defer std.log.info("Deinit vulkan surface OK", .{});
}

// =VkPhysicalDevice===================================================================================================

/// Initialize a vulkan physical device
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

        const deviceName = properties.deviceName;
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
            try handleError(c.vkGetPhysicalDeviceSurfaceSupportKHR(
                physical_devices[i],
                @intCast(j),
                surface,
                &vkBoolHasPresentSupport,
            ));

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
    std.log.info("Selecting physical device with name {s}", .{properties.deviceName});

    defer std.log.info("Trying to select vulkan physical device OK", .{});

    return physical_device;
}

// =VkSurfaceCapabilities==============================================================================================

/// Gets a vulkan extent containing the surface dimensions from an SDL window
pub fn getVkExtentFromSDLWindow(
    window: *c.SDL_Window,
    capabilities: c.VkSurfaceCapabilitiesKHR,
) !c.VkExtent2D {
    std.log.debug("Trying to get extent...", .{});
    errdefer std.log.err("Trying to get extent failed", .{});

    if (capabilities.currentExtent.width != std.math.maxInt(u32) or //
        capabilities.currentExtent.height != std.math.maxInt(u32))
    {
        return capabilities.currentExtent;
    }

    var w: c_int = 0;
    var h: c_int = 0;
    try handleError(c.SDL_GetWindowSizeInPixels(window, &w, &h));

    const w32: u32 = @intCast(if (w < 0) 0 else w);
    const h32: u32 = @intCast(if (h < 0) 0 else h);

    // clamp to boundaries defined by the swapchain
    const extent = c.VkExtent2D{
        .width = std.math.clamp(
            w32,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        ),
        .height = std.math.clamp(
            h32,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        ),
    };

    std.log.debug("Created extent of size ({} x {})", .{ extent.width, extent.height });

    defer std.log.debug("Trying to get extent OK", .{});

    return extent;
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
// The Surface Format (VkSurfaceFormatKHR) dictates exactly how color data is stored in memory and how the monitor
// should interpret that data.

/// Get a list of surface formats supported by our physical devices
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

/// Select the preferred surface format from the supported formats
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

/// Get a preferred surface format
pub fn getPreferredVkSurfaceFormat(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkSurfaceFormatKHR {
    var surface_format: c.VkSurfaceFormatKHR = undefined;

    std.log.debug("Trying to get preferred surface format...", .{});
    errdefer std.log.err("Trying to get preferred surface format failed", .{});

    const supportedSurfaceFormats = try getSupportedVkDeviceSurfaceFormats(
        allocator,
        physical_device,
        surface,
    );
    defer allocator.free(supportedSurfaceFormats);

    surface_format = selectPreferredSurfaceFormat(supportedSurfaceFormats);

    defer std.log.debug("Trying to get preferred surface format OK", .{});

    return surface_format;
}

// =VkPresentMode======================================================================================================
// The Present mode dictates when and how the images you render are handed over to the monitor.

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
    try handleError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &count,
        surfacePresentModes.ptr,
    ));

    defer std.log.info("Trying to enumerate supported vulkan device surface present modes OK", .{});
    return surfacePresentModes;
}

/// Select the preferred present mode from the supported formats
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

fn getQueueFamilyProperties(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    std.log.debug("Trying to get all queue family properties...", .{});
    errdefer std.log.err("Trying to get all queue family properties failed", .{});

    var count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
    const queue_family_properties = try allocator.alloc(c.VkQueueFamilyProperties, count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &count, queue_family_properties.ptr);

    defer std.log.debug("Trying to get all queue family properties OK", .{});
    return queue_family_properties;
}

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

fn getSupportedVkDeviceLayers(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) !std.ArrayList([*:0] const u8) {
    std.log.debug("Trying to enumerate supported vulkan device layers...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device layers failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateDeviceLayerProperties(physical_device, &count, null));
    std.log.debug("Vulkan reports '{}' device layers supported in total", .{count});

    const layer_properties = try allocator.alloc(c.VkLayerProperties, count);
    defer allocator.free(layer_properties);
    try handleError(c.vkEnumerateDeviceLayerProperties(physical_device, &count, layer_properties.ptr));

    var layers = try std.ArrayList([*:0] const u8).initCapacity(allocator, count);
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

fn checkRequestedVkDeviceLayersSupported(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    requested_layers: []const [*:0] const u8,
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

fn getSupportedVkDeviceExtensions(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) !std.ArrayList([*:0] const u8) {
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

    var extensions = try std.ArrayList([*:0] const u8).initCapacity(allocator, count);
    for (extension_properties) |extension_property| {
        const name = std.mem.sliceTo(&extension_property.extensionName, 0);
        std.log.debug("Support exists for device extension '{s}'", .{name});
        try extensions.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan device extensions OK", .{});
    return extensions;
}

fn checkRequestedVkDeviceExtensionsSupported(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    requested_extensions: []const [*:0] const u8,
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
    var extensions = try std.ArrayList([*:0] const u8).initCapacity(allocator, 0);
    defer extensions.deinit(allocator);
    try extensions.append(allocator, c.VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    try checkRequestedVkDeviceExtensionsSupported(allocator, physical_device, extensions.items);

    // create our list of requested instance layers
    var layers = try std.ArrayList([*:0] const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
    try checkRequestedVkDeviceLayersSupported(allocator, physical_device, layers.items);

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

pub fn deinitVkDevice(device: c.VkDevice) void {
    c.vkDestroyDevice(device, null);

    defer std.log.info("Deinit vulkan device OK", .{});
}

// =VkSwapchain========================================================================================================
// The Swapchain is the agreement between Vulkan and your operating system on how the pixels should be displayed. 
// Provides the images that we draw on.

pub fn initVkSwapchain(
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    swap_extent: c.VkExtent2D,
    present_mode: c.VkPresentModeKHR,
    graphics_queue_index: u32,
    present_queue_index: u32,
) !c.VkSwapchainKHR {
    var swapchain: c.VkSwapchainKHR = undefined;

    std.log.info("Trying to init vulkan swapchain...", .{});
    errdefer std.log.err("Trying to init vulkan swapchain failed", .{});

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
    const pQueueFamilyIndices: [*c]const u32 = blk: {
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
        .minImageCount = surface_capabilities.minImageCount,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = swap_extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = @intCast(image_sharing_mode),
        .queueFamilyIndexCount = @intCast(queue_family_index_count),
        .pQueueFamilyIndices = pQueueFamilyIndices,
        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    }, null, &swapchain));

    defer std.log.info("Trying to init vulkan swapchain OK", .{});
    return swapchain;
}

pub fn deinitVkSwapchain(
    device: c.VkDevice,
    vkSwapchain: c.VkSwapchainKHR,
) void {
    c.vkDestroySwapchainKHR(device, vkSwapchain, null);
    defer std.log.info("Deinit vulkan swapchain OK", .{});
}

// =VkImages===========================================================================================================
// Images are that which we draw on.

/// Memory of the image inside the swapchain
pub fn initVkImages(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vkSwapchain: c.VkSwapchainKHR,
) ![]c.VkImage {
    std.log.info("Trying to get images...", .{});
    errdefer std.log.info("Trying to get images failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetSwapchainImagesKHR(device, vkSwapchain, &count, null));
    const images = try allocator.alloc(c.VkImage, count);
    try handleError(c.vkGetSwapchainImagesKHR(device, vkSwapchain, &count, images.ptr));

    std.log.info("Acquired {} images", .{count});

    defer std.log.info("Trying to get images...", .{});
    return images;
}

pub fn deinitVkImages(
    allocator: std.mem.Allocator,
    vkImages: []c.VkImage,
) void {
    defer allocator.free(vkImages);

    defer std.log.info("Deinit images OK", .{});
}

pub fn initVkImageViews(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vkImages: []c.VkImage,
    surface_format: c.VkSurfaceFormatKHR,
) ![]c.VkImageView {
    std.log.info("Trying to get image views...", .{});
    errdefer std.log.info("Trying to get image views failed", .{});

    const vkImageViews = try allocator.alloc(c.VkImageView, vkImages.len);
    for (0..vkImages.len) |i| {
        try handleError(c.vkCreateImageView(device, &c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = vkImages[i],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = surface_format.format,
            .components = c.VkComponentMapping{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        }, null, &vkImageViews[i]));
    }

    defer std.log.info("Trying to get image views OK", .{});
    return vkImageViews;
}

pub fn deinitVkImageViews(allocator: std.mem.Allocator, device: c.VkDevice, vkImageViews: []c.VkImageView) void {
    for (0..vkImageViews.len) |i| {
        c.vkDestroyImageView(device, vkImageViews[i], null);
    }
    allocator.free(vkImageViews);

    defer std.log.info("Deinit image views OK", .{});
}

// =Shaders============================================================================================================
// The Shaders are the code that we run on the GPU

pub fn initVkShaderModule(comptime path: anytype, device: c.VkDevice) !c.VkShaderModule {
    var shader_module: c.VkShaderModule = undefined;

    std.log.info("Trying to init shader module with path '{s}'...", .{path});
    errdefer std.log.info("Trying to init shader module with path '{s}' failed", .{path});

    const code align(@alignOf(u32)) = @embedFile(path).*;

    try handleError(c.vkCreateShaderModule(device, &c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len,
        .pCode = std.mem.bytesAsSlice(u32, &code).ptr,
    }, null, &shader_module));

    defer std.log.info("Trying to init shader module with path '{s}' OK", .{path});
    return shader_module;
}

pub fn deinitVkShaderModule(
    device: c.VkDevice,
    vkShaderModule: c.VkShaderModule,
) void {
    c.vkDestroyShaderModule(device, vkShaderModule, null);

    defer std.log.info("Deinit vulkan shader module OK", .{});
}

// =VkGraphicsPipeline=================================================================================================

pub fn initVkRenderPass(
    device: c.VkDevice,
    surface_format: c.VkSurfaceFormatKHR,
) !c.VkRenderPass {
    var render_pass: c.VkRenderPass = undefined;

    std.log.info("Trying to init render pass...", .{});
    errdefer std.log.info("Trying to init render pass failed", .{});

    try handleError(c.vkCreateRenderPass(device, &c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &[_]c.VkAttachmentDescription{
            c.VkAttachmentDescription{
                .flags = 0,
                .format = surface_format.format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            },
        },
        .subpassCount = 1,
        .pSubpasses = &[_]c.VkSubpassDescription{
            c.VkSubpassDescription{
                .flags = 0,
                .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .inputAttachmentCount = 0,
                .pInputAttachments = null,
                .colorAttachmentCount = 1,
                .pColorAttachments = &c.VkAttachmentReference{
                    .attachment = 0,
                    .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                },
                .pResolveAttachments = null,
                .pDepthStencilAttachment = null,
                .preserveAttachmentCount = 0,
                .pPreserveAttachments = null,
            },
        },
        .dependencyCount = 1,
        .pDependencies = &c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dependencyFlags = 0,
        },
    }, null, &render_pass));

    defer std.log.info("Trying to init render pass...", .{});
    return render_pass;
}

pub fn deinitVkRenderPass(
    device: c.VkDevice,
    vkRenderPass: c.VkRenderPass,
) void {
    c.vkDestroyRenderPass(device, vkRenderPass, null);

    defer std.log.info("Deinit vulkan render pass OK", .{});
}

// =VkDescriptorSet====================================================================================================

pub fn initVkDescriptorSetLayout(
    device: c.VkDevice,
) !c.VkDescriptorSetLayout {
    var vkDescriptorSetLayout: c.VkDescriptorSetLayout = undefined;

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
        &vkDescriptorSetLayout,
    ));

    defer std.log.info("Trying to init vulkan descriptor set layout OK", .{});
    return vkDescriptorSetLayout;
}

pub fn deinitVkDescriptorSetLayout(device: c.VkDevice, vkDescriptorSetLayout: c.VkDescriptorSetLayout) void {
    c.vkDestroyDescriptorSetLayout(device, vkDescriptorSetLayout, null);
    std.log.info("Deinit descriptor set layout OK", .{});
}

// =VkPipeline=========================================================================================================

pub fn initVkPipelineLayout(
    device: c.VkDevice,
    vkDescriptorSetLayout: c.VkDescriptorSetLayout,
) !c.VkPipelineLayout {
    var vkPipelineLayout: c.VkPipelineLayout = undefined;

    std.log.info("Trying to init pipeline layout...", .{});
    errdefer std.log.info("Trying to init pipeline layout failed", .{});

    try handleError(c.vkCreatePipelineLayout(
        device,
        &c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .setLayoutCount = 1,
            .pSetLayouts = &vkDescriptorSetLayout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &c.VkPushConstantRange{
                .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
                .offset = 0,
                .size = 8, //TODO: @sizeOf(Mat4),
            },
        },
        null,
        &vkPipelineLayout,
    ));

    defer std.log.info("Trying to init pipeline layout OK", .{});
    return vkPipelineLayout;
}

pub fn deinitVkPipelineLayout(
    device: c.VkDevice,
    vkPipelineLayout: c.VkPipelineLayout,
) void {
    c.vkDestroyPipelineLayout(device, vkPipelineLayout, null);
    defer std.log.info("Deinit vulkan pipeline layout OK", .{});
}

pub fn initVkGraphicsPipeline(
    device: c.VkDevice,
    vkSwapchainExtent: c.VkExtent2D,
    vkRenderPass: c.VkRenderPass,
    vkPipelineLayout: c.VkPipelineLayout,
    vkShaderModuleVert: c.VkShaderModule,
    vkShaderModuleFrag: c.VkShaderModule,
) !c.VkPipeline {
    var vkGraphicsPipeline: c.VkPipeline = undefined;

    std.log.info("Trying to init graphics pipeline...", .{});
    errdefer std.log.info("Trying to init graphics pipeline failed", .{});

    //
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
                    .module = vkShaderModuleVert,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
                c.VkPipelineShaderStageCreateInfo{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = vkShaderModuleFrag,
                    .pName = "main",
                    .pSpecializationInfo = null,
                },
            },
            .pVertexInputState = &c.VkPipelineVertexInputStateCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .vertexBindingDescriptionCount = Vertex.getVkBindingDiscription().len,
                .pVertexBindingDescriptions = &Vertex.getVkBindingDiscription(),
                .vertexAttributeDescriptionCount = Vertex.getVkAttributeDiscription().len,
                .pVertexAttributeDescriptions = &Vertex.getVkAttributeDiscription(),
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
                // NOTE: negative viewport trick
                .pViewports = &c.VkViewport{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(vkSwapchainExtent.width),
                    .height = @as(f32, @floatFromInt(vkSwapchainExtent.height)),
                    .minDepth = 0,
                    .maxDepth = 1,
                },
                .scissorCount = 1,
                .pScissors = &c.VkRect2D{
                    .offset = c.VkOffset2D{
                        .x = 0,
                        .y = 0,
                    },
                    .extent = vkSwapchainExtent,
                },
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
                    .blendEnable = c.VK_FALSE,
                    .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
                    .colorBlendOp = c.VK_BLEND_OP_ADD,
                    .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
                    .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
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
            .layout = vkPipelineLayout,
            .renderPass = vkRenderPass,
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

pub fn initFramebuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vkImageViews: []c.VkImageView,
    vkRenderPass: c.VkRenderPass,
    vkSwapchainExtent: c.VkExtent2D,
) ![]c.VkFramebuffer {
    std.log.info("Trying to init framebuffers...", .{});
    errdefer std.log.info("Trying to init framebuffers failed", .{});

    var vkFramebuffers = try allocator.alloc(c.VkFramebuffer, vkImageViews.len);

    for (0..vkImageViews.len) |i| {
        try handleError(c.vkCreateFramebuffer(
            device,
            &c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .renderPass = vkRenderPass,
                .attachmentCount = 1,
                .pAttachments = &[_]c.VkImageView{
                    vkImageViews[i],
                },
                .width = vkSwapchainExtent.width,
                .height = vkSwapchainExtent.height,
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

pub fn initCommandPool(
    device: c.VkDevice,
    selectedGraphicsQueueIndex: u32,
) !c.VkCommandPool {
    var vkCommandPool: c.VkCommandPool = undefined;

    std.log.info("Trying to init command pool...", .{});
    errdefer std.log.info("Trying to init command pool failed", .{});

    try handleError(c.vkCreateCommandPool(
        device,
        &c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = selectedGraphicsQueueIndex,
        },
        null,
        &vkCommandPool,
    ));

    defer std.log.info("Trying to init command pool OK", .{});
    return vkCommandPool;
}

pub fn deinitCommandPool(device: c.VkDevice, vkCommandPool: c.VkCommandPool) void {
    c.vkDestroyCommandPool(device, vkCommandPool, null);
    defer std.log.info("Deinit vulkan command pool OK", .{});
}

pub fn initCommandBuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
    bufferCount: usize,
) ![]c.VkCommandBuffer {
    var vkCommandBuffers: []c.VkCommandBuffer = undefined;

    std.log.info("Trying to init command buffers...", .{});
    errdefer std.log.info("Trying to init command buffers failed", .{});

    vkCommandBuffers = try allocator.alloc(c.VkCommandBuffer, bufferCount);

    try handleError(c.vkAllocateCommandBuffers(
        device,
        &c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = vkCommandPool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(bufferCount),
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

// =Buffers============================================================================================================

pub fn begOneTimeCommand(
    device: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
) !c.VkCommandBuffer {
    var vkCommandBuffer: c.VkCommandBuffer = undefined;
    try handleError(c.vkAllocateCommandBuffers(device, &c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = vkCommandPool,
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
    vkGraphicsQueue: c.VkQueue,
    vkCommandBuffer: c.VkCommandBuffer,
    vkCommandPool: c.VkCommandPool,
) !void {
    try handleError(c.vkEndCommandBuffer(vkCommandBuffer));

    try handleError(c.vkQueueSubmit(vkGraphicsQueue, 1, &c.VkSubmitInfo{
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

    try handleError(c.vkQueueWaitIdle(vkGraphicsQueue));

    c.vkFreeCommandBuffers(device, vkCommandPool, 1, &vkCommandBuffer);
}

pub fn bufferCopy(
    device: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
    vkGraphicsQueue: c.VkQueue,
    srcBuffer: c.VkBuffer,
    dstBuffer: c.VkBuffer,
    deviceSize: c.VkDeviceSize,
) !void {
    const vkCommandBuffer: c.VkCommandBuffer = try begOneTimeCommand(device, vkCommandPool);

    {
        c.vkCmdCopyBuffer(vkCommandBuffer, srcBuffer, dstBuffer, 1, &c.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = deviceSize,
        });
    }

    try endOneTimeCommand(device, vkGraphicsQueue, vkCommandBuffer, vkCommandPool);
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

// =VertexBufferSet===================================================================================================

pub const VertexBufferSet = struct {
    vkBuffers: []c.VkBuffer,
    vkBuffersMemory: []c.VkDeviceMemory,
    vkBuffersMapped: []*anyopaque,
    max_vertices: usize,
};

pub fn initVertexBufferSet(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
    max_vertices: usize,
    bufferCount: usize,
) !VertexBufferSet {
    std.log.info("Trying to init dynamic vertex buffers...", .{});
    errdefer std.log.info("Trying to init dynamic vertex buffers failed", .{});

    var vertex_buffer_set: VertexBufferSet = undefined;
    vertex_buffer_set.max_vertices = max_vertices;
    vertex_buffer_set.vkBuffers = try allocator.alloc(c.VkBuffer, bufferCount);
    vertex_buffer_set.vkBuffersMemory = try allocator.alloc(c.VkDeviceMemory, bufferCount);
    vertex_buffer_set.vkBuffersMapped = try allocator.alloc(*anyopaque, bufferCount);

    const buffer_size = @sizeOf(Vertex) * max_vertices;

    for (0..bufferCount) |i| {
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
    bufferCount: usize,
) !UniformBufferSet {
    std.log.info("Trying to init uniform buffers...", .{});
    errdefer std.log.info("Trying to init uniform buffers failed", .{});

    var uniform_buffer_set: UniformBufferSet = undefined;
    uniform_buffer_set.vkUniformBuffers = try allocator.alloc(c.VkBuffer, bufferCount);
    uniform_buffer_set.vkUniformBuffersMemory = try allocator.alloc(c.VkDeviceMemory, bufferCount);
    uniform_buffer_set.vkUniformBuffersMapped = try allocator.alloc(*anyopaque, bufferCount);

    for (0..bufferCount) |i| {
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
    var vkSemaphore: c.VkSemaphore = undefined;

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
        &vkSemaphore,
    ));

    defer std.log.info("Trying to init semaphore OK", .{});
    return vkSemaphore;
}

pub fn deinitVkSemaphore(
    device: c.VkDevice,
    vkSemaphore: c.VkSemaphore,
) void {
    c.vkDestroySemaphore(
        device,
        vkSemaphore,
        null,
    );

    errdefer std.log.info("Deinit vulkan semaphore OK", .{});
}

pub fn initVkSemaphores(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    count: usize,
) ![]c.VkSemaphore {
    var vkSemaphores: []c.VkSemaphore = undefined;

    std.log.info("Trying to init {} semaphores...", .{count});
    errdefer std.log.info("Trying to init {} semaphores failed", .{count});

    vkSemaphores = try allocator.alloc(c.VkSemaphore, count);
    for (vkSemaphores) |*vkSemaphore| {
        vkSemaphore.* = try initVkSemaphore(device);
    }

    defer std.log.info("Trying to init {} semaphores OK", .{count});
    return vkSemaphores;
}

pub fn deinitVkSemaphores(allocator: std.mem.Allocator, device: c.VkDevice, vkSemaphores: []c.VkSemaphore) void {
    for (vkSemaphores) |vkSemaphore| {
        deinitVkSemaphore(device, vkSemaphore);
    }
    allocator.free(vkSemaphores);

    defer std.log.info("Deinit {} semaphores OK", .{vkSemaphores.len});
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
            .pNext = null,
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
    vkDescriptorSetLayout: c.VkDescriptorSetLayout,
    vkDescriptorPool: c.VkDescriptorPool,
    vkUniformBuffers: []c.VkBuffer,
) ![]c.VkDescriptorSet {
    var vkDescriptorSets: []c.VkDescriptorSet = undefined;

    std.log.info("Trying to init descriptor sets...", .{});
    errdefer std.log.info("Trying to init descriptor sets failed", .{});

    const layouts = try allocator.alloc(c.VkDescriptorSetLayout, vkUniformBuffers.len);
    defer allocator.free(layouts);
    for (layouts) |*layout| {
        layout.* = vkDescriptorSetLayout;
    }

    vkDescriptorSets = try allocator.alloc(c.VkDescriptorSet, vkUniformBuffers.len);
    try handleError(c.vkAllocateDescriptorSets(device, &c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = vkDescriptorPool,
        .descriptorSetCount = @intCast(vkUniformBuffers.len),
        .pSetLayouts = @ptrCast(layouts),
    }, @ptrCast(vkDescriptorSets)));

    for (0..@intCast(vkUniformBuffers.len)) |i| {
        c.vkUpdateDescriptorSets(
            device,
            1,
            &[_]c.VkWriteDescriptorSet{
                c.VkWriteDescriptorSet{
                    .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .pNext = null,
                    .dstSet = vkDescriptorSets[i],
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
            },
            0,
            null,
        );
    }

    defer std.log.info("Trying to init descriptor sets OK", .{});
    return vkDescriptorSets;
}

pub fn deinitVkDescriptorSets(
    allocator: std.mem.Allocator,
    vkDescriptorSets: []c.VkDescriptorSet,
) void {
    allocator.free(vkDescriptorSets);

    defer std.log.info("Deinit descriptor sets OK", .{});
}
