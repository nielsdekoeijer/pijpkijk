{
  pkgs,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.zig
    pkgs.zls
    pkgs.bash
    pkgs.pkg-config
    pkgs.file
    pkgs.sdl3.dev
    pkgs.sdl3.lib
    pkgs.directx-shader-compiler
  ];

  shellHook = ''
    PS1="(dev) $PS1"
  '';
}
