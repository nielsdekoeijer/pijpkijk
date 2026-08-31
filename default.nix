{
  pkgs,
  zig-package,
  ...
}:
zig-package {
  pname = "pijpkijk";

  version = "0.11.1";

  src = ./.;

  zigBuildFlags = [
    "-Doptimize=ReleaseSafe"
    "-Dssh-path=${pkgs.lib.getExe pkgs.openssh}"
  ];

  nativeBuildInputs = [
    pkgs.msdf-atlas-gen
    pkgs.patchelf
  ];

  buildInputs = [
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.pipewire.dev
  ];

  postFixup = ''
    patchelf \
      --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} \
      --set-rpath "${pkgs.lib.makeLibraryPath [
        pkgs.alsa-lib
        pkgs.libdecor
        pkgs.libusb1
        pkgs.libxkbcommon
        pkgs.vulkan-loader
        pkgs.wayland
        pkgs.libx11
        pkgs.libxext
        pkgs.libxi
        pkgs.udev
        pkgs.pipewire
      ]}" \
      --output $out/bin/pijpkijk-patched \
      $out/bin/pijpkijk
    mv $out/bin/pijpkijk-patched $out/bin/pijpkijk
  '';
}
