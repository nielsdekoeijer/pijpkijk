const std = @import("std");
const build_options = @import("build_options");
const Io = std.Io;
const c = @import("c.zig").c;
const handleError = @import("error.zig").handleError;
const util = @import("util.zig");
pub const sdl = @import("sdl.zig");
const pipewire = @import("pipewire.zig");
const types = @import("types.zig");

pub const FRAMES_IN_FLIGHT = 3;

pub const UserData = enum(u64) {
    ANAS,
    PIPEWIRE_START_RETRY,
    PIPEWIRE_EVENT,
};

pub const App = AppImpl(sdl.Handle);

pub fn AppImpl(comptime BackendHandle: type) type {
    return struct {
        window_handle: *BackendHandle,
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
        drag_start: ?[2]f32 = null,
        port_drag: ?PortDragState = null,

        // Layout
        auto_layout: bool = true,

        // Profiling visualization
        show_profile_load: bool = false,

        // Search state
        search_mode: SearchMode = .none,
        search_buf: [128]u8 = undefined,
        search_len: usize = 0,
        search_selected: usize = 0,
        saved_camera_pos: [2]f32 = .{ 0, 0 },
        saved_scale: f32 = 1.0,

        const SearchMode = enum { none, move_node, view_node, connect_output, connect_input };

        const MAX_SEARCH_RESULTS = 10;

        const Self = @This();

        fn dpiScale(self: *const Self) f32 {
            return @as(f32, @floatFromInt(self.window_handle.state.fractional_scale)) / 120.0;
        }

        const PortDragState = struct {
            node_id: u32,
            port_id: u32,
            is_output: bool,
            anchor: [2]f32,
            visual_index: usize = 0,
            from_search: bool = false,
            awaiting_release: bool = false,
            completed: bool = false,
        };

        const SearchResult = struct {
            node_id: u32,
            name: []const u8,
            score: i32,
        };

        /// Case-insensitive fuzzy substring match. Returns a score (lower = better) or null if no match.
        fn fuzzyMatch(needle: []const u8, haystack: []const u8) ?i32 {
            if (needle.len == 0) return 0;
            var ni: usize = 0;
            var score: i32 = 0;
            var last_match: i32 = -1;
            for (haystack, 0..) |hc, hi| {
                const h = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
                const n = if (needle[ni] >= 'A' and needle[ni] <= 'Z') needle[ni] + 32 else needle[ni];
                if (h == n) {
                    // Penalize gaps between matched characters
                    if (last_match >= 0) {
                        score += @as(i32, @intCast(hi)) - last_match - 1;
                    } else {
                        score += @intCast(hi); // penalize late start
                    }
                    last_match = @intCast(hi);
                    ni += 1;
                    if (ni >= needle.len) return score;
                }
            }
            return null; // not all needle chars found
        }

        /// Gather search results matching the current search buffer, sorted by score
        fn getSearchResults(self: *Self, results: *[MAX_SEARCH_RESULTS]SearchResult) usize {
            var count: usize = 0;
            const needle = self.search_buf[0..self.search_len];

            var it = self.pipewire_handle.nodes.iterator();
            while (it.next()) |entry| {
                const node = entry.value_ptr;
                if (fuzzyMatch(needle, node.name)) |score| {
                    // Insert sorted by score
                    var insert_pos: usize = count;
                    while (insert_pos > 0 and results[insert_pos - 1].score > score) {
                        if (insert_pos < MAX_SEARCH_RESULTS) {
                            results[insert_pos] = results[insert_pos - 1];
                        }
                        insert_pos -= 1;
                    }
                    if (insert_pos < MAX_SEARCH_RESULTS) {
                        results[insert_pos] = .{
                            .node_id = node.node_id,
                            .name = node.name,
                            .score = score,
                        };
                        if (count < MAX_SEARCH_RESULTS) count += 1;
                    }
                }
            }
            return count;
        }

        const PortSearchResult = struct {
            node_id: u32,
            port_id: u32,
            is_output: bool,
            visual_index: usize,
            score: i32,
            display_name_buf: [128]u8 = undefined,
            display_name_len: usize = 0,

            fn displayName(self: *const PortSearchResult) []const u8 {
                return self.display_name_buf[0..self.display_name_len];
            }
        };

        fn getPortSearchResults(self: *Self, comptime for_outputs: bool, results: *[MAX_SEARCH_RESULTS]PortSearchResult) usize {
            var count: usize = 0;
            const needle = self.search_buf[0..self.search_len];

            var it = self.pipewire_handle.nodes.iterator();
            while (it.next()) |entry| {
                const node = entry.value_ptr;
                const ports = if (for_outputs) &node.outs else &node.inps;
                var port_it = ports.iterator();
                var vi: usize = 0;
                while (port_it.next()) |port_entry| : (vi += 1) {
                    const port = port_entry.value_ptr;
                    // Build "nodename:portname"
                    var name_buf: [128]u8 = undefined;
                    var name_len: usize = 0;
                    const nname = node.name;
                    const pname = port.name;
                    const needed = nname.len + 1 + pname.len;
                    if (needed <= name_buf.len) {
                        @memcpy(name_buf[0..nname.len], nname);
                        name_buf[nname.len] = ':';
                        @memcpy(name_buf[nname.len + 1 .. needed], pname);
                        name_len = needed;
                    } else {
                        continue;
                    }

                    if (fuzzyMatch(needle, name_buf[0..name_len])) |score| {
                        var insert_pos: usize = count;
                        while (insert_pos > 0 and results[insert_pos - 1].score > score) {
                            if (insert_pos < MAX_SEARCH_RESULTS) {
                                results[insert_pos] = results[insert_pos - 1];
                            }
                            insert_pos -= 1;
                        }
                        if (insert_pos < MAX_SEARCH_RESULTS) {
                            results[insert_pos] = .{
                                .node_id = node.node_id,
                                .port_id = port_entry.key_ptr.*,
                                .is_output = for_outputs,
                                .visual_index = vi,
                                .score = score,
                            };
                            results[insert_pos].display_name_buf = name_buf;
                            results[insert_pos].display_name_len = name_len;
                            if (count < MAX_SEARCH_RESULTS) count += 1;
                        }
                    }
                }
            }
            return count;
        }

        const version = build_options.version;
        const name = "pijpkijk";
        const identifier = "com.nielsdekoeijer.pijpkijk";
        const default_width = 800;
        const default_height = 600;

        pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
            _ = io;

            var self: Self = undefined;
            self.allocator = allocator;

            self.ring = try std.os.linux.IoUring.init(32, 0);
            errdefer self.ring.deinit();

            // =InitializeWindowBackend====================================================================================
            self.window_handle = try allocator.create(BackendHandle);
            try BackendHandle.init(self.window_handle);

            try self.window_handle.start_core();
            while (!self.window_handle.core_ready()) {
                try self.window_handle.flush_blocking();
            }

            while (!self.window_handle.seat_ready()) {
                try self.window_handle.flush_blocking();
            }

            try self.window_handle.start_surface();
            while (!self.window_handle.surface_ready()) {
                try self.window_handle.flush_blocking();
            }

            // =InitializePipewire=========================================================================================
            self.pipewire_handle = try pipewire.PipewireHandle.init(self.allocator);

            // =AqcuireVkInstance==========================================================================================
            self.instance = try util.initVkInstance(allocator, try BackendHandle.getVkInstanceExtensions());
            errdefer util.deinitVkInstance(self.instance);

            // =AqcuireVkSurface===========================================================================================
            self.surface = try self.window_handle.createVkSurface(self.instance);
            errdefer util.deinitVkSurface(self.instance, self.surface);

            // =AqcuireVkPhysicalDevice====================================================================================
            self.physical_device = try util.initVkPhysicalDevice(allocator, self.instance, self.surface);
            self.graphics_queue_index = try util.findGraphicsQueueIndex(allocator, self.physical_device);
            self.present_queue_index = try util.findPresentQueueIndex(allocator, self.surface, self.physical_device);
            self.surface_capabilities = try util.getPhysicalDeviceSurfaceCapabilities(self.physical_device, self.surface);
            self.swap_extent = self.window_handle.getVkExtent(self.surface_capabilities);
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
            errdefer util.deinitVertexBufferSet(allocator, self.device, self.bezier_vertex_buffer_set);

            self.text_vertex_buffer_set = try util.initVertexBufferSet(
                types.TextVertex,
                allocator,
                self.device,
                self.physical_device,
                100000,
                FRAMES_IN_FLIGHT,
            );
            errdefer util.deinitVertexBufferSet(allocator, self.device, self.text_vertex_buffer_set);

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
            self.drag_start = null;
            self.port_drag = null;
            self.auto_layout = true;
            self.show_profile_load = false;

            self.search_mode = .none;
            self.search_len = 0;
            self.search_selected = 0;
            self.saved_camera_pos = .{ 0, 0 };
            self.saved_scale = 1.0;

            return self;
        }

        pub fn run(self: *Self) !void {
            std.log.info("Running loop...", .{});
            errdefer std.log.info("Running loop exited with failure", .{});

            var running = true;
            var current_frame: usize = 0;
            var window_resized = false;
            var needs_render = true;
            var needs_state_update = false;

            var gpu_frame_ready = [_]bool{ true, true, true };

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
                    .nsec = 10 * 1_000_000,
                }, 0, 0);

                sqe.user_data = @intFromEnum(UserData.PIPEWIRE_START_RETRY);
            }

            _ = try self.ring.submit();

            // Our main loop of the program
            while (running) {
                if (!needs_render) self.window_handle.idle();

                // Process leftover events from our last loop
                if (try self.window_handle.dispatch()) {
                    needs_render = true;
                    needs_state_update = true;
                }

                var cqes: [16]std.os.linux.io_uring_cqe = undefined;

                const cqe_count = try self.ring.copy_cqes(&cqes, 0);

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
                                    try self.pipewire_handle.drain(self.auto_layout);

                                    needs_state_update = true;
                                    needs_render = true;
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
                    }
                }

                {
                    _ = try self.ring.submit();
                }

                // Check if we should shut down
                if (self.window_handle.state.should_close) {
                    running = false;
                }

                // Update program state based on e.g. inputs
                if (needs_state_update) {
                    needs_state_update = false;

                    if (self.window_handle.state.input.scroll_y != 0 or self.window_handle.state.input.scroll_x != 0) {
                        if (self.window_handle.state.input.scroll_is_finger) {
                            // Trackpad 2-finger scroll → pan
                            self.camera_pos[0] += self.window_handle.state.input.scroll_x * 3.0 / self.scale;
                            self.camera_pos[1] += self.window_handle.state.input.scroll_y * 3.0 / self.scale;
                        } else {
                            // Mouse wheel → zoom
                            const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                            const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;

                            const zoom_factor = 1.0 - (self.window_handle.state.input.scroll_y * 0.08);

                            const world_x_before = (mouse_x / self.scale) + self.camera_pos[0];
                            const world_y_before = (mouse_y / self.scale) + self.camera_pos[1];

                            self.scale *= zoom_factor;
                            self.scale = std.math.clamp(self.scale, 0.05, 5.0);

                            const world_x_after = (mouse_x / self.scale) + self.camera_pos[0];
                            const world_y_after = (mouse_y / self.scale) + self.camera_pos[1];

                            self.camera_pos[0] += (world_x_before - world_x_after);
                            self.camera_pos[1] += (world_y_before - world_y_after);
                        }

                        self.window_handle.state.input.scroll_x = 0;
                        self.window_handle.state.input.scroll_y = 0;
                        self.window_handle.scale_snapshot = self.scale;
                        needs_render = true;
                    }

                    // Pinch gesture → zoom
                    if (self.window_handle.state.input.pinch_scale != 0) {
                        const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                        const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;

                        const world_x_before = (mouse_x / self.scale) + self.camera_pos[0];
                        const world_y_before = (mouse_y / self.scale) + self.camera_pos[1];

                        self.scale = std.math.clamp(self.window_handle.state.input.pinch_scale, 0.05, 5.0);

                        const world_x_after = (mouse_x / self.scale) + self.camera_pos[0];
                        const world_y_after = (mouse_y / self.scale) + self.camera_pos[1];

                        self.camera_pos[0] += (world_x_before - world_x_after);
                        self.camera_pos[1] += (world_y_before - world_y_after);

                        needs_render = true;
                    }

                    if (self.window_handle.state.input.mouse_down_r) {
                        if (self.port_drag != null) {
                            self.port_drag = null;
                        } else {
                            self.camera_pos[0] -= self.window_handle.state.input.mouse_dx / self.scale;
                            self.camera_pos[1] -= self.window_handle.state.input.mouse_dy / self.scale;
                        }
                        needs_render = true;
                    }

                    // Port drag: bezier preview always follows mouse, click completes
                    if (self.port_drag) |drag| {
                        if (drag.awaiting_release) {
                            // Wait for mouse button release before accepting next click
                            if (!self.window_handle.state.input.mouse_down_l) {
                                if (drag.completed) {
                                    // Connection was completed, fully clear now
                                    self.port_drag = null;
                                } else {
                                    self.port_drag.?.awaiting_release = false;
                                }
                            }
                        } else if (self.window_handle.state.input.mouse_down_l) {
                            const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                            const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;
                            const world_x = (mouse_x / self.scale) + self.camera_pos[0];
                            const world_y = (mouse_y / self.scale) + self.camera_pos[1];

                            // Hit-test for a target port of opposite type
                            var it = self.pipewire_handle.nodes.iterator();
                            while (it.next()) |entry| {
                                if (entry.value_ptr.hitTestPort(world_x, world_y)) |hit| {
                                    if (hit.is_output != drag.is_output) {
                                        if (drag.is_output) {
                                            self.pipewire_handle.createLink(drag.node_id, drag.port_id, hit.node_id, hit.port_id);
                                        } else {
                                            self.pipewire_handle.createLink(hit.node_id, hit.port_id, drag.node_id, drag.port_id);
                                        }
                                        break;
                                    }
                                }
                            }
                            // Mark completed; wait for release before clearing
                            self.port_drag.?.awaiting_release = true;
                            self.port_drag.?.completed = true;
                        }
                        needs_render = true;
                    } else if (self.window_handle.state.input.mouse_down_l) {
                        const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                        const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;
                        const world_x = (mouse_x / self.scale) + self.camera_pos[0];
                        const world_y = (mouse_y / self.scale) + self.camera_pos[1];

                        if (self.selected_node) |node_id| {
                            if (self.pipewire_handle.nodes.getPtr(@intCast(node_id))) |node| {
                                node.x.? += self.window_handle.state.input.mouse_dx / self.scale;
                                node.y.? += self.window_handle.state.input.mouse_dy / self.scale;
                                needs_render = true;
                            }
                        } else {
                            // First frame of drag: try port hit, then node pick, then region select
                            if (self.drag_start == null) {
                                // Try port hit-test first
                                var port_hit: ?types.PipewireNode.PortHit = null;
                                {
                                    var it = self.pipewire_handle.nodes.iterator();
                                    while (it.next()) |entry| {
                                        if (entry.value_ptr.hitTestPort(world_x, world_y)) |hit| {
                                            port_hit = hit;
                                            break;
                                        }
                                    }
                                }

                                if (port_hit) |hit| {
                                    self.port_drag = .{
                                        .node_id = hit.node_id,
                                        .port_id = hit.port_id,
                                        .is_output = hit.is_output,
                                        .anchor = hit.center,
                                        .visual_index = hit.visual_index,
                                        .awaiting_release = true,
                                    };
                                    needs_render = true;
                                } else {
                                    // Try node pick (select topmost = lowest z)
                                    var best_z: f32 = std.math.inf(f32);
                                    var best_node: ?usize = null;
                                    var it = self.pipewire_handle.nodes.iterator();
                                    while (it.next()) |entry| {
                                        const n = entry.value_ptr;
                                        if (n.x) |nx| {
                                            if (n.y) |ny| {
                                                const w = types.PipewireNode.W_NODE;
                                                const h = n.computeNodeHeight();
                                                if (world_x >= nx and world_x <= nx + w and
                                                    world_y >= ny and world_y <= ny + h)
                                                {
                                                    const z = n.z orelse std.math.inf(f32);
                                                    if (z < best_z) {
                                                        best_z = z;
                                                        best_node = entry.key_ptr.*;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    if (best_node) |node_id| {
                                        self.selected_node = node_id;
                                        // Bring to front: find min z across all nodes, go below it
                                        var min_z: f32 = std.math.inf(f32);
                                        var zit = self.pipewire_handle.nodes.iterator();
                                        while (zit.next()) |entry| {
                                            if (entry.value_ptr.z) |z| {
                                                if (z < min_z) min_z = z;
                                            }
                                        }
                                        if (self.pipewire_handle.nodes.getPtr(@intCast(node_id))) |node| {
                                            node.z = @max(min_z - 1, 1);
                                        }
                                    } else {
                                        self.drag_start = .{ world_x, world_y };
                                    }
                                }
                            }

                            // Active region select: mark links within the rectangle
                            if (self.drag_start) |start| {
                                const min_x = @min(start[0], world_x);
                                const max_x = @max(start[0], world_x);
                                const min_y = @min(start[1], world_y);
                                const max_y = @max(start[1], world_y);

                                var it = self.pipewire_handle.nodes.iterator();
                                while (it.next()) |entry| {
                                    try entry.value_ptr.markLinksInRegion(
                                        self.pipewire_handle.nodes,
                                        min_x,
                                        min_y,
                                        max_x,
                                        max_y,
                                        self.window_handle.state.input.shift_held,
                                    );
                                }
                                needs_render = true;
                            }
                        }
                    } else {
                        // Mouse released (no port_drag active)
                        self.selected_node = null;
                        self.drag_start = null;
                    }

                    if (self.search_mode != .none) {
                        // --- Search mode input handling ---
                        var search_closed = false;

                        if (self.window_handle.state.input.key_escape) |ke| {
                            if (ke == .PRESSED) {
                                // Cancel search
                                if (self.search_mode == .view_node) {
                                    self.camera_pos = self.saved_camera_pos;
                                    self.scale = self.saved_scale;
                                }
                                self.search_mode = .none;
                                self.window_handle.state.input.key_escape = null;
                                search_closed = true;
                                needs_render = true;
                            }
                        }

                        if (!search_closed) {
                            if (self.window_handle.state.input.key_question) |kq| {
                                if (kq == .PRESSED and self.search_mode == .move_node) {
                                    self.search_mode = .none;
                                    self.window_handle.state.input.key_question = null;
                                    search_closed = true;
                                    needs_render = true;
                                }
                            }
                        }

                        if (!search_closed) {
                            if (self.window_handle.state.input.key_slash) |ks| {
                                if (ks == .PRESSED and self.search_mode == .view_node) {
                                    // Cancel view search
                                    self.camera_pos = self.saved_camera_pos;
                                    self.scale = self.saved_scale;
                                    self.search_mode = .none;
                                    self.window_handle.state.input.key_slash = null;
                                    search_closed = true;
                                    needs_render = true;
                                }
                            }
                        }

                        if (!search_closed) {
                            if (self.window_handle.state.input.key_greater) |kg| {
                                if (kg == .PRESSED and self.search_mode == .connect_output) {
                                    self.search_mode = .none;
                                    self.window_handle.state.input.key_greater = null;
                                    search_closed = true;
                                    needs_render = true;
                                }
                            }
                        }

                        if (!search_closed) {
                            if (self.window_handle.state.input.key_less) |kl| {
                                if (kl == .PRESSED and self.search_mode == .connect_input) {
                                    self.search_mode = .none;
                                    self.window_handle.state.input.key_less = null;
                                    search_closed = true;
                                    needs_render = true;
                                }
                            }
                        }

                        if (!search_closed) {
                            if (self.window_handle.state.input.key_return) |kr| {
                                if (kr == .PRESSED) {
                                    if (self.search_mode == .connect_output or self.search_mode == .connect_input) {
                                        // Confirm port search: set up port_drag from search
                                        const for_outputs = (self.search_mode == .connect_output);
                                        var port_results: [MAX_SEARCH_RESULTS]PortSearchResult = undefined;
                                        const pcount = if (for_outputs)
                                            self.getPortSearchResults(true, &port_results)
                                        else
                                            self.getPortSearchResults(false, &port_results);
                                        if (pcount > 0) {
                                            const sel = @min(self.search_selected, pcount - 1);
                                            const pr = port_results[sel];
                                            if (self.pipewire_handle.nodes.getPtr(pr.node_id)) |node| {
                                                const anchor = if (pr.is_output)
                                                    [2]f32{ node.getOutPortX(pr.visual_index), node.getOutPortY(pr.visual_index) }
                                                else
                                                    [2]f32{ node.getInpPortX(pr.visual_index), node.getInpPortY(pr.visual_index) };
                                                self.port_drag = .{
                                                    .node_id = pr.node_id,
                                                    .port_id = pr.port_id,
                                                    .is_output = pr.is_output,
                                                    .anchor = anchor,
                                                    .visual_index = pr.visual_index,
                                                    .from_search = true,
                                                };
                                            }
                                        }
                                        self.search_mode = .none;
                                        self.window_handle.state.input.key_return = null;
                                        search_closed = true;
                                        needs_render = true;
                                    } else {
                                        // Confirm node search
                                        var results: [MAX_SEARCH_RESULTS]SearchResult = undefined;
                                        const count = self.getSearchResults(&results);
                                        if (count > 0) {
                                            const sel = @min(self.search_selected, count - 1);
                                            const node_id = results[sel].node_id;
                                            if (self.search_mode == .move_node) {
                                                // Move selected node to cursor position
                                                if (self.pipewire_handle.nodes.getPtr(node_id)) |node| {
                                                    const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                                                    const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;
                                                    const world_x = (mouse_x / self.scale) + self.camera_pos[0];
                                                    const world_y = (mouse_y / self.scale) + self.camera_pos[1];
                                                    node.x = world_x - types.PipewireNode.W_NODE / 2.0;
                                                    node.y = world_y - node.computeNodeHeight() / 2.0;
                                                }
                                            }
                                            // For view_node, camera is already positioned from live preview
                                        }
                                        self.search_mode = .none;
                                        self.window_handle.state.input.key_return = null;
                                        search_closed = true;
                                        needs_render = true;
                                    }
                                }
                            }

                            if (self.window_handle.state.input.key_up) |ku| {
                                if (ku == .PRESSED or ku == .REPEATED) {
                                    if (self.search_selected > 0) self.search_selected -= 1;
                                    self.window_handle.state.input.key_up = null;
                                    needs_render = true;
                                }
                            }

                            if (self.window_handle.state.input.key_down) |kd| {
                                if (kd == .PRESSED or kd == .REPEATED) {
                                    self.search_selected += 1;
                                    self.window_handle.state.input.key_down = null;
                                    needs_render = true;
                                }
                            }

                            if (self.window_handle.state.input.key_backspace) |kb| {
                                if (kb == .PRESSED or kb == .REPEATED) {
                                    if (self.search_len > 0) self.search_len -= 1;
                                    self.search_selected = 0;
                                    self.window_handle.state.input.key_backspace = null;
                                    needs_render = true;
                                }
                            }

                            // Typed character (but not the key that opened the search)
                            if (self.window_handle.state.input.typed_codepoint) |cp| {
                                const is_trigger = (cp == '?' and self.search_mode == .move_node) or
                                    (cp == '/' and self.search_mode == .view_node) or
                                    (cp == '>' and self.search_mode == .connect_output) or
                                    (cp == '<' and self.search_mode == .connect_input);
                                if (!is_trigger and self.search_len < self.search_buf.len) {
                                    if (std.math.cast(u8, cp)) |byte| {
                                        self.search_buf[self.search_len] = byte;
                                        self.search_len += 1;
                                        self.search_selected = 0;
                                        needs_render = true;
                                    }
                                }
                            }
                        }

                        // Consume normal-mode keys so they don't leak when search closes
                        self.window_handle.state.input.key_q = null;
                        self.window_handle.state.input.key_r = null;
                        self.window_handle.state.input.key_l = null;
                        self.window_handle.state.input.key_p = null;
                        self.window_handle.state.input.key_h = null;
                        self.window_handle.state.input.key_delete = null;
                        self.window_handle.state.input.key_greater = null;
                        self.window_handle.state.input.key_less = null;

                        // Live camera update for view_node mode (only after typing)
                        if (self.search_mode == .view_node and self.search_len > 0) {
                            var results: [MAX_SEARCH_RESULTS]SearchResult = undefined;
                            const count = self.getSearchResults(&results);
                            if (count > 0) {
                                const sel = @min(self.search_selected, count - 1);
                                if (self.pipewire_handle.nodes.get(results[sel].node_id)) |node| {
                                    if (node.x) |nx| {
                                        if (node.y) |ny| {
                                            const sw: f32 = @floatFromInt(self.window_handle.state.width);
                                            const sh: f32 = @floatFromInt(self.window_handle.state.height);
                                            const node_cx = nx + types.PipewireNode.W_NODE / 2.0;
                                            const node_cy = ny + node.computeNodeHeight() / 2.0;
                                            self.camera_pos[0] = node_cx - (sw / 2.0) / self.scale;
                                            self.camera_pos[1] = node_cy - (sh / 2.0) / self.scale;
                                            needs_render = true;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // --- Normal mode input handling ---
                        if (self.window_handle.state.input.key_q) |key_q| {
                            if (key_q == .PRESSED) {
                                running = false;
                            }
                        }

                        if (self.window_handle.state.input.key_r) |key_r| {
                            if (key_r == .PRESSED) {
                                try self.pipewire_handle.update_graph_metadata();
                            }
                        }

                        if (self.window_handle.state.input.key_l) |key_l| {
                            if (key_l == .PRESSED) {
                                self.auto_layout = !self.auto_layout;
                            }
                        }

                        if (self.window_handle.state.input.key_p) |key_p| {
                            if (key_p == .PRESSED) {
                                self.show_profile_load = !self.show_profile_load;
                                needs_render = true;
                            }
                            self.window_handle.state.input.key_p = null;
                        }

                        if (self.window_handle.state.input.key_delete) |key_delete| {
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

                        if (self.window_handle.state.input.key_h) |kh| {
                            if (kh == .PRESSED or kh == .REPEATED) {
                                needs_render = true;
                            }
                        }

                        if (self.window_handle.state.input.key_question) |kq| {
                            if (kq == .PRESSED) {
                                self.search_mode = .move_node;
                                self.search_len = 0;
                                self.search_selected = 0;
                                self.window_handle.state.input.key_question = null;
                                needs_render = true;
                            }
                        }

                        if (self.window_handle.state.input.key_slash) |ks| {
                            if (ks == .PRESSED) {
                                self.search_mode = .view_node;
                                self.search_len = 0;
                                self.search_selected = 0;
                                self.saved_camera_pos = self.camera_pos;
                                self.saved_scale = self.scale;
                                self.window_handle.state.input.key_slash = null;
                                needs_render = true;
                            }
                        }

                        if (self.window_handle.state.input.key_greater) |kg| {
                            if (kg == .PRESSED) {
                                self.search_mode = .connect_output;
                                self.search_len = 0;
                                self.search_selected = 0;
                                self.window_handle.state.input.key_greater = null;
                                needs_render = true;
                            }
                        }

                        if (self.window_handle.state.input.key_less) |kl| {
                            if (kl == .PRESSED) {
                                self.search_mode = .connect_input;
                                self.search_len = 0;
                                self.search_selected = 0;
                                self.window_handle.state.input.key_less = null;
                                needs_render = true;
                            }
                        }

                        if (self.window_handle.state.input.key_escape) |key_escape| {
                            if (key_escape == .PRESSED) {
                                self.port_drag = null;
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
                    }

                    // Clear typed codepoint so it doesn't repeat
                    self.window_handle.state.input.typed_codepoint = null;

                    // Reset frame deltas so they don't repeatedly apply
                    self.window_handle.state.input.mouse_dx = 0;
                    self.window_handle.state.input.mouse_dy = 0;
                }

                // Do a render if required
                if (needs_render and self.window_handle.state.frame_ready) {
                    needs_render = false;

                    {
                        const new_extent = self.window_handle.getVkExtent(self.surface_capabilities);
                        if (self.swap_extent.width != new_extent.width or
                            self.swap_extent.height != new_extent.height)
                        {
                            window_resized = true;
                        }
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
                            .scale = self.scale * self.dpiScale(),
                        };
                    }

                    // Update QuadVertex buffers for our nodes
                    var quad_vertices = try std.ArrayList(types.QuadVertex).initCapacity(self.allocator, 0);
                    defer quad_vertices.deinit(self.allocator);
                    var overlay_vertex_count: u32 = 0;
                    {
                        var runtime_min_ns: ?f32 = null;
                        var runtime_max_ns: ?f32 = null;
                        if (self.show_profile_load) {
                            var node_it = self.pipewire_handle.nodes.iterator();
                            while (node_it.next()) |node| {
                                const runtime = node.value_ptr.mean_runtime_ns orelse continue;
                                runtime_min_ns = @min(runtime_min_ns orelse runtime, runtime);
                                runtime_max_ns = @max(runtime_max_ns orelse runtime, runtime);
                            }
                        }
                        {
                            var node_it = self.pipewire_handle.nodes.iterator();
                            while (node_it.next()) |node| {
                                if (node.value_ptr.x == null or node.value_ptr.y == null or node.value_ptr.z == null or node.value_ptr.port_color == null) continue;
                                try node.value_ptr.appendVerticesNode(self.allocator, &quad_vertices, runtime_min_ns, runtime_max_ns);
                            }
                        }
                        {
                            var node_it = self.pipewire_handle.nodes.iterator();
                            while (node_it.next()) |node| {
                                if (node.value_ptr.x == null or node.value_ptr.y == null or node.value_ptr.z == null or node.value_ptr.port_color == null) continue;
                                try node.value_ptr.appendVerticesPorts(self.allocator, &quad_vertices);
                            }
                        }

                        const scene_vertex_count = quad_vertices.items.len;

                        // Selection rectangle (appended after scene quads, drawn separately)
                        if (self.drag_start) |start| {
                            if (self.window_handle.state.input.mouse_x) |mx| {
                                if (self.window_handle.state.input.mouse_y) |my| {
                                    const world_ex = (mx / self.scale) + self.camera_pos[0];
                                    const world_ey = (my / self.scale) + self.camera_pos[1];
                                    const rx = @min(start[0], world_ex);
                                    const ry = @min(start[1], world_ey);
                                    const rw = @abs(world_ex - start[0]);
                                    const rh = @abs(world_ey - start[1]);
                                    const select_color = [4]f32{ 0.4, 0.6, 1.0, 0.35 };
                                    const select_radii = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
                                    try types.QuadVertex.append(self.allocator, &quad_vertices, rx, ry, 1.0, rw, rh, select_color, select_radii);
                                }
                            }
                        }

                        // Help overlay background (now triggered by H key)
                        if (self.window_handle.state.input.key_h) |kh| {
                            if (kh == .PRESSED or kh == .REPEATED) {
                                const sw: f32 = @floatFromInt(self.window_handle.state.width);
                                const sh: f32 = @floatFromInt(self.window_handle.state.height);
                                const overlay_w: f32 = 620.0;
                                const overlay_h: f32 = 604.0;
                                const ox = ((sw - overlay_w) / 2.0) / self.scale + self.camera_pos[0];
                                const oy = ((sh - overlay_h) / 2.0) / self.scale + self.camera_pos[1];
                                const ow = overlay_w / self.scale;
                                const oh = overlay_h / self.scale;
                                try types.QuadVertex.append(self.allocator, &quad_vertices, ox, oy, 1.0, ow, oh, .{ 0.15, 0.15, 0.15, 0.92 }, .{ 10.0, 10.0, 10.0, 10.0 });
                            }
                        }

                        // Search dialog overlay background
                        if (self.search_mode != .none) {
                            const sw: f32 = @floatFromInt(self.window_handle.state.width);
                            const clamped_count = blk: {
                                if (self.search_mode == .connect_output or self.search_mode == .connect_input) {
                                    var port_results: [MAX_SEARCH_RESULTS]PortSearchResult = undefined;
                                    const rc = if (self.search_mode == .connect_output)
                                        self.getPortSearchResults(true, &port_results)
                                    else
                                        self.getPortSearchResults(false, &port_results);
                                    break :blk @min(rc, MAX_SEARCH_RESULTS);
                                } else {
                                    var search_results: [MAX_SEARCH_RESULTS]SearchResult = undefined;
                                    const rc = self.getSearchResults(&search_results);
                                    break :blk @min(rc, MAX_SEARCH_RESULTS);
                                }
                            };
                            const overlay_w: f32 = 500.0;
                            const overlay_h: f32 = 60.0 + @as(f32, @floatFromInt(clamped_count)) * 32.0;
                            const ox = ((sw - overlay_w) / 2.0) / self.scale + self.camera_pos[0];
                            const oy = (40.0) / self.scale + self.camera_pos[1];
                            const ow = overlay_w / self.scale;
                            const oh = overlay_h / self.scale;
                            try types.QuadVertex.append(self.allocator, &quad_vertices, ox, oy, 1.0, ow, oh, .{ 0.12, 0.12, 0.12, 0.95 }, .{ 10.0, 10.0, 10.0, 10.0 });

                            // Highlight selected result
                            if (clamped_count > 0) {
                                const sel = @min(self.search_selected, clamped_count - 1);
                                const hl_y = oy + (50.0 + @as(f32, @floatFromInt(sel)) * 32.0) / self.scale;
                                const hl_h = 28.0 / self.scale;
                                try types.QuadVertex.append(self.allocator, &quad_vertices, ox + 8.0 / self.scale, hl_y, 1.0, ow - 16.0 / self.scale, hl_h, .{ 0.25, 0.35, 0.55, 0.8 }, .{ 4.0, 4.0, 4.0, 4.0 });
                            }
                        }

                        overlay_vertex_count = @intCast(quad_vertices.items.len - scene_vertex_count);

                        // TODO: this is ugly as sin, and its because our use of anyopque
                        if (quad_vertices.items.len > self.quad_vertex_buffer_set.max_vertices) {
                            std.log.warn("Quad vertex count ({}) exceeds GPU buffer capacity ({}), clamping", .{ quad_vertices.items.len, self.quad_vertex_buffer_set.max_vertices });
                            quad_vertices.items.len = self.quad_vertex_buffer_set.max_vertices;
                            overlay_vertex_count = 0;
                        }
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
                            if (node.value_ptr.x == null or node.value_ptr.y == null or node.value_ptr.z == null) continue;
                            try node.value_ptr.appendVerticesLinks(
                                self.allocator,
                                self.pipewire_handle.nodes,
                                &bezier_vertices,
                            );
                        }

                        // Append preview bezier for port drag (not when completed, just awaiting release)
                        if (self.port_drag) |drag| {
                            if (!drag.completed) {
                                const mouse_x = self.window_handle.state.input.mouse_x orelse 0.0;
                                const mouse_y = self.window_handle.state.input.mouse_y orelse 0.0;
                                const mouse_world = [2]f32{
                                    (mouse_x / self.scale) + self.camera_pos[0],
                                    (mouse_y / self.scale) + self.camera_pos[1],
                                };

                                // Recalculate anchor from node's current position so the
                                // preview follows when nodes move (e.g. new node spawns)
                                const anchor = if (self.pipewire_handle.nodes.getPtr(drag.node_id)) |node| blk: {
                                    break :blk if (drag.is_output)
                                        [2]f32{ node.getOutPortX(drag.visual_index), node.getOutPortY(drag.visual_index) }
                                    else
                                        [2]f32{ node.getInpPortX(drag.visual_index), node.getInpPortY(drag.visual_index) };
                                } else drag.anchor;

                                const p0 = if (drag.is_output) anchor else mouse_world;
                                const p3 = if (drag.is_output) mouse_world else anchor;
                                const offset = @abs(p3[0] - p0[0]) / 2.0;
                                const p1 = [2]f32{ p0[0] + offset, p0[1] };
                                const p2 = [2]f32{ p3[0] - offset, p3[1] };
                                const gray = [4]f32{ 0.7, 0.7, 0.7, 0.8 };

                                try types.BezierVertex.append(
                                    self.allocator,
                                    &bezier_vertices,
                                    4.0,
                                    10.0,
                                    gray,
                                    gray,
                                    false,
                                    p0,
                                    p1,
                                    p2,
                                    p3,
                                    1.0,
                                );
                            }
                        }

                        std.mem.sort(types.BezierVertex, bezier_vertices.items, {}, struct {
                            pub fn lessThanFn(_: void, lhs: types.BezierVertex, rhs: types.BezierVertex) bool {
                                return lhs.pos[2] > rhs.pos[2];
                            }
                        }.lessThanFn);

                        if (bezier_vertices.items.len > self.bezier_vertex_buffer_set.max_vertices) {
                            std.log.warn("Bezier vertex count ({}) exceeds GPU buffer capacity ({}), clamping", .{ bezier_vertices.items.len, self.bezier_vertex_buffer_set.max_vertices });
                            bezier_vertices.items.len = self.bezier_vertex_buffer_set.max_vertices;
                        }
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
                            if (node.value_ptr.x == null or node.value_ptr.y == null or node.value_ptr.z == null or node.value_ptr.port_color == null) continue;
                            try node.value_ptr.appendVerticesText(self.allocator, self.font_atlas, &text_vertices);
                        }

                        // Help overlay text (now triggered by H key)
                        if (self.window_handle.state.input.key_h) |kh| {
                            if (kh == .PRESSED or kh == .REPEATED) {
                                const sw: f32 = @floatFromInt(self.window_handle.state.width);
                                const sh: f32 = @floatFromInt(self.window_handle.state.height);
                                const overlay_w: f32 = 620.0;
                                const overlay_h: f32 = 576.0;
                                const base_x = ((sw - overlay_w) / 2.0 + 30.0) / self.scale + self.camera_pos[0];
                                const base_y = ((sh - overlay_h) / 2.0 + 40.0) / self.scale + self.camera_pos[1];
                                const line_h: f32 = 28.0 / self.scale;
                                const fs_title: f32 = 28.0 / self.scale;
                                const fs: f32 = 20.0 / self.scale;
                                const max_w: f32 = (overlay_w - 60.0) / self.scale;

                                var cy = base_y;
                                try types.TextVertex.append(self.allocator, self.font_atlas, "Keyboard Shortcuts", .Left, base_x, cy, 1.0, max_w, fs_title, &text_vertices, null);
                                cy += line_h * 1.8;

                                const help_lines = [_][2][]const u8{
                                    .{ "H", "Show this help" },
                                    .{ "?", "Search & move node to cursor" },
                                    .{ "/", "Search & center camera on node" },
                                    .{ ">", "Search output port & connect" },
                                    .{ "<", "Search input port & connect" },
                                    .{ "Q", "Quit" },
                                    .{ "R", "Re-layout graph" },
                                    .{ "L", "Toggle auto-layout" },
                                    .{ "P", "Toggle profiling colors" },
                                    .{ "Delete", "Delete selected connections" },
                                    .{ "Escape", "Deselect / cancel" },
                                };

                                for (help_lines) |line| {
                                    try types.TextVertex.append(self.allocator, self.font_atlas, line[0], .Left, base_x, cy, 1.0, max_w, fs, &text_vertices, null);
                                    try types.TextVertex.append(self.allocator, self.font_atlas, line[1], .Left, base_x + 160.0 / self.scale, cy, 1.0, max_w, fs, &text_vertices, null);
                                    cy += line_h;
                                }

                                cy += line_h * 0.8;
                                try types.TextVertex.append(self.allocator, self.font_atlas, "Mouse", .Left, base_x, cy, 1.0, max_w, fs_title, &text_vertices, null);
                                cy += line_h * 1.5;

                                const mouse_lines = [_][2][]const u8{
                                    .{ "Click port", "Create connection" },
                                    .{ "Drag node", "Move node" },
                                    .{ "Drag empty", "Region select" },
                                    .{ "Right drag", "Pan camera" },
                                    .{ "Scroll", "Zoom" },
                                };

                                for (mouse_lines) |line| {
                                    try types.TextVertex.append(self.allocator, self.font_atlas, line[0], .Left, base_x, cy, 1.0, max_w, fs, &text_vertices, null);
                                    try types.TextVertex.append(self.allocator, self.font_atlas, line[1], .Left, base_x + 160.0 / self.scale, cy, 1.0, max_w, fs, &text_vertices, null);
                                    cy += line_h;
                                }
                            }
                        }

                        // Search dialog text
                        if (self.search_mode != .none) {
                            const sw: f32 = @floatFromInt(self.window_handle.state.width);
                            const overlay_w: f32 = 500.0;
                            const base_x = ((sw - overlay_w) / 2.0 + 20.0) / self.scale + self.camera_pos[0];
                            const base_y = (40.0 + 16.0) / self.scale + self.camera_pos[1];
                            const fs: f32 = 18.0 / self.scale;
                            const fs_small: f32 = 16.0 / self.scale;
                            const max_w: f32 = (overlay_w - 40.0) / self.scale;

                            // Title / prompt
                            const prompt_label: []const u8 = switch (self.search_mode) {
                                .move_node => "? Search & Move",
                                .view_node => "/ Search & View",
                                .connect_output => "> Connect Output",
                                .connect_input => "< Connect Input",
                                .none => unreachable,
                            };
                            try types.TextVertex.append(self.allocator, self.font_atlas, prompt_label, .Left, base_x, base_y, 1.0, max_w, fs, &text_vertices, .{ 0.6, 0.8, 1.0, 1.0 });

                            // Search text with cursor
                            var search_display: [130]u8 = undefined;
                            const query = self.search_buf[0..self.search_len];
                            const display_len = @min(query.len, 126);
                            @memcpy(search_display[0..display_len], query[0..display_len]);
                            search_display[display_len] = '_';
                            try types.TextVertex.append(self.allocator, self.font_atlas, search_display[0 .. display_len + 1], .Left, base_x + 200.0 / self.scale, base_y, 1.0, max_w, fs, &text_vertices, null);

                            // Results
                            if (self.search_mode == .connect_output or self.search_mode == .connect_input) {
                                var port_results: [MAX_SEARCH_RESULTS]PortSearchResult = undefined;
                                const result_count = if (self.search_mode == .connect_output)
                                    self.getPortSearchResults(true, &port_results)
                                else
                                    self.getPortSearchResults(false, &port_results);
                                const clamped_count = @min(result_count, MAX_SEARCH_RESULTS);

                                for (0..clamped_count) |ri| {
                                    const ry = base_y + (34.0 + @as(f32, @floatFromInt(ri)) * 32.0) / self.scale;
                                    const result_color: [4]f32 = if (ri == @min(self.search_selected, clamped_count - 1))
                                        .{ 1.0, 1.0, 1.0, 1.0 }
                                    else
                                        .{ 0.7, 0.7, 0.7, 0.9 };
                                    try types.TextVertex.append(self.allocator, self.font_atlas, port_results[ri].displayName(), .Left, base_x + 10.0 / self.scale, ry, 1.0, max_w, fs_small, &text_vertices, result_color);
                                }

                                if (clamped_count == 0 and self.search_len > 0) {
                                    const ry = base_y + 34.0 / self.scale;
                                    try types.TextVertex.append(self.allocator, self.font_atlas, "No results", .Left, base_x + 10.0 / self.scale, ry, 1.0, max_w, fs_small, &text_vertices, .{ 0.5, 0.5, 0.5, 0.8 });
                                }
                            } else {
                                var search_results: [MAX_SEARCH_RESULTS]SearchResult = undefined;
                                const result_count = self.getSearchResults(&search_results);
                                const clamped_count = @min(result_count, MAX_SEARCH_RESULTS);

                                for (0..clamped_count) |ri| {
                                    const ry = base_y + (34.0 + @as(f32, @floatFromInt(ri)) * 32.0) / self.scale;
                                    const result_color: [4]f32 = if (ri == @min(self.search_selected, clamped_count - 1))
                                        .{ 1.0, 1.0, 1.0, 1.0 }
                                    else
                                        .{ 0.7, 0.7, 0.7, 0.9 };
                                    try types.TextVertex.append(self.allocator, self.font_atlas, search_results[ri].name, .Left, base_x + 10.0 / self.scale, ry, 1.0, max_w, fs_small, &text_vertices, result_color);
                                }

                                if (clamped_count == 0 and self.search_len > 0) {
                                    const ry = base_y + 34.0 / self.scale;
                                    try types.TextVertex.append(self.allocator, self.font_atlas, "No results", .Left, base_x + 10.0 / self.scale, ry, 1.0, max_w, fs_small, &text_vertices, .{ 0.5, 0.5, 0.5, 0.8 });
                                }
                            }
                        }

                        if (text_vertices.items.len > self.text_vertex_buffer_set.max_vertices) {
                            std.log.warn("Text vertex count ({}) exceeds GPU buffer capacity ({}), clamping", .{ text_vertices.items.len, self.text_vertex_buffer_set.max_vertices });
                            text_vertices.items.len = self.text_vertex_buffer_set.max_vertices;
                        }
                        if (text_vertices.items.len > 0) {
                            const text_vert_map: [*]types.TextVertex = @ptrCast(@alignCast(
                                self.text_vertex_buffer_set.vkBuffersMapped[current_frame],
                            ));
                            @memcpy(text_vert_map[0..text_vertices.items.len], text_vertices.items);
                        }
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

                    const scene_quad_count: u32 = @intCast(quad_vertices.items.len - overlay_vertex_count);
                    if (scene_quad_count > 0) {
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

                        c.vkCmdDraw(cmd, scene_quad_count, 1, 0, 0);
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

                    // Draw selection overlay last so it doesn't write depth over scene content
                    if (overlay_vertex_count > 0) {
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

                        c.vkCmdDraw(cmd, overlay_vertex_count, 1, scene_quad_count, 0);
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
                    self.window_handle.request_frame_callback();

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

        pub fn recreateSwapchain(self: *Self) !void {
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
            self.swap_extent = self.window_handle.getVkExtent(self.surface_capabilities);
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

        pub fn deinit(self: *Self) void {
            defer self.allocator.destroy(self.window_handle);
            defer self.window_handle.deinit();
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
}
