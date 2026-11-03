# Source variant: the release tag compiled with Cargo, packaged by upstream's own
# packaging/linux/package.sh so the result matches the official Linux packages file for file
# (same cargo invocation and features, same staged desktop entry, icons, metainfo, man pages,
# completions and data files). The script runs with every format switched off; only its staged
# FHS tree is installed.
#
# Inputs mirror the release workflow (storytold/craft-common-actions release.yml):
#   * the official stable Rust toolchain (rust.packages.prebuilt: rust-lang.org binaries with their
#     bundled LLVM, as rustup installs in CI). nixpkgs' own rustc links a system LLVM that can lag
#     behind the one its stdarch expects (rustc 1.99 on LLVM 21 rejects the AVX-512 VNNI intrinsics
#     PdfCraft's OCR engine uses);
#   * CRAFT_FONTS_DIR   storytold/craft-fonts at the revision the release used (CJK and other
#                       non-Latin fonts embedded into the binaries);
#   * CRAFT_I18N_DIR    storytold/craft-i18n, for apps that pin one in craft-i18n.rev;
#   * prefetched files  anything the packaging downloads with curl (PdfCraft's OCR models), served
#                       from the Nix store by an offline `curl` stand-in.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  writeShellScriptBin,
  rustPlatform,
  rust,
  pkg-config,
  python3,
  wayland-scanner,
  autoPatchelfHook,
  autoAddDriverRunpath,
  app,
  runtimeLibs,
}:

let
  inherit (app) name source;
  inherit (source) version;
  inherit (rust.packages.prebuilt) cargo rustc;
  envPrefix = lib.toUpper name;

  fetchStorytold =
    repo: pin:
    fetchFromGitHub {
      owner = "storytold";
      inherit repo;
      inherit (pin) rev hash;
    };

  src = fetchStorytold name source.src;
  craftFonts =
    if source.craftFonts != null then fetchStorytold "craft-fonts" source.craftFonts else null;
  craftI18n = if source.craftI18n != null then fetchStorytold "craft-i18n" source.craftI18n else null;

  prefetched = map (file: file // { path = fetchurl { inherit (file) url hash; }; }) source.fetched;

  # Answers `curl [options] -o FILE URL` from the Nix store; the build has no network.
  offlineCurl = writeShellScriptBin "curl" ''
    out= url=
    while [ $# -gt 0 ]; do
      case "$1" in
        -o | --output) out=$2; shift 2 ;;
        --retry | --retry-delay | --retry-max-time | --max-time | --connect-timeout | --proto | \
          -H | --header | -A | --user-agent | -w | --write-out) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    case "$url" in
    ${lib.concatMapStrings (
      file: "  ${lib.escapeShellArg file.url}) from=${file.path} ;;\n"
    ) prefetched}
      *) echo "curl: $url is not prefetched (offline Nix build); add it to nix/sources.json" >&2; exit 22 ;;
    esac
    if [ -n "$out" ]; then install -m644 "$from" "$out"; else cat "$from"; fi
  '';
in
stdenv.mkDerivation {
  pname = "${name}-source";
  inherit version;

  inherit src;

  cargoDeps = rustPlatform.fetchCargoVendor {
    name = "${name}-${version}-vendor";
    inherit src;
    hash = source.cargoHash;
  };

  strictDeps = true;

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    pkg-config
    wayland-scanner
    python3
    autoPatchelfHook
    autoAddDriverRunpath
  ]
  ++ lib.optional (prefetched != [ ]) offlineCurl;

  # pkg-config finds ALSA and the windowing libraries for the -sys crates that link them;
  # autoPatchelfHook rewrites the RUNPATH and needs libgcc_s from here too.
  buildInputs = runtimeLibs ++ [ stdenv.cc.cc.lib ];

  # dlopen()ed libraries: autoPatchelfHook appends <dep>/lib of each to every executable's
  # RUNPATH, so pass the outputs that hold the libraries (libva's default output is dev).
  runtimeDependencies = map lib.getLib runtimeLibs;

  env = {
    "${envPrefix}_BUILD_DATE" = source.date;
    "${envPrefix}_BUILD_SHA" = source.src.rev;
  }
  // lib.optionalAttrs (craftFonts != null) {
    CRAFT_FONTS_DIR = toString craftFonts;
    CRAFT_FONTS_REQUIRED = "1";
  }
  // lib.optionalAttrs (craftI18n != null) {
    CRAFT_I18N_DIR = toString craftI18n;
    CRAFT_I18N_REQUIRED = "1";
  };

  postPatch = ''
    patchShebangs packaging
  '';

  # After patchPhase: cargoSetupHook's post-patch check compares the pristine Cargo.lock with the
  # vendored copy, and this rewrites it.
  preBuild = ''
    python3 ${./drop-unused-cargo-patches.py}
  '';

  buildPhase = ''
    runHook preBuild

    export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
    packaging/linux/package.sh --formats none

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r target/linux-package/root/usr/. $out/

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/${name}-cli --version
    test -f $out/share/applications/${app.appId}.desktop

    runHook postInstallCheck
  '';

  passthru = {
    inherit craftFonts craftI18n;
    variant = "source";
  };

  meta = app.meta // {
    description = "${app.description} (built from source)";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
}
