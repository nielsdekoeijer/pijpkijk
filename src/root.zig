const std = @import("std");
const Io = std.Io;
const c = @import("c.zig").c;
const handleError = @import("error.zig").handleError;
const util = @import("util.zig");

pub const FRAMES_IN_FLIGHT = 2;

pub const App = struct {
    window: *c.struct_SDL_Window,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    graphics_queue_index: u32,
    present_queue_index: u32,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    swap_extent: c.VkExtent2D,
    present_mode: c.VkPresentModeKHR,
    depth_format: c.VkFormat,
    device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    vert_shader: c.VkShaderModule,
    frag_shader: c.VkShaderModule,
    render_pass: c.VkRenderPass,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    pipeline_layout: c.VkPipelineLayout,
    graphics_pipeline: c.VkPipeline,
    framebuffers: []c.VkFramebuffer,
    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,
    uniform_buffer_set: util.UniformBufferSet,
    vertex_buffer_set: util.VertexBufferSet,

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
        self.surface_format = try util.getPreferredVkSurfaceFormat(allocator, self.physical_device, self.surface);
        self.present_mode = try util.getPreferredVkPresentMode(allocator, self.physical_device, self.surface);
        self.depth_format = try util.getPreferredVkDepthFormat(self.physical_device);

        // =AqcuireVkDevice============================================================================================
        self.device = try util.initVkDevice(
            allocator,
            self.graphics_queue_index,
            self.present_queue_index,
            self.physical_device,
        );
        errdefer util.deinitVkDevice(self.device);

        // =CreateVkSwapchain==========================================================================================
        self.swapchain = try util.initVkSwapchain(
            self.device,
            self.surface,
            self.surface_capabilities,
            self.surface_format,
            self.swap_extent,
            self.present_mode,
            self.graphics_queue_index,
            self.present_queue_index,
        );
        errdefer util.deinitVkSwapchain(self.device, self.swapchain);

        // =CreateVkImages=============================================================================================
        self.images = try util.initVkImages(allocator, self.device, self.swapchain);
        errdefer util.deinitVkImages(allocator, self.images);

        self.image_views = try util.initVkImageViews(allocator, self.device, self.images, self.surface_format);
        errdefer util.deinitVkImageViews(allocator, self.device, self.image_views);

        // =Shaders====================================================================================================
        self.vert_shader = try util.initVkShaderModule("./shaders/triangle.vert.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.vert_shader);

        self.frag_shader = try util.initVkShaderModule("./shaders/triangle.frag.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.frag_shader);

        // =RenderPass=================================================================================================
        self.render_pass = try util.initVkRenderPass(self.device, self.surface_format);
        errdefer util.deinitVkRenderPass(self.device, self.render_pass);

        // =PipelineLayout=============================================================================================
        self.descriptor_set_layout = try util.initVkDescriptorSetLayout(self.device);
        errdefer util.deinitVkDescriptorSetLayout(self.device, self.descriptor_set_layout);

        self.pipeline_layout = try util.initVkPipelineLayout(self.device, self.descriptor_set_layout);
        errdefer util.deinitVkPipelineLayout(self.device, self.pipeline_layout);

        // =GraphicsPipeline===========================================================================================
        self.graphics_pipeline = try util.initVkGraphicsPipeline(
            self.device,
            self.swap_extent,
            self.render_pass,
            self.pipeline_layout,
            self.vert_shader,
            self.frag_shader,
        );
        errdefer util.deinitVkPipeline(self.device, self.graphics_pipeline);

        // =FrameBuffers===============================================================================================
        self.framebuffers = try util.initFramebuffers(
            allocator,
            self.device,
            self.image_views,
            self.render_pass,
            self.swap_extent,
        );
        errdefer util.deinitFramebuffers(allocator, self.device, self.framebuffers);

        // =CommandBuffers=============================================================================================
        self.command_pool = try util.initCommandPool(self.device, self.graphics_queue_index);
        errdefer util.deinitCommandPool(self.device, self.command_pool);

        self.command_buffers = try util.initCommandBuffers(
            allocator,
            self.device,
            self.command_pool,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitCommandBuffers(allocator, self.command_buffers);

        // =UniformBuffers=============================================================================================
        self.uniform_buffer_set = try util.initUniformBufferSet(
            allocator,
            self.device,
            self.physical_device,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitUniformBufferSet(allocator, self.device, self.uniform_buffer_set);

        // =VertexBuffers==============================================================================================
        self.vertex_buffer_set = try util.initVertexBufferSet(
            allocator,
            self.device,
            self.physical_device,
            100,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitVertexBufferSet(allocator, self.device, self.vertex_buffer_set);

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
        defer util.deinitVkSwapchain(self.device, self.swapchain);
        defer util.deinitVkImages(self.allocator, self.images);
        defer util.deinitVkImageViews(self.allocator, self.device, self.image_views);
        defer util.deinitVkShaderModule(self.device, self.vert_shader);
        defer util.deinitVkShaderModule(self.device, self.frag_shader);
        defer util.deinitVkRenderPass(self.device, self.render_pass);
        defer util.deinitVkDescriptorSetLayout(self.device, self.descriptor_set_layout);
        defer util.deinitVkPipelineLayout(self.device, self.pipeline_layout);
        defer util.deinitVkPipeline(self.device, self.graphics_pipeline);
        defer util.deinitFramebuffers(self.allocator, self.device, self.framebuffers);
        defer util.deinitCommandPool(self.device, self.command_pool);
        defer util.deinitCommandBuffers(self.allocator, self.command_buffers);
        defer util.deinitUniformBufferSet(self.allocator, self.device, self.uniform_buffer_set);
        defer util.deinitVertexBufferSet(self.allocator, self.device, self.vertex_buffer_set);
    }
};
