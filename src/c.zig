pub const c = @cImport({
    @cInclude("stb/stb_image.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");

    // Nasty hack: why is pipewire so fucking awful? Weird API
    @cDefine("_Static_assert(...)", {});
    @cInclude("pipewire/pipewire.h");
    @cInclude("pipewire/extensions/profiler.h");
    @cInclude("pipewire/impl-module.h");
    @cInclude("spa/param/profiler.h");
    @cInclude("spa/pod/parser.h");
    @cInclude("spa/pod/iter.h");
    @cInclude("spa/param/latency-utils.h");
});
