{
  pkgs,
  ...
}:
let
  # Same static overrides as default.nix for consistent builds
  wayland-static = pkgs.wayland.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Ddefault_library=both" ];
  });

  xkbcommon-static = pkgs.libxkbcommon.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Ddefault_library=both" ];
  });

  libffi-static = pkgs.libffi.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [ "--enable-static" ];
  });

  libxcb-static = pkgs.libxcb.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [ "--enable-static" ];
  });

  libxau-static = pkgs.libxau.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [ "--enable-static" ];
  });

  libxdmcp-static = pkgs.libxdmcp.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [ "--enable-static" ];
  });
in
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
    wayland-static
    pkgs.wayland-scanner
    pkgs.wayland-protocols
    xkbcommon-static.dev
    libffi-static
    libxcb-static.dev
    libxau-static.dev
    libxdmcp-static.dev
  ];

  shellHook = ''
    PS1="(dev) $PS1"
    LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}";
  '';
}
