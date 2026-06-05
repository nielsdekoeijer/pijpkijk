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
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.vulkan-validation-layers
    pkgs.msdf-atlas-gen
    pkgs.pipewire.dev
    pkgs.pkg-config
    # future
    pkgs.wayland
    pkgs.wayland-scanner
    pkgs.wayland-protocols
    pkgs.libxkbcommon.dev
  ];

  shellHook = ''
    PS1="(dev) $PS1"
    LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}";
  '';
}
