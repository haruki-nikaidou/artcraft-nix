# `programs.artcraft`, shared by the NixOS module (installs into environment.systemPackages) and
# the Home Manager module (installs into home.packages); `packagesOption` is the only difference.
#
#   programs.artcraft = {
#     enable = true;
#     variant = "appimage";                          # or "source", for every app below
#     apps.photocraft.enable = true;
#     apps.soundcraft = { enable = true; variant = "source"; };
#   };
{ self, packagesOption }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.artcraft;
  apps = import ../nix/apps.nix;
  flakePackages = self.packages.${pkgs.stdenv.hostPlatform.system} or { };

  variantType = types.enum [
    "appimage"
    "source"
  ];

  appOptions =
    name: info:
    { config, ... }:
    {
      options = {
        enable = mkEnableOption info.title;

        variant = mkOption {
          type = variantType;
          default = cfg.variant;
          defaultText = literalExpression "config.programs.artcraft.variant";
          description = "How to obtain ${info.title}; see {option}`programs.artcraft.variant`.";
        };

        package = mkOption {
          type = types.package;
          default = flakePackages.${if config.variant == "source" then "${name}-source" else name};
          defaultText = literalExpression ''
            artcraft.packages.''${system}.${name}         # variant = "appimage"
            artcraft.packages.''${system}.${name}-source  # variant = "source"
          '';
          description = "The ${info.title} package to install. Overrides {option}`variant`.";
        };
      };
    };

  enabledApps = lib.filterAttrs (_: app: app.enable) cfg.apps;
in
{
  options.programs.artcraft = {
    enable = mkEnableOption "the ArtCraft applications selected in {option}`programs.artcraft.apps`";

    variant = mkOption {
      type = variantType;
      default = "appimage";
      description = ''
        Default way to obtain every app, overridable per app:

        - `"appimage"`: the official prebuilt release AppImage, unpacked and patched to run
          natively on NixOS (no FUSE or AppImage runtime). Downloads only.
        - `"source"`: the same release tag compiled from source with Cargo. Needs Rust ≥ 1.95
          (nixpkgs' `rust.packages.prebuilt`) and takes a long time to build.
      '';
    };

    apps = lib.mapAttrs (
      name: info:
      mkOption {
        type = types.submodule (appOptions name info);
        default = { };
        description = "${info.title}: ${info.description}.";
      }
    ) apps;
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      (lib.setAttrByPath packagesOption (lib.mapAttrsToList (_: app: app.package) enabledApps))
      {
        warnings = lib.optional (enabledApps == { }) ''
          programs.artcraft.enable is set, but no app is enabled: set
          programs.artcraft.apps.<name>.enable = true for any of ${lib.concatStringsSep ", " (lib.attrNames apps)}.
        '';
      }
    ]
  );
}
