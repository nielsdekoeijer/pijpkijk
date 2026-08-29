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
    pkgs.alsa-lib
    pkgs.libdecor
    pkgs.libusb1
    pkgs.libxkbcommon
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.vulkan-validation-layers
    pkgs.wayland
    pkgs.libx11
    pkgs.libxext
    pkgs.libxi
    pkgs.udev
    pkgs.msdf-atlas-gen
    pkgs.pipewire.dev
    pkgs.pkg-config
  ];

  shellHook = ''
    PS1="(dev) $PS1"
    LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}";
  '';
}
