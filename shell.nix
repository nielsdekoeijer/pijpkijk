{
  pkgs,
  ...
}:
pkgs.mkShell rec {
  nativeBuildInputs = [
    pkgs.zig
    pkgs.zls
    pkgs.bash
    pkgs.file
    pkgs.sdl3-image.dev
    pkgs.sdl3.dev
    pkgs.sdl3.lib
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.vulkan-validation-layers
    pkgs.msdf-atlas-gen
    pkgs.pipewire.dev
    pkgs.pkg-config
  ];

  shellHook = ''
    PS1="(dev) $PS1"
    LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}";
  '';
}
