{
  description = "pijpkijk";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    zig-flake.url = "github:mitchellh/zig-overlay";
    zls-flake = {
      url = "github:zigtools/zls?ref=0.16.0";
      inputs.nixpkgs.follows = "nixpkgs";
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
      zig-flake,
      zls-flake,
      msdf-atlas-gen,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        # packages for the given system
        # Note: shader-slang (slangc) comes from nixpkgs, which is pinned via
        # flake.lock. Updating slangc requires `nix flake update nixpkgs`.
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              zig = zig-flake.packages.${system}."0.16.0";
              zls = zls-flake.packages.${system}.default.overrideAttrs (old: {
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.zig ];
              });
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
      in
      rec {
        # on `nix build` — portable FHS binary
        packages.default = pkgs.callPackage ./default.nix {
          inherit pkgs;
        };

        # on `nix run` — run the portable binary on NixOS
        apps.default =
          let
            wrapper = pkgs.writeShellScript "pijpkijk-wrapper" ''
              export LD_LIBRARY_PATH="${pkgs.sdl3}/lib:${pkgs.vulkan-loader}/lib:${pkgs.pipewire}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              exec ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ${packages.default}/bin/pijpkijk "$@"
            '';
          in
          {
            type = "app";
            program = "${wrapper}";
          };

        # on `nix develop`
        devShells.default = pkgs.callPackage ./shell.nix {
          inherit pkgs;
        };
      }
    );
}
