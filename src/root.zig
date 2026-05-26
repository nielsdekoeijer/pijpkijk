const std = @import("std");
const Io = std.Io;
const c = @import("c.zig").c;
const handleError = @import("error.zig").handleError;
const util = @import("util.zig");
const types = @import("types.zig");

pub const FRAMES_IN_FLIGHT = 2;

const rect_verts = [_]types.Vertex{
    // Triangle 1
    .{ .pos = .{ 100.0, 100.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .pos = .{ 100.0, 300.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .pos = .{ 300.0, 100.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    // Triangle 2
    .{ .pos = .{ 300.0, 100.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .pos = .{ 100.0, 300.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .pos = .{ 300.0, 300.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
};

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
    image_availible_semaphore: []c.VkSemaphore,
    render_finished_semaphore: []c.VkSemaphore,
    in_flight_fences: []c.VkFence,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_sets: []c.VkDescriptorSet,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,

    // TEMP
    cube_pos: [2]f32 = .{ 200.0, 200.0 },

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
        self.window = try util.sdlInitWindow(.{ .cname = name, .w = default_width, .h = default_height });
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
        self.swap_extent = try util.getVkExtentFromSDLWindow(self.window, self.surface_capabilities);
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

        // =Semaphores=================================================================================================
        self.render_finished_semaphore = try util.initVkSemaphores(allocator, self.device, FRAMES_IN_FLIGHT);
        errdefer util.deinitVkSemaphores(allocator, self.device, self.render_finished_semaphore);

        self.image_availible_semaphore = try util.initVkSemaphores(allocator, self.device, FRAMES_IN_FLIGHT);
        errdefer util.deinitVkSemaphores(allocator, self.device, self.image_availible_semaphore);

        self.in_flight_fences = try util.initVkFences(allocator, self.device, FRAMES_IN_FLIGHT);
        errdefer util.deinitVkFences(allocator, self.device, self.in_flight_fences);

        // =Descriptors================================================================================================
        self.descriptor_pool = try util.initVkDescriptorPool(self.device, self.uniform_buffer_set.vkUniformBuffers);
        errdefer util.deinitVkDescriptorPool(self.device, self.descriptor_pool);

        self.descriptor_sets = try util.initVkDescriptorSets(
            allocator,
            self.device,
            self.descriptor_set_layout,
            self.descriptor_pool,
            self.uniform_buffer_set.vkUniformBuffers,
        );
        errdefer util.deinitVkDescriptorSets(allocator, self.descrptor_sets);

        return self;
    }

    pub fn run(self: *App) !void {
        std.log.info("Running loop...", .{});
        errdefer std.log.info("Running loop exited with failure", .{});

        var key_down_x: ?f32 = null;
        var key_down_y: ?f32 = null;
        var running = true;
        var current_frame: usize = 0;
        var window_resized = false;
        var e: c.SDL_Event = undefined;

        while (running) {
            while (c.SDL_PollEvent(&e) != false) {
                switch (e.type) {
                    c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                        running = false;
                    },
                    c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                        window_resized = true;
                    },
                    c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                        std.log.debug("Mouse button down: ({}, {})", .{ e.button.x, e.button.y });
                        key_down_x = e.button.x;
                        key_down_y = e.button.y;
                    },
                    c.SDL_EVENT_MOUSE_BUTTON_UP => {
                        std.log.debug("Mouse button lift: ({}, {})", .{ e.button.x, e.button.y });
                        key_down_x = null;
                        key_down_y = null;
                    },
                    c.SDL_EVENT_MOUSE_MOTION => {
                        if (key_down_x) |x| {
                            self.cube_pos[0] += e.button.x - x;
                            key_down_x = e.button.x;
                        }

                        if (key_down_y) |y| {
                            self.cube_pos[1] += e.button.y - y;
                            key_down_y = e.button.y;
                        }
                    },
                    c.SDL_EVENT_KEY_DOWN => {
                        const move_speed = 10.0;
                        switch (e.key.key) {
                            c.SDLK_ESCAPE => running = false,
                            c.SDLK_Q => running = false,
                            c.SDLK_W => self.cube_pos[1] += move_speed,
                            c.SDLK_S => self.cube_pos[1] -= move_speed,
                            c.SDLK_A => self.cube_pos[0] -= move_speed,
                            c.SDLK_D => self.cube_pos[0] += move_speed,
                            else => {},
                        }
                    },
                    else => {},
                }
            }

            // 1. If an SDL event told us the window resized, recreate BEFORE acquiring.
            if (window_resized) {
                window_resized = false;
                try self.recreateSwapchain();
            }

            // 2. Wait for the GPU to finish the previous frame using this slot
            try handleError(c.vkWaitForFences(self.device, 1, &self.in_flight_fences[current_frame], c.VK_TRUE, std.math.maxInt(u64)));

            // 3. Acquire the next image from the swapchain
            var image_index: u32 = undefined;
            const acquire_result = c.vkAcquireNextImageKHR(
                self.device,
                self.swapchain,
                std.math.maxInt(u64),
                self.image_availible_semaphore[current_frame],
                null,
                &image_index,
            );

            // Handle acquire failures (on failure, the semaphore is left unsignaled, so continue is safe)
            if (acquire_result == c.VK_ERROR_OUT_OF_DATE_KHR) {
                try self.recreateSwapchain();
                continue;
            } else if (acquire_result != c.VK_SUCCESS and acquire_result != c.VK_SUBOPTIMAL_KHR) {
                return error.VulkanAcquireFailed;
            }

            // Only reset the fence once we know we are definitely submitting work
            try handleError(c.vkResetFences(self.device, 1, &self.in_flight_fences[current_frame]));

            // Update Memory Mapped Buffers (Vertex + Uniform)
            const vert_map: [*]types.Vertex = @ptrCast(@alignCast(self.vertex_buffer_set.vkBuffersMapped[current_frame]));
            @memcpy(vert_map[0..6], &rect_verts);

            // In step 3 (Update Memory Mapped Buffers)
            const uniform_map: [*]types.Uniform = @ptrCast(@alignCast(self.uniform_buffer_set.vkUniformBuffersMapped[current_frame]));
            uniform_map[0] = .{
                .screen_size = .{ @floatFromInt(self.swap_extent.width), @floatFromInt(self.swap_extent.height) },
                .cube_pos = self.cube_pos,
            };

            // Record Command Buffer
            const cmd = self.command_buffers[current_frame];
            try handleError(c.vkResetCommandBuffer(cmd, 0)); // Catch error here!

            const begin_info = c.VkCommandBufferBeginInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .pNext = null,
                .flags = 0,
                .pInheritanceInfo = null,
            };
            try handleError(c.vkBeginCommandBuffer(cmd, &begin_info)); // Catch error here!

            const clear_value = c.VkClearValue{ .color = .{ .float32 = .{ 0.1, 0.1, 0.1, 1.0 } } };
            const render_pass_info = c.VkRenderPassBeginInfo{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .pNext = null,
                .renderPass = self.render_pass,
                .framebuffer = self.framebuffers[image_index],
                .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_extent },
                .clearValueCount = 1,
                .pClearValues = &clear_value,
            };

            c.vkCmdBeginRenderPass(cmd, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);
            c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphics_pipeline);

            const offsets = [_]c.VkDeviceSize{0};
            c.vkCmdBindVertexBuffers(cmd, 0, 1, &self.vertex_buffer_set.vkBuffers[current_frame], &offsets);

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

            const viewport = c.VkViewport{
                .x = 0.0,
                .y = 0,
                .width = @floatFromInt(self.swap_extent.width),
                .height = @as(f32, @floatFromInt(self.swap_extent.height)),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            };
            c.vkCmdSetViewport(cmd, 0, 1, @ptrCast(&viewport));

            const scissor = c.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_extent,
            };
            c.vkCmdSetScissor(cmd, 0, 1, @ptrCast(&scissor));

            c.vkCmdDraw(cmd, 6, 1, 0, 0);
            c.vkCmdEndRenderPass(cmd);
            try handleError(c.vkEndCommandBuffer(cmd)); // Catch error here!

            // 5. Submit to Graphics Queue (Added explicit @ptrCasts to guarantee C-compatibility)
            const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
            const submit_info = c.VkSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pNext = null,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = @ptrCast(&self.image_availible_semaphore[current_frame]),
                .pWaitDstStageMask = @ptrCast(&wait_stages),
                .commandBufferCount = 1,
                .pCommandBuffers = @ptrCast(&cmd),
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = @ptrCast(&self.render_finished_semaphore[current_frame]),
            };

            // Catch error here! If this fails, the app will panic immediately instead of generating un-signaled wait errors.
            try handleError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[current_frame]));

            // 6. Present to Screen
            const present_info = c.VkPresentInfoKHR{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .pNext = null,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = @ptrCast(&self.render_finished_semaphore[current_frame]),
                .swapchainCount = 1,
                .pSwapchains = @ptrCast(&self.swapchain),
                .pImageIndices = &image_index,
                .pResults = null,
            };

            const present_result = c.vkQueuePresentKHR(self.present_queue, &present_info);

            // Check if the swapchain became invalid during presentation
            if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
                // Flag a resize for the start of the next loop iteration
                window_resized = true;
            } else if (present_result != c.VK_SUCCESS) {
                return error.VulkanPresentFailed;
            }

            // 7. Advance Frame
            current_frame = (current_frame + 1) % FRAMES_IN_FLIGHT;
        }

        // Ensure the GPU has finished everything before tearing down
        _ = c.vkDeviceWaitIdle(self.device);

        defer std.log.info("Running loop OK", .{});
    }

    pub fn recreateSwapchain(self: *App) !void {
        std.log.info("Recreating swapchain...", .{});
        errdefer std.log.info("Recreating swapchain failed", .{});

        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSizeInPixels(self.window, &w, &h);
        while (w == 0 or h == 0) {
            _ = c.SDL_GetWindowSizeInPixels(self.window, &w, &h);
            _ = c.SDL_WaitEvent(null); // Pause the thread while minimized
        }

        _ = c.vkDeviceWaitIdle(self.device);

        util.deinitFramebuffers(self.allocator, self.device, self.framebuffers);
        util.deinitVkImageViews(self.allocator, self.device, self.image_views);
        util.deinitVkImages(self.allocator, self.images);
        util.deinitVkSwapchain(self.device, self.swapchain);

        self.surface_capabilities = try util.getPhysicalDeviceSurfaceCapabilities(self.physical_device, self.surface);
        self.swap_extent = try util.getVkExtentFromSDLWindow(self.window, self.surface_capabilities);

        self.swapchain = try util.initVkSwapchain(self.device, self.surface, self.surface_capabilities, self.surface_format, self.swap_extent, self.present_mode, self.graphics_queue_index, self.present_queue_index);
        self.images = try util.initVkImages(self.allocator, self.device, self.swapchain);
        self.image_views = try util.initVkImageViews(self.allocator, self.device, self.images, self.surface_format);
        self.framebuffers = try util.initFramebuffers(self.allocator, self.device, self.image_views, self.render_pass, self.swap_extent);
        defer std.log.info("Recreating swapchain OK", .{});
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
        defer util.deinitVkSemaphores(self.allocator, self.device, self.render_finished_semaphore);
        defer util.deinitVkSemaphores(self.allocator, self.device, self.image_availible_semaphore);
        defer util.deinitVkFences(self.allocator, self.device, self.in_flight_fences);
        defer util.deinitVkDescriptorPool(self.device, self.descriptor_pool);
        defer util.deinitVkDescriptorSets(self.allocator, self.descriptor_sets);
    }
};
