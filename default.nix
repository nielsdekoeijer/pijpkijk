{
  pkgs,
  ...
}:
pkgs.stdenv.mkDerivation rec {
  pname = "pijpkijk";

  version = "0.8.1";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    pkgs.zig
    pkgs.pkg-config
    pkgs.msdf-atlas-gen
    pkgs.patchelf
  ];

  buildInputs = [
    pkgs.shader-slang
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.pipewire.dev
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
