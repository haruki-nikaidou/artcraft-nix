# Prebuilt variant: the official release AppImage from GitHub, unpacked rather than run through
# its runtime. The AppDir already holds the FHS tree upstream's package.sh staged (bin/ with the
# GUI and the CLI, share/ with the desktop entry, icons, MIME types, AppStream metadata and, for
# some apps, man pages, shell completions or data files), so it is copied as is and the binaries
# are patched to the Nix store's glibc and libraries. Nothing runs from the AppImage at run time:
# no FUSE, no bubblewrap sandbox, and the CLI is a plain executable next to the GUI.
{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  autoPatchelfHook,
  autoAddDriverRunpath,
  alsa-lib,
  app,
  runtimeLibs,
}:

let
  inherit (app) name source;
  system = stdenv.hostPlatform.system;
  asset =
    source.appimage.${system} or (throw "${name}: upstream publishes no AppImage for ${system}");

  appimage = fetchurl {
    inherit (asset) url hash;
  };
in
stdenv.mkDerivation {
  pname = name;
  inherit (source) version;

  src = appimageTools.extract {
    pname = name;
    inherit (source) version;
    src = appimage;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    autoAddDriverRunpath
  ];

  # Linked directly (DT_NEEDED): libgcc_s for every binary, libasound for the apps with audio.
  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib
  ];

  # dlopen()ed libraries: autoPatchelfHook appends <dep>/lib of each to every executable's
  # RUNPATH, so pass the outputs that hold the libraries (libva's default output is dev).
  runtimeDependencies = map lib.getLib runtimeLibs;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r usr/bin usr/share $out/

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
    inherit appimage;
    variant = "appimage";
  };

  meta = app.meta // {
    description = "${app.description} (official prebuilt release)";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames source.appimage;
  };
}
