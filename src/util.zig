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

/// Debug callback for vulkan
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

// =VkInstance=========================================================================================================

fn getSDLRequestedVkInstanceExtensions(
    allocator: std.mem.Allocator,
) !std.ArrayList([*c]const u8) {
    std.log.debug("Trying to enumerate SDL3 requested vulkan extensions...", .{});
    errdefer std.log.err("Trying to enumerate SDL3 requested vulkan extensions failed", .{});

    var count: u32 = 0;
    const extensions_base = c.SDL_Vulkan_GetInstanceExtensions(&count);
    std.log.debug("SDL requests '{}' extensions in total", .{count});
    var extensions = try std.ArrayList([*c]const u8).initCapacity(allocator, count);
    for (0..count) |i| {
        std.log.debug("SDL requests extension '{s}'", .{extensions_base[i]});
        try extensions.append(allocator, extensions_base[i]);
    }

    defer std.log.debug("Trying to enumerate SDL3 requested vulkan extensions OK", .{});
    return extensions;
}

fn getSupportedVkInstanceExtensions(
    allocator: std.mem.Allocator,
) !std.ArrayList([*c]const u8) {
    std.log.debug("Trying to enumerate supported vulkan instance extensions...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan instance extensions failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateInstanceExtensionProperties(null, &count, null));
    std.log.debug("Vulkan reports '{}' instance extenions supported in total", .{count});

    const extension_properties = try allocator.alloc(c.VkExtensionProperties, count);
    defer allocator.free(extension_properties);
    try handleError(c.vkEnumerateInstanceExtensionProperties(null, &count, @ptrCast(extension_properties)));

    var extensions = try std.ArrayList([*c]const u8).initCapacity(allocator, count);
    for (extension_properties) |extensionProperty| {
        const name = std.mem.sliceTo(&extensionProperty.extensionName, 0);
        std.log.debug("Support exists for instance extension '{s}'", .{name});
        try extensions.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan instance extensions OK", .{});
    return extensions;
}

fn checkRequestedVkInstanceExtensionsSupported(
    allocator: std.mem.Allocator,
    requestedExtensions: std.ArrayList([*c]const u8),
) !void {
    std.log.debug("Trying to checking if requested vulkan instance extensions are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan instance extensions are supported failed", .{});

    // query supported vulkan instance extensions
    var supported_extensions = try getSupportedVkInstanceExtensions(allocator);
    defer {
        for (supported_extensions.items) |s| allocator.free(std.mem.span(s));
        supported_extensions.deinit(allocator);
    }

    // find each extension in the supported extension set
    for (requestedExtensions.items) |requested| {
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

fn getSupportedVkInstanceLayers(
    allocator: std.mem.Allocator,
) !std.ArrayList([*c]const u8) {
    std.log.debug("Trying to enumerate supported vulkan instance layers...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan instance layers failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateInstanceLayerProperties(&count, null));
    std.log.debug("Vulkan reports '{}' instance layers supported in total", .{count});

    const layer_properties = try allocator.alloc(c.VkLayerProperties, count);
    defer allocator.free(layer_properties);
    try handleError(c.vkEnumerateInstanceLayerProperties(&count, @ptrCast(layer_properties)));

    var layers = try std.ArrayList([*c]const u8).initCapacity(allocator, count);
    for (layer_properties) |layer_property| {
        const name = std.mem.sliceTo(&layer_property.layerName, 0);
        std.log.debug("Support exists for instance layer '{s}'", .{name});
        try layers.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan instance layers OK", .{});
    return layers;
}

fn checkRequestedVkInstanceLayersSupported(
    allocator: std.mem.Allocator,
    requestedLayers: std.ArrayList([*c]const u8),
) !void {
    std.log.debug("Trying to checking if requested vulkan layers are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan layers are supported failed", .{});

    var supported_layers = try getSupportedVkInstanceLayers(allocator);
    defer {
        for (supported_layers.items) |s| allocator.free(std.mem.span(s));
        supported_layers.deinit(allocator);
    }

    for (requestedLayers.items) |requested| {
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

pub fn initVkInstance(
    allocator: std.mem.Allocator,
) !c.VkInstance {
    var vk_instance: c.VkInstance = undefined;

    std.log.info("Trying to init vulkan instance...", .{});
    errdefer std.log.err("Trying to init vulkan instance failed", .{});

    // create our list of requested instance extensions
    var extensions = try getSDLRequestedVkInstanceExtensions(allocator);
    defer extensions.deinit(allocator);
    try extensions.append(allocator, c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    try checkRequestedVkInstanceExtensionsSupported(allocator, extensions);

    // create our list of requested instance layers
    var layers = try std.ArrayList([*c]const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
    try checkRequestedVkInstanceLayersSupported(allocator, layers);

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
                    c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | //
                    c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,

                .pfnUserCallback = vkDebugCallback,
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
            .enabledLayerCount = @intCast(layers.items.len),
            .ppEnabledLayerNames = @ptrCast(layers.items),

            // pass our extensions
            .enabledExtensionCount = @intCast(extensions.items.len),
            .ppEnabledExtensionNames = @ptrCast(extensions.items),
        }, null, @ptrCast(&vk_instance)),
    );

    defer std.log.info("Trying to init vulkan instance OK", .{});

    return vk_instance;
}

pub fn deinitVkInstance(
    vkInstance: c.VkInstance,
) void {
    c.vkDestroyInstance(vkInstance, null);

    defer std.log.info("Deinit vulkan instance OK", .{});
}

// =VkSurface==========================================================================================================

pub fn initVkSurface(
    window: *c.SDL_Window,
    vk_instance: c.VkInstance,
) !c.VkSurfaceKHR {
    var vk_surface: c.VkSurfaceKHR = undefined;

    std.log.info("Trying to init vulkan surface...", .{});
    errdefer std.log.err("Trying to init vulkan surface failed", .{});

    try handleError(c.SDL_Vulkan_CreateSurface(window, vk_instance, null, &vk_surface));

    defer std.log.info("Trying to init vulkan surface OK", .{});
    return vk_surface;
}

pub fn deinitVkSurface(
    vk_instance: c.VkInstance,
    vk_surface: c.VkSurfaceKHR,
) void {
    c.SDL_Vulkan_DestroySurface(vk_instance, vk_surface, null);

    defer std.log.info("Deinit vulkan surface OK", .{});
}

// =VkPhysicalDevice===================================================================================================

pub fn getVkExtent(
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
    defer std.log.debug("Trying to get extent OK", .{});
    return .{
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
}

fn selectSupportedVkFormats(
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkFormats: []c.VkFormat,
    vkImageTiling: c.VkImageTiling,
    vkFormatFeatureFlags: c.VkFormatFeatureFlags,
) !c.VkFormat {
    for (vkFormats) |vkFormat| {
        var vkFormatProperties: c.VkFormatProperties = undefined;
        c.vkGetPhysicalDeviceFormatProperties(vkPhysicalDevice, vkFormat, &vkFormatProperties);

        if (vkImageTiling == c.VK_IMAGE_TILING_LINEAR and //
            (vkFormatProperties.linearTilingFeatures & vkFormatFeatureFlags) == vkFormatFeatureFlags)
        {
            return vkFormat;
        }

        if (vkImageTiling == c.VK_IMAGE_TILING_OPTIMAL and //
            (vkFormatProperties.optimalTilingFeatures & vkFormatFeatureFlags) == vkFormatFeatureFlags)
        {
            return vkFormat;
        }
    }

    return error.VkErrorFormatUnsupported;
}

pub fn getPreferredVkDepthFormat(
    vkPhysicalDevice: c.VkPhysicalDevice,
) !c.VkFormat {
    return try selectSupportedVkFormats(
        vkPhysicalDevice,
        @ptrCast(@constCast(&[_]c.VkFormat{
            c.VK_FORMAT_D32_SFLOAT,
            c.VK_FORMAT_D32_SFLOAT_S8_UINT,
            c.VK_FORMAT_D24_UNORM_S8_UINT,
        })),
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );
}

pub fn getPreferredVkSurfaceFormat(
    allocator: std.mem.Allocator,
    vk_physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkSurfaceFormatKHR {
    var vk_surface_format: c.VkSurfaceFormatKHR = undefined;

    std.log.debug("Trying to get preferred surface format...", .{});
    errdefer std.log.err("Trying to get preferred surface format failed", .{});

    const supportedSurfaceFormats = try getSupportedVkDeviceSurfaceFormats(
        allocator,
        vk_physical_device,
        surface,
    );

    defer allocator.free(supportedSurfaceFormats);

    vk_surface_format = selectPreferredSurfaceFormat(supportedSurfaceFormats);

    defer std.log.debug("Trying to get preferred surface format OK", .{});

    return vk_surface_format;
}

pub fn getPreferredVkPresentMode(
    allocator: std.mem.Allocator,
    vk_physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkPresentModeKHR {
    var vk_present_mode: c.VkPresentModeKHR = undefined;

    std.log.debug("Trying to get preferred surface format...", .{});
    errdefer std.log.err("Trying to get preferred surface format failed", .{});

    const supportedPresentModes = try getSupportedVkDeviceSurfacePresentModes(
        allocator,
        vk_physical_device,
        surface,
    );

    defer allocator.free(supportedPresentModes);

    vk_present_mode = selectPreferredSurfacePresentMode(supportedPresentModes);

    defer std.log.debug("Trying to get preferred surface format OK", .{});

    return vk_present_mode;
}

pub fn getPhysicalDeviceSurfaceCapabilities(
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkSurface: c.VkSurfaceKHR,
) !c.VkSurfaceCapabilitiesKHR {
    std.log.debug("Trying to get surface capabilities...", .{});
    errdefer std.log.err("Trying to get surface capabilities failed", .{});

    var vkSurfaceCapabilities = c.VkSurfaceCapabilitiesKHR{};
    try handleError(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        vkPhysicalDevice,
        vkSurface,
        &vkSurfaceCapabilities,
    ));

    defer std.log.debug("Trying to get surface capabilities OK", .{});
    return vkSurfaceCapabilities;
}

fn getQueueFamilyProperties(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    std.log.debug("Trying to get all queue family properties...", .{});
    errdefer std.log.err("Trying to get all queue family properties failed", .{});

    var count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(vkPhysicalDevice, &count, null);
    const queueFamilyProperties = try allocator.alloc(c.VkQueueFamilyProperties, count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(vkPhysicalDevice, &count, @ptrCast(queueFamilyProperties));

    defer std.log.debug("Trying to get all queue family properties OK", .{});
    return queueFamilyProperties;
}

pub fn findGraphicsQueueIndex(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
) !u32 {
    std.log.debug("Trying to get graphics queue index...", .{});
    errdefer std.log.err("Trying to get graphics queue index failed", .{});

    const queueFamilyProperties = try getQueueFamilyProperties(allocator, vkPhysicalDevice);
    defer allocator.free(queueFamilyProperties);

    var graphicsQueueIndex: u32 = 0;
    var graphicsQueueFound = false;
    for (0..queueFamilyProperties.len) |i| {
        if (queueFamilyProperties[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT > 0) {
            graphicsQueueIndex = @intCast(i);
            graphicsQueueFound = true;
            break;
        }
    }

    if (!graphicsQueueFound) {
        std.log.err("Could not find queue with graphics bit set", .{});
        return error.VkQueueNotFound;
    }

    std.log.debug("Using graphics queue index '{}'", .{graphicsQueueIndex});

    defer std.log.debug("Trying to get graphics queue index OK", .{});
    return graphicsQueueIndex;
}

pub fn findPresentQueueIndex(
    allocator: std.mem.Allocator,
    vkSurface: c.VkSurfaceKHR,
    vkPhysicalDevice: c.VkPhysicalDevice,
) !u32 {
    std.log.debug("Trying to get present queue index...", .{});
    errdefer std.log.err("Trying to get present queue index failed", .{});

    const queueFamilyProperties = try getQueueFamilyProperties(allocator, vkPhysicalDevice);
    defer allocator.free(queueFamilyProperties);

    var presentQueueIndex: u32 = 0;
    var presentQueueFound = false;
    for (0..queueFamilyProperties.len) |j| {
        var vkBoolHasPresentSupport: c.VkBool32 = 0;
        try handleError(c.vkGetPhysicalDeviceSurfaceSupportKHR(
            vkPhysicalDevice,
            @intCast(j),
            vkSurface,
            &vkBoolHasPresentSupport,
        ));
        if (vkBoolHasPresentSupport > 0) {
            presentQueueIndex = @intCast(j);
            presentQueueFound = true;
            break;
        }
    }

    if (!presentQueueFound) {
        std.log.err("Could not find queue with present bit set", .{});
        return error.VkQueueNotFound;
    }

    std.log.debug("Using present queue index '{}'", .{presentQueueIndex});

    defer std.log.debug("Trying to get present queue index OK", .{});
    return presentQueueIndex;
}

pub fn initVkPhysicalDevice(
    allocator: std.mem.Allocator,
    vk_instance: c.VkInstance,
    vk_surface: c.VkSurfaceKHR,
) !c.VkPhysicalDevice {
    var vk_physical_device: c.VkPhysicalDevice = undefined;

    std.log.info("Trying to select vulkan physical device...", .{});
    errdefer std.log.err("Trying to select vulkan physical device failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumeratePhysicalDevices(vk_instance, &count, null));
    std.log.debug("Vulkan reports '{}' physical devices in total", .{count});

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, count);
    defer allocator.free(physical_devices);
    try handleError(c.vkEnumeratePhysicalDevices(vk_instance, &count, @ptrCast(physical_devices)));

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

        const queueFamilyProperties = try getQueueFamilyProperties(allocator, physical_devices[i]);
        defer allocator.free(queueFamilyProperties);

        // check for graphics bit
        var hasGraphicsBit = false;
        for (0..queueFamilyProperties.len) |j| {
            if (queueFamilyProperties[j].queueFlags & c.VK_QUEUE_GRAPHICS_BIT > 0) {
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
        for (0..queueFamilyProperties.len) |j| {
            var vkBoolHasPresentSupport: c.VkBool32 = 0;
            try handleError(c.vkGetPhysicalDeviceSurfaceSupportKHR(
                physical_devices[i],
                @intCast(j),
                vk_surface,
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

    vk_physical_device = physical_devices[highestScoreIndex];
    var properties = c.VkPhysicalDeviceProperties{};
    c.vkGetPhysicalDeviceProperties(physical_devices[highestScoreIndex], &properties);

    std.log.info("Selecting physical device with name {s}", .{properties.deviceName});

    defer std.log.info("Trying to select vulkan physical device OK", .{});

    return vk_physical_device;
}

// =VkDevice===========================================================================================================

fn selectPreferredSurfacePresentMode(
    supportedPresentModes: []c.VkSurfacePresentModeKHR,
) c.VkPresentModeKHR {
    std.log.info("Trying to select vulkan swapchain present mode...", .{});
    errdefer std.log.err("Trying to select vulkan swapchain present mode failed", .{});

    var selectedMode: c.VkPresentModeKHR = undefined;
    for (supportedPresentModes) |mode| {
        if (mode.presentMode == @as(c.VkPresentModeKHR, @intCast(c.VK_PRESENT_MODE_MAILBOX_KHR))) {
            defer std.log.debug("Selecting present mode 'VK_PRESENT_MODE_MAILBOX_KHR'", .{});
            selectedMode = mode.presentMode;

            defer std.log.info("Trying to select vulkan swapchain present mode OK", .{});
            return selectedMode;
        }
    }

    selectedMode = c.VK_PRESENT_MODE_FIFO_KHR;
    defer std.log.debug("Selecting present mode 'VK_PRESENT_MODE_FIFO_KHR'", .{});

    defer std.log.info("Trying to select vulkan swapchain present mode OK", .{});
    return selectedMode;
}

fn getSupportedVkDeviceSurfacePresentModes(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkSurface: c.VkSurfaceKHR,
) ![]c.VkSurfacePresentModeKHR {
    std.log.info("Trying to enumerate supported vulkan device surface present modes...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device surface present modes failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(vkPhysicalDevice, vkSurface, &count, null));
    std.log.debug("Vulkan reports '{}' device surfaces present modes in total", .{count});

    const surfacePresentModes = try allocator.alloc(c.VkSurfacePresentModeKHR, count);
    try handleError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
        vkPhysicalDevice,
        vkSurface,
        &count,
        @ptrCast(surfacePresentModes),
    ));

    defer std.log.info("Trying to enumerate supported vulkan device surface present modes OK", .{});
    return surfacePresentModes;
}

fn getSupportedVkDeviceSurfaceFormats(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkSurface: c.VkSurfaceKHR,
) ![]c.VkSurfaceFormatKHR {
    std.log.debug("Trying to enumerate supported vulkan device surface formats...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device surface formats failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &count, null));
    std.log.debug("Vulkan reports '{}' device surfaces formats in total", .{count});

    const surfaceFormats = try allocator.alloc(c.VkSurfaceFormatKHR, count);
    try handleError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &count, @ptrCast(surfaceFormats)));

    defer std.log.debug("Trying to enumerate supported vulkan device surface formats OK", .{});
    return surfaceFormats;
}

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

    defer std.log.debug("Selecting first format we found", .{});
    defer std.log.debug("Trying to select vulkan surface format OK", .{});
    return supportedFormats[0];
}

fn getSupportedVkDeviceLayers(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
) !std.ArrayList([*c]const u8) {
    std.log.debug("Trying to enumerate supported vulkan device layers...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device layers failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateDeviceLayerProperties(vkPhysicalDevice, &count, null));
    std.log.debug("Vulkan reports '{}' device layers supported in total", .{count});

    const layerProperties = try allocator.alloc(c.VkLayerProperties, count);
    defer allocator.free(layerProperties);
    try handleError(c.vkEnumerateDeviceLayerProperties(vkPhysicalDevice, &count, @ptrCast(layerProperties)));

    var layers = try std.ArrayList([*c]const u8).initCapacity(allocator, count);
    for (layerProperties) |layerProperty| {
        const name = std.mem.sliceTo(&layerProperty.layerName, 0);
        std.log.debug("Support exists for device layer '{s}'", .{name});
        try layers.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan device layers OK", .{});
    return layers;
}

fn getSupportedVkDeviceExtensions(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
) !std.ArrayList([*c]const u8) {
    std.log.debug("Trying to enumerate supported vulkan device extensions...", .{});
    errdefer std.log.err("Trying to enumerate supported vulkan device extensions failed", .{});

    var count: u32 = 0;
    try handleError(c.vkEnumerateDeviceExtensionProperties(vkPhysicalDevice, null, &count, null));
    std.log.debug("Vulkan reports '{}' device extenions supported in total", .{count});

    const extensionProperties = try allocator.alloc(c.VkExtensionProperties, count);
    defer allocator.free(extensionProperties);
    try handleError(c.vkEnumerateDeviceExtensionProperties(
        vkPhysicalDevice,
        null,
        &count,
        @ptrCast(extensionProperties),
    ));

    var extensions = try std.ArrayList([*c]const u8).initCapacity(allocator, count);
    for (extensionProperties) |extensionProperty| {
        const name = std.mem.sliceTo(&extensionProperty.extensionName, 0);
        std.log.debug("Support exists for device extension '{s}'", .{name});
        try extensions.append(allocator, try allocator.dupeZ(u8, name));
    }

    defer std.log.debug("Trying to enumerate supported vulkan device extensions OK", .{});
    return extensions;
}

fn checkRequestedVkDeviceExtensionsSupported(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
    requestedExtensions: std.ArrayList([*c]const u8),
) !void {
    std.log.debug("Trying to checking if requested vulkan device extensions are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan device extensions are supported failed", .{});

    // note that we own the memory here
    var supportedExtensions = try getSupportedVkDeviceExtensions(allocator, vkPhysicalDevice);
    defer {
        for (supportedExtensions.items) |s| allocator.free(std.mem.span(s));
        supportedExtensions.deinit(allocator);
    }

    for (requestedExtensions.items) |requested| {
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

fn checkRequestedVkDeviceLayersSupported(
    allocator: std.mem.Allocator,
    vkPhysicalDevice: c.VkPhysicalDevice,
    requestedLayers: std.ArrayList([*c]const u8),
) !void {
    std.log.debug("Trying to checking if requested vulkan layers are supported...", .{});
    errdefer std.log.err("Trying to checking if requested vulkan layers are supported failed", .{});

    // note that we own the memory here
    var supportedLayers = try getSupportedVkDeviceLayers(allocator, vkPhysicalDevice);
    defer {
        for (supportedLayers.items) |s| allocator.free(std.mem.span(s));
        supportedLayers.deinit(allocator);
    }

    for (requestedLayers.items) |requested| {
        var found = false;
        for (supportedLayers.items) |supported| {
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

pub fn initVkDevice(
    allocator: std.mem.Allocator,
    vk_graphics_queue_index: u32,
    vk_present_queue_index: u32,
    vk_physical_device: c.VkPhysicalDevice,
) !c.VkDevice {
    var vk_device: c.VkDevice = undefined;

    std.log.info("Trying to init vulkan device...", .{});
    errdefer std.log.err("Trying to init vulkan device failed", .{});

    // create our list of requested instance extensions
    var extensions = try std.ArrayList([*c]const u8).initCapacity(allocator, 0);
    defer extensions.deinit(allocator);
    try extensions.append(allocator, c.VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    try checkRequestedVkDeviceExtensionsSupported(allocator, vk_physical_device, extensions);

    // create our list of requested instance layers
    var layers = try std.ArrayList([*c]const u8).initCapacity(allocator, 0);
    defer layers.deinit(allocator);
    try layers.append(allocator, "VK_LAYER_KHRONOS_validation");
    try checkRequestedVkDeviceLayersSupported(allocator, vk_physical_device, layers);

    // populate queue families
    const queuePriorities: f32 = 1.0;
    var queueFamilyCreateInfos = try std.ArrayList(c.VkDeviceQueueCreateInfo).initCapacity(allocator, 0);
    defer queueFamilyCreateInfos.deinit(allocator);

    // graphics queue family
    try queueFamilyCreateInfos.append(allocator, c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = vk_graphics_queue_index,
        .queueCount = 1,
        .pQueuePriorities = &queuePriorities,
    });

    // present queue family
    if (vk_present_queue_index != vk_graphics_queue_index) {
        try queueFamilyCreateInfos.append(allocator, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = vk_present_queue_index,
            .queueCount = 1,
            .pQueuePriorities = &queuePriorities,
        });
    }

    // create device
    try handleError(c.vkCreateDevice(vk_physical_device, &c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,

        // specify queue families to create, where we can later retrieve a handle for
        .queueCreateInfoCount = @intCast(queueFamilyCreateInfos.items.len),
        .pQueueCreateInfos = @ptrCast(queueFamilyCreateInfos.items),

        // layers to enable
        .enabledLayerCount = @intCast(layers.items.len),
        .ppEnabledLayerNames = @ptrCast(layers.items),

        // extensions to enable
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = @ptrCast(extensions.items),

        // features to enable
        .pEnabledFeatures = &c.VkPhysicalDeviceFeatures{
            .samplerAnisotropy = c.VK_TRUE,
        },
    }, null, &vk_device));

    defer std.log.info("Trying to init vulkan device OK", .{});
    return vk_device;
}

pub fn deinitVkDevice(vk_device: c.VkDevice) void {
    c.vkDestroyDevice(vk_device, null);

    defer std.log.info("Deinit vulkan device OK", .{});
}

// =VkSwapchain========================================================================================================

pub fn initVkSwapchain(
    vkDevice: c.VkDevice,
    vkSurface: c.VkSurfaceKHR,
    vkSurfaceCapabilities: c.VkSurfaceCapabilitiesKHR,
    selectedSurfaceFormat: c.VkSurfaceFormatKHR,
    selectedSwapExtent: c.VkExtent2D,
    selectedPresentMode: c.VkPresentModeKHR,
    graphicsQueueIndex: u32,
    presentQueueIndex: u32,
) !c.VkSwapchainKHR {
    var vk_swapchain: c.VkSwapchainKHR = undefined;

    std.log.info("Trying to init vulkan swapchain...", .{});
    errdefer std.log.err("Trying to init vulkan swapchain failed", .{});

    const imageSharingMode: u32 = blk: {
        if (graphicsQueueIndex != presentQueueIndex) {
            break :blk c.VK_SHARING_MODE_CONCURRENT;
        } else {
            break :blk c.VK_SHARING_MODE_EXCLUSIVE;
        }
    };

    const queueFamilyIndexCount: u32 = blk: {
        if (graphicsQueueIndex != presentQueueIndex) {
            break :blk 2;
        } else {
            break :blk 0;
        }
    };

    const pQueueFamilyIndices: [*c]const u32 = blk: {
        if (graphicsQueueIndex != presentQueueIndex) {
            break :blk @ptrCast(&[_]u32{ graphicsQueueIndex, presentQueueIndex });
        } else {
            break :blk null;
        }
    };

    // initialize
    try handleError(c.vkCreateSwapchainKHR(vkDevice, &c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = vkSurface,
        .minImageCount = vkSurfaceCapabilities.minImageCount,
        .imageFormat = selectedSurfaceFormat.format,
        .imageColorSpace = selectedSurfaceFormat.colorSpace,
        .imageExtent = selectedSwapExtent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = @intCast(imageSharingMode),
        .queueFamilyIndexCount = @intCast(queueFamilyIndexCount),
        .pQueueFamilyIndices = pQueueFamilyIndices,
        .preTransform = vkSurfaceCapabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = selectedPresentMode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    }, null, &vk_swapchain));

    defer std.log.info("Trying to init vulkan swapchain OK", .{});
    return vk_swapchain;
}

pub fn deinitVkSwapchain(
    vkDevice: c.VkDevice,
    vkSwapchain: c.VkSwapchainKHR,
) void {
    c.vkDestroySwapchainKHR(vkDevice, vkSwapchain, null);
    defer std.log.info("Deinit vulkan swapchain OK", .{});
}

// =VkImages===========================================================================================================

/// Memory of the image inside the swapchain
pub fn initVkImages(
    allocator: std.mem.Allocator,
    vkDevice: c.VkDevice,
    vkSwapchain: c.VkSwapchainKHR,
) ![]c.VkImage {
    std.log.info("Trying to get images...", .{});
    errdefer std.log.info("Trying to get images failed", .{});

    var count: u32 = 0;
    try handleError(c.vkGetSwapchainImagesKHR(vkDevice, vkSwapchain, &count, null));
    const images = try allocator.alloc(c.VkImage, count);
    try handleError(c.vkGetSwapchainImagesKHR(vkDevice, vkSwapchain, &count, @ptrCast(images)));

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
    vkDevice: c.VkDevice,
    vkImages: []c.VkImage,
    selectedSurfaceFormat: c.VkSurfaceFormatKHR,
) ![]c.VkImageView {
    std.log.info("Trying to get image views...", .{});
    errdefer std.log.info("Trying to get image views failed", .{});

    const vkImageViews = try allocator.alloc(c.VkImageView, vkImages.len);
    for (0..vkImages.len) |i| {
        try handleError(c.vkCreateImageView(vkDevice, &c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = vkImages[i],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = selectedSurfaceFormat.format,
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

pub fn deinitVkImageViews(allocator: std.mem.Allocator, vkDevice: c.VkDevice, vkImageViews: []c.VkImageView) void {
    for (0..vkImageViews.len) |i| {
        c.vkDestroyImageView(vkDevice, vkImageViews[i], null);
    }
    allocator.free(vkImageViews);

    defer std.log.info("Deinit image views OK", .{});
}

// =Shaders============================================================================================================
pub fn initVkShaderModule(comptime path: anytype, vkDevice: c.VkDevice) !c.VkShaderModule {
    var vk_shader_module: c.VkShaderModule = undefined;

    std.log.info("Trying to init shader module with path '{s}'...", .{path});
    errdefer std.log.info("Trying to init shader module with path '{s}' failed", .{path});

    const code = @embedFile(path);
    try handleError(c.vkCreateShaderModule(vkDevice, &c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len,
        .pCode = @ptrCast(@alignCast(code)),
    }, null, &vk_shader_module));

    defer std.log.info("Trying to init shader module with path '{s}' OK", .{path});
    return vk_shader_module;
}

pub fn deinitVkShaderModule(
    vkDevice: c.VkDevice,
    vkShaderModule: c.VkShaderModule,
) void {
    c.vkDestroyShaderModule(vkDevice, vkShaderModule, null);

    defer std.log.info("Deinit vulkan shader module OK", .{});
}

// =GraphicsPipeline===================================================================================================

pub fn initVkRenderPass(
    vkDevice: c.VkDevice,
    vkSurfaceFormat: c.VkSurfaceFormatKHR,
) !c.VkRenderPass {
    var vk_render_pass: c.VkRenderPass = undefined;

    std.log.info("Trying to init render pass...", .{});
    errdefer std.log.info("Trying to init render pass failed", .{});

    try handleError(c.vkCreateRenderPass(vkDevice, &c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &[_]c.VkAttachmentDescription{
            c.VkAttachmentDescription{
                .flags = 0,
                .format = vkSurfaceFormat.format,
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
    }, null, &vk_render_pass));

    defer std.log.info("Trying to init render pass...", .{});
    return vk_render_pass;
}

pub fn deinitVkRenderPass(
    vkDevice: c.VkDevice,
    vkRenderPass: c.VkRenderPass,
) void {
    c.vkDestroyRenderPass(vkDevice, vkRenderPass, null);

    defer std.log.info("Deinit vulkan render pass OK", .{});
}

pub fn initVkDescriptorSetLayout(
    vkDevice: c.VkDevice,
) !c.VkDescriptorSetLayout {
    var vkDescriptorSetLayout: c.VkDescriptorSetLayout = undefined;

    std.log.info("Trying to init vulkan descriptor set layout...", .{});
    errdefer std.log.err("Trying to init vulkan descriptor set layout", .{});

    try handleError(c.vkCreateDescriptorSetLayout(
        vkDevice,
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

pub fn deinitVkDescriptorSetLayout(vkDevice: c.VkDevice, vkDescriptorSetLayout: c.VkDescriptorSetLayout) void {
    c.vkDestroyDescriptorSetLayout(vkDevice, vkDescriptorSetLayout, null);
    std.log.info("Deinit descriptor set layout OK", .{});
}

pub fn initVkPipelineLayout(
    vkDevice: c.VkDevice,
    vkDescriptorSetLayout: c.VkDescriptorSetLayout,
) !c.VkPipelineLayout {
    var vkPipelineLayout: c.VkPipelineLayout = undefined;

    std.log.info("Trying to init pipeline layout...", .{});
    errdefer std.log.info("Trying to init pipeline layout failed", .{});

    try handleError(c.vkCreatePipelineLayout(
        vkDevice,
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
    vkDevice: c.VkDevice,
    vkPipelineLayout: c.VkPipelineLayout,
) void {
    c.vkDestroyPipelineLayout(vkDevice, vkPipelineLayout, null);
    defer std.log.info("Deinit vulkan pipeline layout OK", .{});
}

pub fn initVkGraphicsPipeline(
    vkDevice: c.VkDevice,
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
        vkDevice,
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

pub fn deinitVkPipeline(vkDevice: c.VkDevice, vkPipeline: c.VkPipeline) void {
    c.vkDestroyPipeline(vkDevice, vkPipeline, null);
    defer std.log.info("Deinit vulkan pipeline OK", .{});
}

// =FrameBuffers=======================================================================================================

pub fn initFramebuffers(
    allocator: std.mem.Allocator,
    vkDevice: c.VkDevice,
    vkImageViews: []c.VkImageView,
    vkRenderPass: c.VkRenderPass,
    vkSwapchainExtent: c.VkExtent2D,
) ![]c.VkFramebuffer {
    std.log.info("Trying to init framebuffers...", .{});
    errdefer std.log.info("Trying to init framebuffers failed", .{});

    var vkFramebuffers = try allocator.alloc(c.VkFramebuffer, vkImageViews.len);

    for (0..vkImageViews.len) |i| {
        try handleError(c.vkCreateFramebuffer(
            vkDevice,
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
    vkDevice: c.VkDevice,
    vkFramebuffers: []c.VkFramebuffer,
) void {
    for (0..vkFramebuffers.len) |i| {
        c.vkDestroyFramebuffer(vkDevice, vkFramebuffers[i], null);
    }

    allocator.free(vkFramebuffers);

    defer std.log.info("Deinit vulkan framebuffers OK", .{});
}

// =CommandBuffers=====================================================================================================

pub fn initCommandPool(
    vkDevice: c.VkDevice,
    selectedGraphicsQueueIndex: u32,
) !c.VkCommandPool {
    var vkCommandPool: c.VkCommandPool = undefined;

    std.log.info("Trying to init command pool...", .{});
    errdefer std.log.info("Trying to init command pool failed", .{});

    try handleError(c.vkCreateCommandPool(
        vkDevice,
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

pub fn deinitCommandPool(vkDevice: c.VkDevice, vkCommandPool: c.VkCommandPool) void {
    c.vkDestroyCommandPool(vkDevice, vkCommandPool, null);
    defer std.log.info("Deinit vulkan command pool OK", .{});
}

pub fn initCommandBuffers(
    allocator: std.mem.Allocator,
    vkDevice: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
    bufferCount: usize,
) ![]c.VkCommandBuffer {
    var vkCommandBuffers: []c.VkCommandBuffer = undefined;

    std.log.info("Trying to init command buffers...", .{});
    errdefer std.log.info("Trying to init command buffers failed", .{});

    vkCommandBuffers = try allocator.alloc(c.VkCommandBuffer, bufferCount);

    try handleError(c.vkAllocateCommandBuffers(
        vkDevice,
        &c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = vkCommandPool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(bufferCount),
        },
        @ptrCast(vkCommandBuffers),
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
    vkDevice: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
) !c.VkCommandBuffer {
    var vkCommandBuffer: c.VkCommandBuffer = undefined;
    try handleError(c.vkAllocateCommandBuffers(vkDevice, &c.VkCommandBufferAllocateInfo{
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
    vkDevice: c.VkDevice,
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

    c.vkFreeCommandBuffers(vkDevice, vkCommandPool, 1, &vkCommandBuffer);
}

pub fn bufferCopy(
    vkDevice: c.VkDevice,
    vkCommandPool: c.VkCommandPool,
    vkGraphicsQueue: c.VkQueue,
    srcBuffer: c.VkBuffer,
    dstBuffer: c.VkBuffer,
    vkDeviceSize: c.VkDeviceSize,
) !void {
    const vkCommandBuffer: c.VkCommandBuffer = try begOneTimeCommand(vkDevice, vkCommandPool);

    {
        c.vkCmdCopyBuffer(vkCommandBuffer, srcBuffer, dstBuffer, 1, &c.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = vkDeviceSize,
        });
    }

    try endOneTimeCommand(vkDevice, vkGraphicsQueue, vkCommandBuffer, vkCommandPool);
}

fn findMemoryType(
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkTypeFilter: u32,
    vkMemoryPropertyFlags: c.VkMemoryPropertyFlags,
) !u32 {
    var vkPhysicalDeviceMemoryProperties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(vkPhysicalDevice, &vkPhysicalDeviceMemoryProperties);

    for (0..vkPhysicalDeviceMemoryProperties.memoryTypeCount) |i| {
        const mask = @as(u32, 1) << @as(u5, @intCast(i));
        if ((vkTypeFilter & mask) > 0 and
            (vkPhysicalDeviceMemoryProperties.memoryTypes[i].propertyFlags & vkMemoryPropertyFlags) == //
                vkMemoryPropertyFlags)
        {
            return @intCast(i);
        }
    }

    return error.VkError;
}

fn initBuffer(
    vkDevice: c.VkDevice,
    vkPhysicalDevice: c.VkPhysicalDevice,
    vkDeviceSize: c.VkDeviceSize,
    vkBufferUsageFlags: c.VkBufferUsageFlags,
    vkMemoryPropertyFlags: c.VkMemoryPropertyFlags,
    vkBuffer: *c.VkBuffer,
    vkBufferMemory: *c.VkDeviceMemory,
) !void {
    std.log.info("Trying to init buffer...", .{});
    errdefer std.log.info("Trying to init buffer failed", .{});

    try handleError(c.vkCreateBuffer(
        vkDevice,
        &c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = vkDeviceSize,
            .usage = vkBufferUsageFlags,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        },
        null,
        vkBuffer,
    ));

    var vkMemoryRequirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(vkDevice, vkBuffer.*, &vkMemoryRequirements);

    try handleError(c.vkAllocateMemory(vkDevice, &c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = vkMemoryRequirements.size,
        .memoryTypeIndex = try findMemoryType(
            vkPhysicalDevice,
            vkMemoryRequirements.memoryTypeBits,
            vkMemoryPropertyFlags,
        ),
    }, null, vkBufferMemory));

    try handleError(c.vkBindBufferMemory(vkDevice, vkBuffer.*, vkBufferMemory.*, 0));

    defer std.log.info("Trying to init buffer OK", .{});
}

fn deinitBuffer(
    vkDevice: c.VkDevice,
    vkBuffer: c.VkBuffer,
    vkBufferMemory: c.VkDeviceMemory,
) void {
    c.vkDestroyBuffer(vkDevice, vkBuffer, null);
    c.vkFreeMemory(vkDevice, vkBufferMemory, null);

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
    vkDevice: c.VkDevice,
    vkPhysicalDevice: c.VkPhysicalDevice,
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
            vkDevice,
            vkPhysicalDevice,
            buffer_size,
            c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &vertex_buffer_set.vkBuffers[i],
            &vertex_buffer_set.vkBuffersMemory[i],
        );

        try handleError(c.vkMapMemory(
            vkDevice,
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
    vkDevice: c.VkDevice,
    vertex_buffer_set: VertexBufferSet,
) void {
    for (0..vertex_buffer_set.vkBuffers.len) |i| {
        deinitBuffer(vkDevice, vertex_buffer_set.vkBuffers[i], vertex_buffer_set.vkBuffersMemory[i]);
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
    vkDevice: c.VkDevice,
    vkPhysicalDevice: c.VkPhysicalDevice,
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
            vkDevice,
            vkPhysicalDevice,
            @sizeOf(Uniform),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &uniform_buffer_set.vkUniformBuffers[i],
            &uniform_buffer_set.vkUniformBuffersMemory[i],
        );

        try handleError(c.vkMapMemory(
            vkDevice,
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
    vkDevice: c.VkDevice,
    uniform_buffer_set: UniformBufferSet,
) void {
    for (0..uniform_buffer_set.vkUniformBuffers.len) |i| {
        deinitBuffer(vkDevice, uniform_buffer_set.vkUniformBuffers[i], uniform_buffer_set.vkUniformBuffersMemory[i]);
    }
    allocator.free(uniform_buffer_set.vkUniformBuffers);
    allocator.free(uniform_buffer_set.vkUniformBuffersMemory);
    allocator.free(uniform_buffer_set.vkUniformBuffersMapped);

    defer std.log.info("Deinit vulkan uniform buffers OK", .{});
}

// =Semaphores=========================================================================================================
pub fn initVkSemaphore(vkDevice: c.VkDevice) !c.VkSemaphore {
    var vkSemaphore: c.VkSemaphore = undefined;

    std.log.info("Trying to init semaphore...", .{});
    errdefer std.log.info("Trying to init semaphore failed", .{});

    try handleError(c.vkCreateSemaphore(
        vkDevice,
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
    vkDevice: c.VkDevice,
    vkSemaphore: c.VkSemaphore,
) void {
    c.vkDestroySemaphore(
        vkDevice,
        vkSemaphore,
        null,
    );

    errdefer std.log.info("Deinit vulkan semaphore OK", .{});
}

pub fn initVkSemaphores(
    allocator: std.mem.Allocator,
    vkDevice: c.VkDevice,
    count: usize,
) ![]c.VkSemaphore {
    var vkSemaphores: []c.VkSemaphore = undefined;

    std.log.info("Trying to init {} semaphores...", .{count});
    errdefer std.log.info("Trying to init {} semaphores failed", .{count});

    vkSemaphores = try allocator.alloc(c.VkSemaphore, count);
    for (vkSemaphores) |*vkSemaphore| {
        vkSemaphore.* = try initVkSemaphore(vkDevice);
    }

    defer std.log.info("Trying to init {} semaphores OK", .{count});
    return vkSemaphores;
}

pub fn deinitVkSemaphores(allocator: std.mem.Allocator, vkDevice: c.VkDevice, vkSemaphores: []c.VkSemaphore) void {
    for (vkSemaphores) |vkSemaphore| {
        deinitVkSemaphore(vkDevice, vkSemaphore);
    }
    allocator.free(vkSemaphores);

    defer std.log.info("Deinit {} semaphores OK", .{vkSemaphores.len});
}

// =Fences=============================================================================================================

pub fn initVkFence(vkDevice: c.VkDevice) !c.VkFence {
    var vkFence: c.VkFence = undefined;

    std.log.info("Trying to init fence...", .{});
    errdefer std.log.info("Trying to init fence failed", .{});

    try handleError(c.vkCreateFence(
        vkDevice,
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

pub fn deinitVkFence(vkDevice: c.VkDevice, vkFence: c.VkFence) void {
    c.vkDestroyFence(
        vkDevice,
        vkFence,
        null,
    );
    defer std.log.info("Deinit vulkan fence OK", .{});
}

pub fn initVkFences(allocator: std.mem.Allocator, vkDevice: c.VkDevice, count: usize) ![]c.VkFence {
    var vkFences: []c.VkFence = undefined;

    std.log.info("Trying to init {} fences...", .{count});
    errdefer std.log.info("Trying to init {} fences failed", .{count});

    vkFences = try allocator.alloc(c.VkFence, count);
    for (vkFences) |*vkFence| {
        vkFence.* = try initVkFence(vkDevice);
    }

    defer std.log.info("Trying to init {} fences OK", .{count});
    return vkFences;
}

pub fn deinitVkFences(allocator: std.mem.Allocator, vkDevice: c.VkDevice, vkFences: []c.VkFence) void {
    for (vkFences) |vkFence| {
        deinitVkFence(vkDevice, vkFence);
    }
    allocator.free(vkFences);

    defer std.log.info("Deinit {} fences OK", .{vkFences.len});
}

// =DescriptorPool=====================================================================================================

pub fn initVkDescriptorPool(
    vkDevice: c.VkDevice,
    vkUniformBuffers: []c.VkBuffer,
) !c.VkDescriptorPool {
    var vkDescriptorPool: c.VkDescriptorPool = undefined;

    std.log.info("Trying to init descriptor pool with capacity {}...", .{vkUniformBuffers.len});
    errdefer std.log.info("Trying to init descriptor pool with capacity {} failed", .{vkUniformBuffers.len});

    try handleError(c.vkCreateDescriptorPool(
        vkDevice,
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
    vkDevice: c.VkDevice,
    vkDescriptorPool: c.VkDescriptorPool,
) void {
    c.vkDestroyDescriptorPool(vkDevice, vkDescriptorPool, null);

    defer std.log.info("Deinit descriptor pool OK", .{});
}

// =DescriptorSets=====================================================================================================

pub fn initVkDescriptorSets(
    allocator: std.mem.Allocator,
    vkDevice: c.VkDevice,
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
    try handleError(c.vkAllocateDescriptorSets(vkDevice, &c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = vkDescriptorPool,
        .descriptorSetCount = @intCast(vkUniformBuffers.len),
        .pSetLayouts = @ptrCast(layouts),
    }, @ptrCast(vkDescriptorSets)));

    for (0..@intCast(vkUniformBuffers.len)) |i| {
        c.vkUpdateDescriptorSets(
            vkDevice,
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
