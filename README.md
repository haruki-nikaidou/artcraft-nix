# artcraft-nix

Nix flake for the open-source [ArtCraft](https://getartcraft.com/apps) apps on NixOS and Home
Manager. ArtCraft's own launcher/installer is not used.

| App | Package (prebuilt) | Package (from source) |
| --- | --- | --- |
| [PhotoCraft](https://getartcraft.com/apps/photocraft): image editor | `photocraft` | `photocraft-source` |
| [VectorCraft](https://getartcraft.com/apps/vectorcraft): vector illustration | `vectorcraft` | `vectorcraft-source` |
| [FilmCraft](https://getartcraft.com/apps/filmcraft): video editor | `filmcraft` | `filmcraft-source` |
| [LightCraft](https://getartcraft.com/apps/lightcraft): photo library & raw developer | `lightcraft` | `lightcraft-source` |
| [PdfCraft](https://getartcraft.com/apps/pdfcraft): PDF workbench | `pdfcraft` | `pdfcraft-source` |
| [EffectCraft](https://getartcraft.com/apps/effectcraft): motion graphics & VFX | `effectcraft` | `effectcraft-source` |
| [DesignCraft](https://getartcraft.com/apps/designcraft): page layout & publishing | `designcraft` | `designcraft-source` |
| [SoundCraft](https://getartcraft.com/apps/soundcraft): digital audio workstation | `soundcraft` | `soundcraft-source` |

Each package installs the GUI (`<app>`) and the headless CLI/MCP server (`<app>-cli`), plus the
desktop entry, icons, MIME types and AppStream metadata, and man pages and shell completions
where upstream ships them. Systems: `x86_64-linux` and `aarch64-linux`.

## Variants

- **`<app>`** (prebuilt) downloads the official release AppImage from GitHub and unpacks it. It
  does not run through the AppImage runtime: the binaries are patched to use Nix store libraries,
  so you don't need FUSE, `appimage-run` or a sandbox. Downloads only, nothing to compile.
- **`<app>-source`** compiles the same release tag with Cargo and stages it with upstream's own
  `packaging/linux/package.sh`. It uses the same features, embedded
  [craft-fonts](https://github.com/storytold/craft-fonts) and installed files as the official
  packages. It compiles with the official Rust toolchain that nixpkgs ships as
  `rust.packages.prebuilt`, which has to be 1.95 or newer. The pinned nixos-unstable has 1.99.

Both variants put the libraries the apps `dlopen()` (Wayland/X11, Vulkan/EGL, D-Bus, ALSA, VA-API)
in the binaries' RUNPATH, and they find GPU drivers through `/run/opengl-driver`. On NixOS that
needs `hardware.graphics.enable = true;`, which desktop setups already enable.

## Usage

Add the flake as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    artcraft = {
      url = "github:haruki-nikaidou/artcraft-nix";
      inputs.nixpkgs.follows = "nixpkgs"; # optional; the source variant needs Rust >= 1.95
    };
  };
}
```

### NixOS module

```nix
{ inputs, ... }:
{
  imports = [ inputs.artcraft.nixosModules.default ];

  programs.artcraft = {
    enable = true;
    variant = "appimage"; # default for every app: "appimage" or "source"
    apps.photocraft.enable = true;
    apps.pdfcraft.enable = true;
    apps.soundcraft = {
      enable = true;
      variant = "source"; # per-app override
    };
  };
}
```

### Home Manager module

The options are the same, but the apps go into `home.packages`:

```nix
{ inputs, ... }:
{
  imports = [ inputs.artcraft.homeModules.default ];

  programs.artcraft = {
    enable = true;
    apps.vectorcraft.enable = true;
    apps.filmcraft.enable = true;
  };
}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `programs.artcraft.enable` | `false` | Install the apps enabled below. |
| `programs.artcraft.variant` | `"appimage"` | Default variant for every app. |
| `programs.artcraft.apps.<app>.enable` | `false` | Install this app. |
| `programs.artcraft.apps.<app>.variant` | `programs.artcraft.variant` | Variant for this app. |
| `programs.artcraft.apps.<app>.package` | from the variant | Package to install. Setting it overrides `variant`. |

`<app>` is one of `photocraft`, `vectorcraft`, `filmcraft`, `lightcraft`, `pdfcraft`,
`effectcraft`, `designcraft` or `soundcraft`.

### Plain package lists

```nix
# NixOS
environment.systemPackages = with inputs.artcraft.packages.${pkgs.stdenv.hostPlatform.system}; [
  photocraft
  lightcraft-source
];

# Home Manager
home.packages = [ inputs.artcraft.packages.${pkgs.stdenv.hostPlatform.system}.designcraft ];
```

You can also use the overlay, which builds against your own nixpkgs:

```nix
nixpkgs.overlays = [ inputs.artcraft.overlays.default ];
environment.systemPackages = [ pkgs.photocraft pkgs.effectcraft-source ];
```

### Try without installing

```sh
nix run github:haruki-nikaidou/artcraft-nix#photocraft
nix shell github:haruki-nikaidou/artcraft-nix#pdfcraft --command pdfcraft-cli --help
```

## Updating from upstream

All per-release data (tags, commits, AppImage URLs and hashes, source and Cargo vendor hashes, and
the craft-fonts/craft-i18n pins) lives in `nix/sources.json`. `scripts/update.py` writes it:

```sh
nix run .#update                 # every app whose latest GitHub release changed
nix run .#update -- soundcraft   # just some apps
nix run .#update -- --force      # re-pin even if the version didn't change
```

For each app with a new release, the script:

1. Reads `releases/latest` from the GitHub API.
2. Takes the AppImage hashes from the release asset digests.
3. Prefetches the source tarball.
4. Reads the release's craft-fonts pin from `.github/workflows/release.yml`, falling back to the
   suite default in `storytold/craft-common-actions`.
5. Reads the release's craft-i18n pin from `craft-i18n.rev`.
6. Reads the files the packaging downloads from `ATTRIBUTION.toml`. Currently that's PdfCraft's
   OCR models, which the offline build serves from the Nix store.
7. Builds `.#<app>-source.cargoDeps` to learn the Cargo vendor hash.

If one app fails, the script keeps that app's previous pin, still updates the others, and exits
with a non-zero status. Set `GITHUB_TOKEN` to avoid the API rate limit.

CI isn't set up yet. A scheduled workflow only needs to:

1. Install Nix.
2. Run `nix run .#update` with `GITHUB_TOKEN`.
3. Optionally run `nix flake check`, which builds every prebuilt package and so verifies the
   pinned AppImage hashes.
4. Commit or open a PR when `nix/sources.json` changes.

## Layout

```
flake.nix                 inputs and outputs only
nix/apps.nix              hand-written app metadata (names, titles, descriptions)
nix/sources.json          generated pins, written by scripts/update.py
pkgs/default.nix          package set: <app> and <app>-source for every app
pkgs/appimage.nix         prebuilt builder (unpacked AppImage, autoPatchelf)
pkgs/source.nix           source builder (Cargo + upstream package.sh)
pkgs/runtime-libs.nix     libraries the apps dlopen() at run time
pkgs/drop-unused-cargo-patches.py
                          makes upstream's unused [patch] entries vendorable offline
modules/artcraft.nix      programs.artcraft, shared by the NixOS and Home Manager modules
scripts/update.py         upstream updater (nix run .#update)
```

## License

The Nix code in this repository is released under [CC0 1.0](LICENSE). The ArtCraft apps are
dual-licensed by their authors under MIT and Apache-2.0.
