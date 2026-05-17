{
  pkgs,
  ...
}:
pkgs.mkShell rec {
  nativeBuildInputs = [
    pkgs.zig
    pkgs.zls
    pkgs.bash
    pkgs.pkg-config
    pkgs.file
    pkgs.sdl3.dev
    pkgs.sdl3.lib
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.vulkan-validation-layers
  ];

  shellHook = ''
    PS1="(dev) $PS1"
    LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}";
  '';
}
