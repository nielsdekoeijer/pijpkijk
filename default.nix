{
  pkgs,
  ...
}:
let
  # Build static (.a) versions of libraries for portable binary
  wayland-static = pkgs.wayland.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Ddefault_library=both" ];
  });

  xkbcommon-static = pkgs.libxkbcommon.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Ddefault_library=both" ];
  });

  libffi-static = pkgs.libffi.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [ "--enable-static" ];
  });
in
pkgs.stdenv.mkDerivation rec {
  pname = "pijpkijk";

  version = "0.1.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    pkgs.zig
    pkgs.pkg-config
    pkgs.msdf-atlas-gen
    pkgs.patchelf
    pkgs.wayland-scanner
  ];

  buildInputs = [
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.pipewire.dev
    wayland-static
    pkgs.wayland-protocols
    xkbcommon-static.dev
    libffi-static
    pkgs.libxcb.dev
    pkgs.libxcb-keysyms
  ];

  installPhase = ''
    runHook preInstall

    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR

    zig build -Doptimize=ReleaseSafe --prefix $out install

    runHook postInstall
  '';

  postFixup = ''
    patchelf \
      --set-interpreter /lib64/ld-linux-x86-64.so.2 \
      --set-rpath "/usr/lib/x86_64-linux-gnu:/usr/lib:/lib" \
      $out/bin/pijpkijk
  '';

  outputs = [ "out" ];
}
