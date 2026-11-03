{
  description = "ArtCraft apps (PhotoCraft, VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft, SoundCraft) for NixOS and Home Manager";

  inputs = {
    # The source builds need Rust >= 1.95 (edition 2024; nixpkgs' rust.packages.prebuilt), hence
    # unstable. Consumers can retarget it with `inputs.artcraft.inputs.nixpkgs.follows = "nixpkgs";`.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # Upstream publishes Linux AppImages for these two; the source builds target the same.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: import ./pkgs { inherit (pkgs) lib callPackage; });

      # Adds every package above to a nixpkgs instance of your choosing (pkgs.photocraft, …). The
      # attribute names come from prev's lib so the overlay never forces the fixed point.
      overlays.default =
        final: prev:
        import ./pkgs {
          inherit (prev) lib;
          inherit (final) callPackage;
        };

      nixosModules.default = import ./modules/artcraft.nix {
        inherit self;
        packagesOption = [
          "environment"
          "systemPackages"
        ];
      };

      homeModules.default = import ./modules/artcraft.nix {
        inherit self;
        packagesOption = [
          "home"
          "packages"
        ];
      };

      # `nix run .#update`: refresh nix/sources.json from the latest upstream releases.
      apps = forAllSystems (pkgs: {
        update = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "artcraft-update";
              runtimeInputs = [
                pkgs.python3
                pkgs.nix
                pkgs.git
              ];
              text = ''exec python3 ${./scripts/update.py} "$@"'';
            }
          );
          meta.description = "Update nix/sources.json to the latest ArtCraft releases";
        };
      });

      # The prebuilt packages: cheap to build, and they exercise every pinned AppImage hash.
      checks = forAllSystems (
        pkgs:
        lib.filterAttrs (
          name: _: !lib.hasSuffix "-source" name
        ) self.packages.${pkgs.stdenv.hostPlatform.system}
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
