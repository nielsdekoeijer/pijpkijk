pub const c = @cImport({
    @cInclude("stb/stb_image.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");

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
