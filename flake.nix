{
  description = "pijpkijk";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "utils";
    };

    msdf-atlas-gen = {
      url = "git+https://github.com/Chlumsky/msdf-atlas-gen?submodules=1";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      zig2nix,
      msdf-atlas-gen,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        zig-env = zig2nix.outputs.zig-env.${system} {
          inherit nixpkgs;
          zig = zig2nix.outputs.packages.${system}.zig-0_16_0;
        };

        # packages for the given system
        # Note: shader-slang (slangc) comes from nixpkgs, which is pinned via
        # flake.lock. Updating slangc requires `nix flake update nixpkgs`.
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              inherit (zig-env) zig zls;
              msdf-atlas-gen = prev.stdenv.mkDerivation {
                pname = "msdf-atlas-gen";
                version = "git";

                src = msdf-atlas-gen;

                nativeBuildInputs = [ prev.cmake ];
                buildInputs = [
                  prev.freetype
                  prev.libpng
                ];

                cmakeFlags = [
                  "-DMSDF_ATLAS_USE_VCPKG=OFF"
                  "-DMSDF_ATLAS_USE_SKIA=OFF"
                ];

                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/bin
                  cp bin/msdf-atlas-gen $out/bin/
                  runHook postInstall
                '';
              };
            })
          ];
        };

        zig-package = pkgs.callPackage (pkgs.callPackage "${zig2nix}/src/package.nix" {
          inherit (zig-env) zig target fromZON;
          deriveLockFile = _: attrs: pkgs.callPackage ./build.zig.zon.nix attrs;
        });
      in
      rec {
        # on `nix build` — Nix-native package
        packages.default = pkgs.callPackage ./default.nix {
          inherit pkgs;
          inherit zig-package;
        };

        # GitHub release artifact for non-Nix Linux systems.
        packages.release = pkgs.callPackage ./release.nix {
          inherit pkgs;
          inherit zig-package;
        };

        apps.default = {
          type = "app";
          program = pkgs.lib.getExe packages.default;
        };

        # on `nix develop`
        devShells.default = pkgs.callPackage ./shell.nix {
          inherit pkgs;
        };
      }
    );
}
