const std = @import("std");
const Io = std.Io;
const c = @import("c.zig").c;
const handleError = @import("error.zig").handleError;
const util = @import("util.zig");
const wayland = @import("wayland.zig");
const pipewire = @import("pipewire.zig");
const types = @import("types.zig");

pub const FRAMES_IN_FLIGHT = 3;

pub const UserData = enum(u64) {
    ANAS,
    WAYLAND,
    PIPEWIRE_START_RETRY,
    PIPEWIRE_EVENT,
};

pub const App = struct {
    wayland_handle: *wayland.WaylandHandle,
    pipewire_handle: *pipewire.PipewireHandle,
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
    device: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    depth_format: c.VkFormat,
    depth_images: []util.Image,
    depth_image_views: []c.VkImageView,
    quad_vert_shader: c.VkShaderModule,
    quad_frag_shader: c.VkShaderModule,
    bezier_vert_shader: c.VkShaderModule,
    bezier_frag_shader: c.VkShaderModule,
    text_vert_shader: c.VkShaderModule,
    text_frag_shader: c.VkShaderModule,
    render_pass: c.VkRenderPass,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    pipeline_layout: c.VkPipelineLayout,
    quad_vertex_graphics_pipeline: c.VkPipeline,
    bezier_vertex_graphics_pipeline: c.VkPipeline,
    text_vertex_graphics_pipeline: c.VkPipeline,
    framebuffers: []c.VkFramebuffer,
    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,
    uniform_buffer_set: util.UniformBufferSet,
    quad_vertex_buffer_set: util.VertexBufferSet,
    bezier_vertex_buffer_set: util.VertexBufferSet,
    text_vertex_buffer_set: util.VertexBufferSet,
    image_availible_semaphore: []c.VkSemaphore,
    render_finished_semaphore: []c.VkSemaphore,
    in_flight_fences: []c.VkFence,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_sets: []c.VkDescriptorSet,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    font_atlas: types.FontAtlas,
    font_texture_image: util.Image,
    font_texture_view: []c.VkImageView,
    font_sampler: c.VkSampler,
    ring: std.os.linux.IoUring,

    // TEMP
    camera_pos: [2]f32,
    scale: f32,
    selected_node: ?usize,

    const version = "0.1.0";
    const name = "pijpkijk";
    const identifier = "com.nielsdekoeijer.pijpkijk";
    const default_width = 800;
    const default_height = 600;

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !App {
        _ = io;

        var self: @This() = undefined;
        self.allocator = allocator;

        self.ring = try std.os.linux.IoUring.init(32, 0);
        errdefer self.ring.deinit();

        // =InitializeWayland==========================================================================================
        self.wayland_handle = try allocator.create(wayland.WaylandHandle);
        try wayland.WaylandHandle.init(self.wayland_handle);

        try self.wayland_handle.start_core();
        while (!self.wayland_handle.core_ready()) {
            try self.wayland_handle.flush_blocking();
        }

        while (!self.wayland_handle.seat_ready()) {
            try self.wayland_handle.flush_blocking();
        }

        try self.wayland_handle.start_surface();
        while (!self.wayland_handle.surface_ready()) {
            try self.wayland_handle.flush_blocking();
        }

        // =InitializePipewire=========================================================================================
        self.pipewire_handle = try pipewire.PipewireHandle.init(self.allocator);

        // =AqcuireVkInstance==========================================================================================
        self.instance = try util.initVkInstance(allocator);
        errdefer util.deinitVkInstance(self.instance);

        // =AqcuireVkSurface===========================================================================================
        self.surface = try util.initVkSurfaceWayland(
            self.instance,
            self.wayland_handle.core.display,
            self.wayland_handle.registry_surface.surface.?,
        );
        errdefer util.deinitVkSurface(self.instance, self.surface);

        // =AqcuireVkPhysicalDevice====================================================================================
        self.physical_device = try util.initVkPhysicalDevice(allocator, self.instance, self.surface);
        self.graphics_queue_index = try util.findGraphicsQueueIndex(allocator, self.physical_device);
        self.present_queue_index = try util.findPresentQueueIndex(allocator, self.surface, self.physical_device);
        self.surface_capabilities = try util.getPhysicalDeviceSurfaceCapabilities(self.physical_device, self.surface);
        self.swap_extent = util.getVkExtentFromWayland(self.wayland_handle, self.surface_capabilities);
        self.surface_format = try util.getPreferredVkSurfaceFormat(allocator, self.physical_device, self.surface);
        self.present_mode = try util.getPreferredVkPresentMode(allocator, self.physical_device, self.surface);

        // =AqcuireVkDevice============================================================================================
        self.device = try util.initVkDevice(
            allocator,
            self.graphics_queue_index,
            self.present_queue_index,
            self.physical_device,
        );
        errdefer util.deinitVkDevice(self.device);

        c.vkGetDeviceQueue(self.device, self.graphics_queue_index, 0, &self.graphics_queue);
        c.vkGetDeviceQueue(self.device, self.present_queue_index, 0, &self.present_queue);

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
            @ptrCast(c.VK_NULL_HANDLE),
        );
        errdefer util.deinitVkSwapchain(self.device, self.swapchain);

        // =CreateVkImages=============================================================================================
        self.images = try util.initVkImages(allocator, self.device, self.swapchain);
        errdefer util.deinitVkImages(allocator, self.images);

        self.image_views = try util.initVkImageViews(allocator, self.device, self.images, self.surface_format);
        errdefer util.deinitVkImageViews(allocator, self.device, self.image_views);

        self.depth_format = try util.findDepthFormat(self.physical_device);
        self.depth_images = try allocator.alloc(util.Image, self.images.len);
        self.depth_image_views = try allocator.alloc(c.VkImageView, self.images.len);

        for (0..self.images.len) |i| {
            self.depth_images[i] = try util.initImage(
                self.device,
                self.physical_device,
                self.swap_extent.height,
                self.swap_extent.width,
                self.depth_format,
                c.VK_IMAGE_TILING_OPTIMAL,
                c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            );
            self.depth_image_views[i] = try util.initDepthImageView(self.device, self.depth_images[i].image, self.depth_format);
        }

        // =Shaders====================================================================================================
        self.quad_vert_shader = try util.initVkShaderModule("./shaders/quad.vert.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.quad_vert_shader);

        self.quad_frag_shader = try util.initVkShaderModule("./shaders/quad.frag.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.quad_frag_shader);

        self.bezier_vert_shader = try util.initVkShaderModule("./shaders/bezier.vert.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.bezier_vert_shader);

        self.bezier_frag_shader = try util.initVkShaderModule("./shaders/bezier.frag.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.bezier_frag_shader);

        self.text_vert_shader = try util.initVkShaderModule("./shaders/text.vert.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.text_vert_shader);

        self.text_frag_shader = try util.initVkShaderModule("./shaders/text.frag.spirv", self.device);
        errdefer util.deinitVkShaderModule(self.device, self.text_frag_shader);

        // =RenderPass=================================================================================================
        self.render_pass = try util.initVkRenderPass(self.device, self.surface_format, self.depth_format);
        errdefer util.deinitVkRenderPass(self.device, self.render_pass);

        // =Pipeline===================================================================================================
        self.descriptor_set_layout = try util.initVkDescriptorSetLayout(self.device);
        errdefer util.deinitVkDescriptorSetLayout(self.device, self.descriptor_set_layout);

        self.pipeline_layout = try util.initVkPipelineLayout(self.device, self.descriptor_set_layout);
        errdefer util.deinitVkPipelineLayout(self.device, self.pipeline_layout);

        self.quad_vertex_graphics_pipeline = try util.initQuadVertexVkGraphicsPipeline(
            self.device,
            self.render_pass,
            self.pipeline_layout,
            self.quad_vert_shader,
            self.quad_frag_shader,
        );
        errdefer util.deinitVkPipeline(self.device, self.quad_vertex_graphics_pipeline);

        self.bezier_vertex_graphics_pipeline = try util.initBezierVertexVkGraphicsPipeline(
            self.device,
            self.render_pass,
            self.pipeline_layout,
            self.bezier_vert_shader,
            self.bezier_frag_shader,
        );
        errdefer util.deinitVkPipeline(self.device, self.bezier_vertex_graphics_pipeline);

        self.text_vertex_graphics_pipeline = try util.initTextVertexVkGraphicsPipeline(
            self.device,
            self.render_pass,
            self.pipeline_layout,
            self.text_vert_shader,
            self.text_frag_shader,
        );
        errdefer util.deinitVkPipeline(self.device, self.text_vertex_graphics_pipeline);

        // =FrameBuffers===============================================================================================
        self.framebuffers = try util.initFramebuffers(
            allocator,
            self.device,
            self.image_views,
            self.depth_image_views,
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

        // =Buffers====================================================================================================
        // To enable mutli-buffering, we create SETS of the objects we need, parameterized by FRAMES_IN_FLIGHT

        self.uniform_buffer_set = try util.initUniformBufferSet(
            allocator,
            self.device,
            self.physical_device,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitUniformBufferSet(allocator, self.device, self.uniform_buffer_set);

        self.quad_vertex_buffer_set = try util.initVertexBufferSet(
            types.QuadVertex,
            allocator,
            self.device,
            self.physical_device,
            100000,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitVertexBufferSet(allocator, self.device, self.quad_vertex_buffer_set);

        self.bezier_vertex_buffer_set = try util.initVertexBufferSet(
            types.BezierVertex,
            allocator,
            self.device,
            self.physical_device,
            100000,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitVertexBufferSet(allocator, self.device, self.quad_vertex_buffer_set);

        self.text_vertex_buffer_set = try util.initVertexBufferSet(
            types.TextVertex,
            allocator,
            self.device,
            self.physical_device,
            100000,
            FRAMES_IN_FLIGHT,
        );
        errdefer util.deinitVertexBufferSet(allocator, self.device, self.quad_vertex_buffer_set);

        // =Semaphores=================================================================================================
        self.render_finished_semaphore = try util.initVkSemaphores(allocator, self.device, self.images.len);
        errdefer util.deinitVkSemaphores(allocator, self.device, self.render_finished_semaphore);

        self.image_availible_semaphore = try util.initVkSemaphores(allocator, self.device, FRAMES_IN_FLIGHT);
        errdefer util.deinitVkSemaphores(allocator, self.device, self.image_availible_semaphore);

        self.in_flight_fences = try util.initVkFences(allocator, self.device, FRAMES_IN_FLIGHT);
        errdefer util.deinitVkFences(allocator, self.device, self.in_flight_fences);

        // =Fonts======================================================================================================
        self.font_atlas = try types.FontAtlas.init(allocator, @embedFile("fonts/RobotoMono-Regular.json"));

        self.font_texture_image = try util.initTextureImage(
            self.device,
            self.physical_device,
            self.command_pool,
            self.graphics_queue,
            @embedFile("fonts/RobotoMono-Regular.png"),
        );
        errdefer util.deinitTextureImage(self.device, self.font_texture_image.image, self.font_texture_image.image_memory);

        self.font_texture_view = try util.initVkImageViews(
            self.allocator,
            self.device,
            @constCast(&[_]c.VkImage{self.font_texture_image.image}),
            c.VkSurfaceFormatKHR{
                .format = c.VK_FORMAT_R8G8B8A8_UNORM,
                .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            },
        );
        errdefer util.deinitVkImageViews(allocator, self.device, self.font_texture_view);

        self.font_sampler = try util.initTextureSampler(self.device, self.physical_device);
        errdefer util.deinitTextureSampler(self.device, self.font_sampler);

        // =Descriptors================================================================================================
        self.descriptor_pool = try util.initVkDescriptorPool(self.device, self.uniform_buffer_set.vkUniformBuffers);
        errdefer util.deinitVkDescriptorPool(self.device, self.descriptor_pool);

        self.descriptor_sets = try util.initVkDescriptorSets(
            allocator,
            self.device,
            self.descriptor_set_layout,
            self.descriptor_pool,
            self.uniform_buffer_set.vkUniformBuffers,
            self.font_texture_view[0],
            self.font_sampler,
        );
        errdefer util.deinitVkDescriptorSets(allocator, self.descriptor_sets);

        self.camera_pos = [_]f32{ -100, -100 };
        self.scale = 0.55;

        self.selected_node = null;

        return self;
    }

    pub fn run(self: *App) !void {
        std.log.info("Running loop...", .{});
        errdefer std.log.info("Running loop exited with failure", .{});

        var running = true;
        var current_frame: usize = 0;
        var window_resized = false;
        var needs_render = true;
        var needs_state_update = false;

        var gpu_frame_ready = [_]bool{ true, true, true };

        const wl_fd = c.wl_display_get_fd(self.wayland_handle.core.display);

        var pw_fd: ?i32 = null;
        if (self.pipewire_handle.start_core()) |_| {
            pw_fd = self.pipewire_handle.fd();

            _ = try self.ring.poll_add(
                @intFromEnum(UserData.PIPEWIRE_EVENT),
                pw_fd.?,
                std.posix.POLL.IN,
            );
        } else |_| {
            var sqe = try self.ring.get_sqe();

            sqe.prep_timeout(&.{
                .sec = 0,
                .nsec = 1000 * 1_000_000,
            }, 0, 0);

            sqe.user_data = @intFromEnum(UserData.PIPEWIRE_START_RETRY);
        }

        _ = try self.ring.poll_add(
            @intFromEnum(UserData.WAYLAND),
            wl_fd,
            std.posix.POLL.IN,
        );

        _ = try self.ring.submit();

        // Our main loop of the program
        while (running) {
            // Process leftover events from our last loop
            _ = c.wl_display_dispatch_pending(self.wayland_handle.core.display);

            var cqes: [16]std.os.linux.io_uring_cqe = undefined;

            const wait_nr: u32 = if (needs_render) 0 else 1;
            const cqe_count = try self.ring.copy_cqes(&cqes, wait_nr);

            for (cqes[0..cqe_count]) |cqe| {
                const user_data: UserData = @enumFromInt(cqe.user_data);
                // std.log.debug("Received io_uring event: '{s}'", .{@tagName(user_data)});

                switch (user_data) {
                    UserData.ANAS => unreachable,
                    UserData.PIPEWIRE_EVENT => {
                        // If no error...
                        if (cqe.res >= 0) {
                            const revents = @as(u32, @bitCast(cqe.res));

                            // Check if poll input...
                            if ((revents & std.posix.POLL.IN) != 0) {
                                try self.pipewire_handle.drain();
                                try self.pipewire_handle.update_graph_metadata();
                                needs_state_update = true;
                            }
                        }

                        // Reschedule
                        _ = try self.ring.poll_add(@intFromEnum(UserData.PIPEWIRE_EVENT), pw_fd.?, std.posix.POLL.IN);
                    },

                    UserData.PIPEWIRE_START_RETRY => {
                        if (self.pipewire_handle.start_core()) |_| {
                            pw_fd = self.pipewire_handle.fd();

                            _ = try self.ring.poll_add(
                                @intFromEnum(UserData.PIPEWIRE_EVENT),
                                pw_fd.?,
                                std.posix.POLL.IN,
                            );
                        } else |_| {
                            var sqe = try self.ring.get_sqe();

                            sqe.prep_timeout(&.{
                                .sec = 0,
                                .nsec = 1000 * 1_000_000,
                            }, 1, 0);

                            sqe.user_data = @intFromEnum(UserData.PIPEWIRE_START_RETRY);
                        }
                    },

                    UserData.WAYLAND => {
                        // If no error...
                        if (cqe.res >= 0) {
                            const revents = @as(u32, @bitCast(cqe.res));

                            if ((revents & std.posix.POLL.IN) != 0) {
                                try handleError(
                                    c.wl_display_dispatch(self.wayland_handle.core.display),
                                );

                                needs_render = true;
                                needs_state_update = true;
                            }
                        }

                        // Reschedule
                        _ = try self.ring.poll_add(@intFromEnum(UserData.WAYLAND), wl_fd, std.posix.POLL.IN);
                    },
                }
            }

            {
                _ = try self.ring.submit();
                try handleError(
                    c.wl_display_flush(self.wayland_handle.core.display),
                );
            }

            // Check if we should shut down
            if (self.wayland_handle.state.should_close) {
                running = false;
            }

            // Update program state based on e.g. inputs
            if (needs_state_update) {
                needs_state_update = false;

                if (self.wayland_handle.state.input.scroll_y != 0) {
                    const mouse_x = self.wayland_handle.state.input.mouse_x orelse 0.0;
                    const mouse_y = self.wayland_handle.state.input.mouse_y orelse 0.0;

                    const zoom_factor = 1.0 - (self.wayland_handle.state.input.scroll_y * 0.02);

                    // Track where the mouse is in the world BEFORE scaling
                    const world_x_before = (mouse_x / self.scale) + self.camera_pos[0];
                    const world_y_before = (mouse_y / self.scale) + self.camera_pos[1];

                    self.scale *= zoom_factor;
                    self.scale = std.math.clamp(self.scale, 0.05, 5.0);

                    // Track where the mouse is in the world AFTER scaling
                    const world_x_after = (mouse_x / self.scale) + self.camera_pos[0];
                    const world_y_after = (mouse_y / self.scale) + self.camera_pos[1];

                    // Pan the camera so the mouse stays over the exact same world coordinate
                    self.camera_pos[0] += (world_x_before - world_x_after);
                    self.camera_pos[1] += (world_y_before - world_y_after);

                    self.wayland_handle.state.input.scroll_y = 0;
                    needs_render = true;
                }

                if (self.wayland_handle.state.input.mouse_down_r) {
                    self.camera_pos[0] -= self.wayland_handle.state.input.mouse_dx / self.scale;
                    self.camera_pos[1] -= self.wayland_handle.state.input.mouse_dy / self.scale;
                    needs_render = true;
                }

                if (self.wayland_handle.state.input.mouse_down_l) {
                    const mouse_x = self.wayland_handle.state.input.mouse_x orelse 0.0;
                    const mouse_y = self.wayland_handle.state.input.mouse_y orelse 0.0;
                    const world_x = (mouse_x / self.scale) + self.camera_pos[0];
                    const world_y = (mouse_y / self.scale) + self.camera_pos[1];

                    if (self.selected_node) |node_id| {
                        if (self.pipewire_handle.nodes.getPtr(@intCast(node_id))) |node| {
                            node.x.? += self.wayland_handle.state.input.mouse_dx / self.scale;
                            node.y.? += self.wayland_handle.state.input.mouse_dy / self.scale;
                            needs_render = true;
                        }
                    } else {
                        var it = self.pipewire_handle.nodes.iterator();
                        while (it.next()) |entry| {
                            try entry.value_ptr.markNearbyLinks(
                                self.pipewire_handle.nodes,
                                [_]f32{ world_x, world_y },
                            );

                            const n = entry.value_ptr;
                            if (n.x) |nx| {
                                if (n.y) |ny| {
                                    const w = types.PipewireNode.W_NODE;
                                    const h = n.computeNodeHeight();
                                    if (world_x >= nx and world_x <= nx + w and
                                        world_y >= ny and world_y <= ny + h)
                                    {
                                        self.selected_node = entry.key_ptr.*;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Let go of the node on release
                    self.selected_node = null;
                }

                if (self.wayland_handle.state.input.key_q) |key_q| {
                    if (key_q == .PRESSED) {
                        running = false;
                    }
                }

                if (self.wayland_handle.state.input.key_r) |key_r| {
                    if (key_r == .PRESSED) {
                        try self.pipewire_handle.update_graph_metadata();
                    }
                }

                if (self.wayland_handle.state.input.key_delete) |key_delete| {
                    if (key_delete == .PRESSED) {
                        var node_it = self.pipewire_handle.nodes.iterator();
                        while (node_it.next()) |*node| {
                            var port_it = node.value_ptr.outs.iterator();
                            while (port_it.next()) |*port| {
                                var i: usize = port.value_ptr.connections.count();
                                while (i > 0) {
                                    i -= 1;
                                    const link = port.value_ptr.connections.values()[i];

                                    if (link.is_selected) {
                                        try handleError(c.pw_registry_destroy(self.pipewire_handle.registry, link.link_id));
                                    }
                                }
                            }
                        }
                    }
                }

                if (self.wayland_handle.state.input.key_escape) |key_escape| {
                    if (key_escape == .PRESSED) {
                        var node_it = self.pipewire_handle.nodes.iterator();
                        while (node_it.next()) |*node| {
                            var port_it = node.value_ptr.outs.iterator();
                            while (port_it.next()) |*port| {
                                var link_it = port.value_ptr.connections.iterator();
                                while (link_it.next()) |*link| {
                                    link.value_ptr.is_selected = false;
                                }
                            }
                        }
                    }
                }

                // Reset frame deltas so they don't repeatedly apply
                self.wayland_handle.state.input.mouse_dx = 0;
                self.wayland_handle.state.input.mouse_dy = 0;
            }

            // Do a render if required
            if (needs_render and self.wayland_handle.state.frame_ready) {
                needs_render = false;

                if (self.swap_extent.width != self.wayland_handle.state.width or
                    self.swap_extent.height != self.wayland_handle.state.height)
                {
                    window_resized = true;
                }

                // If window resized, we must recreate the swapchain
                if (window_resized) {
                    window_resized = false;
                    try self.recreateSwapchain();
                }

                // Stops CPU from overwriting buffers currently in flight, this garuntee that the GPU has finished working
                // on `current_frame` before we start overwriting stuff.
                try handleError(
                    c.vkWaitForFences(
                        self.device,
                        1,
                        &self.in_flight_fences[current_frame],
                        c.VK_TRUE,
                        std.math.maxInt(u64),
                    ),
                );

                // Retrieve the image of the next swapchain image
                var image_index: u32 = undefined;
                {
                    const acquire_result = c.vkAcquireNextImageKHR(
                        self.device,
                        self.swapchain,
                        std.math.maxInt(u64),
                        // Is when the image is safe to draw to, can be either a semaphore or a fence. Note we return
                        // BEFORE the semaphore is signaled! So it must be checked.
                        self.image_availible_semaphore[current_frame],

                        // This would be the fence, but we are using a semaphore
                        null,
                        &image_index,
                    );

                    if (acquire_result == c.VK_ERROR_OUT_OF_DATE_KHR) {
                        try self.recreateSwapchain();
                        continue;
                    } else if (acquire_result != c.VK_SUCCESS and acquire_result != c.VK_SUBOPTIMAL_KHR) {
                        return error.VulkanAcquireFailed;
                    }
                }

                // Only reset the fence once we know we are definitely submitting work
                try handleError(
                    c.vkResetFences(
                        self.device,
                        1,
                        &self.in_flight_fences[current_frame],
                    ),
                );
                gpu_frame_ready[current_frame] = false;

                // Update uniforms buffers
                {
                    // TODO: this is ugly as sin, and its because our use of anyopque
                    const uniform_map: [*]types.Uniform = @ptrCast(
                        @alignCast(self.uniform_buffer_set.vkUniformBuffersMapped[current_frame]),
                    );
                    uniform_map[0] = .{
                        .screen_size = .{
                            @floatFromInt(self.swap_extent.width),
                            @floatFromInt(self.swap_extent.height),
                        },
                        .camera_pos = self.camera_pos,
                        .scale = self.scale,
                    };
                }

                // Update QuadVertex buffers for our nodes
                var quad_vertices = try std.ArrayList(types.QuadVertex).initCapacity(self.allocator, 0);
                defer quad_vertices.deinit(self.allocator);
                {
                    {
                        var node_it = self.pipewire_handle.nodes.iterator();
                        while (node_it.next()) |node| {
                            try node.value_ptr.appendVerticesNode(self.allocator, &quad_vertices);
                        }
                    }
                    {
                        var node_it = self.pipewire_handle.nodes.iterator();
                        while (node_it.next()) |node| {
                            try node.value_ptr.appendVerticesPorts(self.allocator, &quad_vertices);
                        }
                    }

                    // TODO: this is ugly as sin, and its because our use of anyopque
                    if (quad_vertices.items.len > 0) {
                        const quad_vert_map: [*]types.QuadVertex = @ptrCast(@alignCast(
                            self.quad_vertex_buffer_set.vkBuffersMapped[current_frame],
                        ));
                        @memcpy(quad_vert_map[0..quad_vertices.items.len], quad_vertices.items);
                    }
                }

                // Update BexierVertex buffers for our connections
                var bezier_vertices = try std.ArrayList(types.BezierVertex).initCapacity(self.allocator, 0);
                defer bezier_vertices.deinit(self.allocator);
                {
                    var node_it = self.pipewire_handle.nodes.iterator();
                    while (node_it.next()) |node| {
                        try node.value_ptr.appendVerticesLinks(
                            self.allocator,
                            self.pipewire_handle.nodes,
                            &bezier_vertices,
                        );
                    }

                    std.mem.sort(types.BezierVertex, bezier_vertices.items, {}, struct {
                        pub fn lessThanFn(_: void, lhs: types.BezierVertex, rhs: types.BezierVertex) bool {
                            return lhs.pos[2] > rhs.pos[2];
                        }
                    }.lessThanFn);

                    if (bezier_vertices.items.len > 0) {
                        // TODO: this is ugly as sin, and its because our use of anyopque
                        const bezier_vert_map: [*]types.BezierVertex = @ptrCast(@alignCast(
                            self.bezier_vertex_buffer_set.vkBuffersMapped[current_frame],
                        ));
                        @memcpy(bezier_vert_map[0..bezier_vertices.items.len], bezier_vertices.items);
                    }
                }

                // Update TextVertex buffers for our text
                var text_vertices = try std.ArrayList(types.TextVertex).initCapacity(self.allocator, 0);
                defer text_vertices.deinit(self.allocator);
                {
                    var node_it = self.pipewire_handle.nodes.iterator();
                    while (node_it.next()) |node| {
                        try node.value_ptr.appendVerticesText(self.allocator, self.font_atlas, &text_vertices);
                    }

                    const text_vert_map: [*]types.TextVertex = @ptrCast(@alignCast(
                        self.text_vertex_buffer_set.vkBuffersMapped[current_frame],
                    ));
                    @memcpy(text_vert_map[0..text_vertices.items.len], text_vertices.items);
                }

                // Reset command buffer for the current frame
                const cmd = self.command_buffers[current_frame];
                try util.resetCommandBuffer(cmd);
                try util.beginCommandBuffer(cmd);

                c.vkCmdBeginRenderPass(cmd, &c.VkRenderPassBeginInfo{
                    .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                    .pNext = null,
                    .renderPass = self.render_pass,
                    .framebuffer = self.framebuffers[image_index],
                    .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_extent },
                    .clearValueCount = 2,
                    .pClearValues = &[_]c.VkClearValue{
                        .{ .color = .{ .float32 = .{ 0.1, 0.1, 0.1, 1.0 } } },
                        .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
                    },
                }, c.VK_SUBPASS_CONTENTS_INLINE);

                c.vkCmdSetViewport(cmd, 0, 1, &c.VkViewport{
                    .x = 0.0,
                    .y = 0,
                    .width = @floatFromInt(self.swap_extent.width),
                    .height = @as(f32, @floatFromInt(self.swap_extent.height)),
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                });

                c.vkCmdSetScissor(cmd, 0, 1, &c.VkRect2D{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = self.swap_extent,
                });

                if (quad_vertices.items.len > 0) {
                    const offsets = [_]c.VkDeviceSize{0};
                    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.quad_vertex_graphics_pipeline);
                    c.vkCmdBindVertexBuffers(cmd, 0, 1, &self.quad_vertex_buffer_set.vkBuffers[current_frame], &offsets);
                    c.vkCmdBindDescriptorSets(
                        cmd,
                        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                        self.pipeline_layout,
                        0,
                        1,
                        &self.descriptor_sets[current_frame],
                        0,
                        null,
                    );

                    c.vkCmdDraw(cmd, @intCast(quad_vertices.items.len), 1, 0, 0);
                }

                if (bezier_vertices.items.len > 0) {
                    const offsets = [_]c.VkDeviceSize{0};
                    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.bezier_vertex_graphics_pipeline);
                    c.vkCmdBindVertexBuffers(cmd, 0, 1, &self.bezier_vertex_buffer_set.vkBuffers[current_frame], &offsets);
                    c.vkCmdBindDescriptorSets(
                        cmd,
                        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                        self.pipeline_layout,
                        0,
                        1,
                        &self.descriptor_sets[current_frame],
                        0,
                        null,
                    );

                    c.vkCmdDraw(cmd, @intCast(bezier_vertices.items.len), 1, 0, 0);
                }

                if (text_vertices.items.len > 0) {
                    const offsets = [_]c.VkDeviceSize{0};
                    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.text_vertex_graphics_pipeline);
                    c.vkCmdBindVertexBuffers(cmd, 0, 1, &self.text_vertex_buffer_set.vkBuffers[current_frame], &offsets);
                    c.vkCmdBindDescriptorSets(
                        cmd,
                        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                        self.pipeline_layout,
                        0,
                        1,
                        &self.descriptor_sets[current_frame],
                        0,
                        null,
                    );

                    c.vkCmdDraw(cmd, @intCast(text_vertices.items.len), 1, 0, 0);
                }

                c.vkCmdEndRenderPass(cmd);
                try handleError(c.vkEndCommandBuffer(cmd));

                const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
                const submit_info = c.VkSubmitInfo{
                    .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .pNext = null,
                    .waitSemaphoreCount = 1,
                    // Wait until the image is availible before trying to render
                    .pWaitSemaphores = @ptrCast(&self.image_availible_semaphore[current_frame]),
                    .pWaitDstStageMask = @ptrCast(&wait_stages),
                    .commandBufferCount = 1,
                    .pCommandBuffers = &cmd,
                    .signalSemaphoreCount = 1,
                    // Signal this when we are done rendering
                    .pSignalSemaphores = @ptrCast(&self.render_finished_semaphore[image_index]),
                };

                // Submit commands
                try handleError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[current_frame]));

                // Request new frame
                self.wayland_handle.request_frame_callback();

                // Present
                const present_info = c.VkPresentInfoKHR{
                    .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                    .pNext = null,
                    .waitSemaphoreCount = 1,
                    // Wait until the image is done rendering before presenting it
                    .pWaitSemaphores = @ptrCast(&self.render_finished_semaphore[image_index]),
                    .swapchainCount = 1,
                    .pSwapchains = @ptrCast(&self.swapchain),
                    .pImageIndices = &image_index,
                    .pResults = null,
                };

                const present_result = c.vkQueuePresentKHR(self.present_queue, &present_info);

                if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
                    window_resized = true;
                } else if (present_result != c.VK_SUCCESS) {
                    return error.VulkanPresentFailed;
                }

                current_frame = (current_frame + 1) % FRAMES_IN_FLIGHT;
            }
        }

        // Ensure the GPU has finished everything before tearing down
        _ = c.vkDeviceWaitIdle(self.device);

        defer std.log.info("Running loop OK", .{});
    }

    pub fn recreateSwapchain(self: *App) !void {
        std.log.info("Recreating swapchain...", .{});
        errdefer std.log.info("Recreating swapchain failed", .{});

        // Wait for idle before recreating the swapchian
        _ = c.vkDeviceWaitIdle(self.device);

        // Delete what we had
        util.deinitVkSemaphores(self.allocator, self.device, self.render_finished_semaphore);
        util.deinitFramebuffers(self.allocator, self.device, self.framebuffers);
        util.deinitVkImageViews(self.allocator, self.device, self.depth_image_views);
        for (self.depth_images) |img| {
            util.deinitTextureImage(self.device, img.image, img.image_memory);
        }
        self.allocator.free(self.depth_images);
        util.deinitVkImageViews(self.allocator, self.device, self.image_views);
        util.deinitVkImages(self.allocator, self.images);
        util.deinitVkSwapchain(self.device, self.swapchain);

        // Reinitialize
        self.surface_capabilities = try util.getPhysicalDeviceSurfaceCapabilities(self.physical_device, self.surface);
        self.swap_extent = util.getVkExtentFromWayland(self.wayland_handle, self.surface_capabilities);
        self.swapchain = try util.initVkSwapchain(
            self.device,
            self.surface,
            self.surface_capabilities,
            self.surface_format,
            self.swap_extent,
            self.present_mode,
            self.graphics_queue_index,
            self.present_queue_index,
            // self.swapchain,
            null,
        );
        self.images = try util.initVkImages(self.allocator, self.device, self.swapchain);
        self.image_views = try util.initVkImageViews(self.allocator, self.device, self.images, self.surface_format);

        self.depth_images = try self.allocator.alloc(util.Image, self.images.len);
        self.depth_image_views = try self.allocator.alloc(c.VkImageView, self.images.len);
        for (0..self.images.len) |i| {
            self.depth_images[i] = try util.initImage(
                self.device,
                self.physical_device,
                self.swap_extent.height,
                self.swap_extent.width,
                self.depth_format,
                c.VK_IMAGE_TILING_OPTIMAL,
                c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            );
            self.depth_image_views[i] = try util.initDepthImageView(self.device, self.depth_images[i].image, self.depth_format);
        }

        self.framebuffers = try util.initFramebuffers(
            self.allocator,
            self.device,
            self.image_views,
            self.depth_image_views,
            self.render_pass,
            self.swap_extent,
        );

        self.render_finished_semaphore = try util.initVkSemaphores(self.allocator, self.device, self.images.len);

        defer std.log.info("Recreating swapchain OK", .{});
    }

    pub fn deinit(self: *App) void {
        defer self.allocator.destroy(self.wayland_handle);
        defer self.wayland_handle.deinit();
        defer self.allocator.destroy(self.pipewire_handle);
        defer self.pipewire_handle.deinit();
        defer self.ring.deinit();
        defer util.deinitVkInstance(self.instance);
        defer util.deinitVkSurface(self.instance, self.surface);
        defer util.deinitVkDevice(self.device);
        defer util.deinitVkSwapchain(self.device, self.swapchain);
        defer util.deinitVkImages(self.allocator, self.images);
        defer util.deinitVkImageViews(self.allocator, self.device, self.image_views);
        defer util.deinitVkShaderModule(self.device, self.quad_vert_shader);
        defer util.deinitVkShaderModule(self.device, self.quad_frag_shader);
        defer util.deinitVkShaderModule(self.device, self.bezier_vert_shader);
        defer util.deinitVkShaderModule(self.device, self.bezier_frag_shader);
        defer util.deinitVkShaderModule(self.device, self.text_vert_shader);
        defer util.deinitVkShaderModule(self.device, self.text_frag_shader);
        defer util.deinitVkRenderPass(self.device, self.render_pass);
        defer util.deinitVkDescriptorSetLayout(self.device, self.descriptor_set_layout);
        defer util.deinitVkPipelineLayout(self.device, self.pipeline_layout);
        defer util.deinitVkPipeline(self.device, self.quad_vertex_graphics_pipeline);
        defer util.deinitVkPipeline(self.device, self.bezier_vertex_graphics_pipeline);
        defer util.deinitVkPipeline(self.device, self.text_vertex_graphics_pipeline);
        defer util.deinitFramebuffers(self.allocator, self.device, self.framebuffers);
        defer util.deinitCommandPool(self.device, self.command_pool);
        defer util.deinitCommandBuffers(self.allocator, self.command_buffers);
        defer util.deinitUniformBufferSet(self.allocator, self.device, self.uniform_buffer_set);
        defer util.deinitVertexBufferSet(self.allocator, self.device, self.quad_vertex_buffer_set);
        defer util.deinitVertexBufferSet(self.allocator, self.device, self.bezier_vertex_buffer_set);
        defer util.deinitVertexBufferSet(self.allocator, self.device, self.text_vertex_buffer_set);
        defer util.deinitVkSemaphores(self.allocator, self.device, self.render_finished_semaphore);
        defer util.deinitVkSemaphores(self.allocator, self.device, self.image_availible_semaphore);
        defer util.deinitVkFences(self.allocator, self.device, self.in_flight_fences);
        defer util.deinitVkDescriptorPool(self.device, self.descriptor_pool);
        defer util.deinitVkDescriptorSets(self.allocator, self.descriptor_sets);
        defer util.deinitTextureImage(self.device, self.font_texture_image.image, self.font_texture_image.image_memory);
        defer util.deinitVkImageViews(self.allocator, self.device, self.font_texture_view);
        defer util.deinitTextureSampler(self.device, self.font_sampler);
        defer {
            util.deinitVkImageViews(self.allocator, self.device, self.depth_image_views);
            for (self.depth_images) |img| {
                util.deinitTextureImage(self.device, img.image, img.image_memory);
            }
            self.allocator.free(self.depth_images);
        }
        defer self.font_atlas.deinit();
    }
};
