{
  pkgs,
  ...
}:
let
in
pkgs.stdenv.mkDerivation rec {
  pname = "pijpkijk";

  version = "0.1.0";

  src = ./.;

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR
  '';

  nativeBuildInputs = [
    pkgs.zig
    pkgs.pkg-config
  ];

  buildInputs = [
    pkgs.sdl3.dev
    pkgs.sdl3.lib
  ];

  installPhase = ''
    runHook preInstall

    zig build -Doptimize=ReleaseSafe --prefix $out install

    runHook postInstall
  '';

  outputs = [ "out" ];
}
