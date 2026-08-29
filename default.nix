{
  pkgs,
  zig-package,
  ...
}:
zig-package {
  pname = "pijpkijk";

  version = "0.9.1";

  src = ./.;

  zigTarget = "x86_64-linux-gnu.2.35";

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
      --set-interpreter /lib64/ld-linux-x86-64.so.2 \
      --set-rpath "/usr/lib/x86_64-linux-gnu:/usr/lib:/lib" \
      --output $out/bin/pijpkijk-patched \
      $out/bin/pijpkijk
    mv $out/bin/pijpkijk-patched $out/bin/pijpkijk
  '';
}
