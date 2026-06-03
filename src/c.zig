/// Import SDL C-bindings
pub const c = @cImport({
    // Import vulkan first
    @cInclude("vulkan/vulkan.h");

    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("SDL3_image/SDL_image.h");
});

/// Seperate now because imports are cooked for some reason
pub const pw = @cImport({
    // Nasty hack: why is pipewire so fucking awful?
    @cDefine("_Static_assert(...)", {});
    @cInclude("pipewire-0.3/pipewire/pipewire.h");
});
