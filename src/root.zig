const std = @import("std");
const Io = std.Io;
const c = @import("c.zig").c;
const handleError = @import("error.zig").handleError;
const util = @import("util.zig");

pub const App = struct {
    window: *c.struct_SDL_Window,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    graphics_queue_index: u32,
    present_queue_index: u32,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    swap_extent: c.VkExtent2D,
    device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,

    const version = "0.1.0";
    const name = "pijpkijk";
    const identifier = "com.nielsdekoeijer.pijpkijk";
    const default_width = 800;
    const default_height = 600;

    pub fn init(allocator: std.mem.Allocator) !App {
        var self: @This() = undefined;
        self.allocator = allocator;

        // =InitializeSDL3=============================================================================================
        try util.sdlInit(.{});
        errdefer util.sdlQuit();

        // =AqcuireWindow==============================================================================================
        self.window = try util.sdlInitWindow(&.{ .cname = name, .w = default_width, .h = default_height });
        errdefer util.sdlDestroyWindow(self.window);

        // =AqcuireVkInstance==========================================================================================
        self.instance = try util.initVkInstance(allocator);
        errdefer util.deinitVkInstance(self.instance);

        // =AqcuireVkSurface===========================================================================================
        self.surface = try util.initVkSurface(self.window, self.instance);
        errdefer util.deinitVkSurface(self.instance, self.surface);

        // =AqcuireVkPhysicalDevice====================================================================================
        self.physical_device = try util.initVkPhysicalDevice(allocator, self.instance, self.surface);
        self.graphics_queue_index = try util.findGraphicsQueueIndex(allocator, self.physical_device);
        self.present_queue_index = try util.findPresentQueueIndex(allocator, self.surface, self.physical_device);
        self.surface_capabilities = try util.getPhysicalDeviceSurfaceCapabilities(self.physical_device, self.surface);
        self.swap_extent = try util.getVkExtent(self.window, self.surface_capabilities);

        // =AqcuireVkDevice============================================================================================
        self.device = try util.initVkDevice(
            allocator,
            self.graphics_queue_index,
            self.present_queue_index,
            self.physical_device,
        );
        errdefer util.deinitVkDevice(self.device);

        // =CreateVkSwapchain==========================================================================================
        // selectedSurfaceFormat: c.VkSurfaceFormatKHR,
        // selectedSwapExtent: c.VkExtent2D,
        // selectedPresentMode: c.VkPresentModeKHR,

        // self.swapchain = try util.initVkSwapchain(
        //     self.device,
        //     self.surface,
        //     self.surface_format,
        //     self.swap_extent,
        //     self.present_mode,
        //     self.surface_capabilities,
        //     self.graphics_queue_index,
        //     self.present_queue_index,
        // );
        errdefer util.deinitVkSwapchain(self.swapchain);

        return self;
    }

    pub fn run(self: *App) !void {
        _ = self;

        std.log.info("Running loop...", .{});
        errdefer std.log.info("Running loop exited with failure", .{});

        var running = true;
        var e: c.SDL_Event = undefined;

        while (running) {
            while (c.SDL_PollEvent(&e) != false) {
                switch (e.type) {
                    c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => running = false,

                    else => {},

                    c.SDL_EVENT_KEY_DOWN => {
                        switch (e.key.key) {
                            c.SDLK_ESCAPE => {
                                running = false;
                            },
                            else => {},
                        }
                    },
                }
            }

            running = false;
        }

        defer std.log.info("Running loop OK", .{});
    }

    pub fn deinit(self: *App) void {
        defer util.sdlQuit();
        defer util.sdlDestroyWindow(self.window);
        defer util.deinitVkInstance(self.instance);
        defer util.deinitVkSurface(self.instance, self.surface);
        defer util.deinitVkDevice(self.device);
    }
};
