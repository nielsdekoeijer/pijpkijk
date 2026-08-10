// Wayland backend C imports (with VK_USE_PLATFORM_WAYLAND_KHR)
pub const wl = @cImport({
    @cInclude("stb/stb_image.h");

    // Wayland
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-protocol.h");
    @cInclude("cursor-shape-v1-protocol.h");
    @cInclude("fractional-scale-v1-protocol.h");
    @cInclude("pointer-gestures-unstable-v1-protocol.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("xkbcommon/xkbcommon.h");

    // Import vulkan
    @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", "1");
    @cInclude("vulkan/vulkan.h");

    // Nasty hack: why is pipewire so fucking awful? Weird API
    @cDefine("_Static_assert(...)", {});
    @cInclude("pipewire-0.3/pipewire/pipewire.h");
    @cInclude("pipewire-0.3/pipewire/extensions/profiler.h");
    @cInclude("pipewire-0.3/pipewire/impl-module.h");
    @cInclude("spa-0.2/spa/param/profiler.h");
    @cInclude("spa-0.2/spa/pod/parser.h");
    @cInclude("spa-0.2/spa/pod/iter.h");
    @cInclude("spa-0.2/spa/param/latency-utils.h");
});

// X11 backend C imports (with VK_USE_PLATFORM_XCB_KHR)
pub const xcb = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xkb.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-x11.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");

    @cDefine("VK_USE_PLATFORM_XCB_KHR", "1");
    @cInclude("vulkan/vulkan.h");
});

// Legacy alias — most of the codebase uses `c` which is the wayland import
pub const c = wl;
