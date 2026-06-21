pub const c = @cImport({
    // For loading images
    @cInclude("stb/stb_image.h");

    // Wayland
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-protocol.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("xkbcommon/xkbcommon.h");

    // Import vulkan 
    @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", "1");
    @cInclude("vulkan/vulkan.h");

    // Nasty hack: why is pipewire so fucking awful? Weird API
    @cDefine("_Static_assert(...)", {});
    @cInclude("pipewire-0.3/pipewire/pipewire.h");
});
