# The ArtCraft package set for one nixpkgs instance: for every app in nix/apps.nix,
#   <name>         the official prebuilt release AppImage, unpacked and patched for NixOS
#   <name>-source  the same release tag compiled from source with Cargo
{ lib, callPackage }:

let
  apps = import ../nix/apps.nix;
  sources = lib.importJSON ../nix/sources.json;

  runtimeLibs = callPackage ./runtime-libs.nix { };

  mkApp =
    name: info:
    let
      app = info // {
        inherit name;
        appId = "ai.storyteller.${name}";
        source = sources.apps.${name};
        meta = {
          inherit (info) description;
          homepage = "https://getartcraft.com/apps/${name}";
          changelog = "https://github.com/storytold/${name}/releases/tag/${sources.apps.${name}.tag}";
          license = with lib.licenses; [
            asl20
            mit
          ];
          platforms = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          mainProgram = name;
        };
      };
    in
    {
      ${name} = callPackage ./appimage.nix { inherit app runtimeLibs; };
      "${name}-source" = callPackage ./source.nix { inherit app runtimeLibs; };
    };
in
lib.concatMapAttrs mkApp apps
