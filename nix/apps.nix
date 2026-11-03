# Hand-maintained metadata for every packaged ArtCraft app. Everything that changes with an upstream
# release (versions, revisions, hashes) lives in ./sources.json, written by scripts/update.py.
#
# Every app follows the same upstream conventions, which the builders rely on:
#   * repository        github.com/storytold/<name>
#   * binaries          <name> (GUI) and <name>-cli (headless CLI / MCP server)
#   * AppStream id      ai.storyteller.<name> (desktop file, icons, metainfo)
#   * release assets    <name>-<version>-linux-{x86_64,aarch64}.AppImage
#   * packaging         packaging/linux/package.sh builds and stages the FHS tree
{
  photocraft = {
    title = "PhotoCraft";
    description = "Open-source image editor written from scratch in Rust";
  };
  vectorcraft = {
    title = "VectorCraft";
    description = "Open-source vector illustration tool written from scratch in Rust";
  };
  filmcraft = {
    title = "FilmCraft";
    description = "Open-source nonlinear video editor written from scratch in Rust";
  };
  lightcraft = {
    title = "LightCraft";
    description = "Open-source photo library and non-destructive raw developer written from scratch in Rust";
  };
  pdfcraft = {
    title = "PdfCraft";
    description = "Open-source PDF reader and editor written from scratch in Rust";
  };
  effectcraft = {
    title = "EffectCraft";
    description = "Open-source motion graphics and compositing tool written from scratch in Rust";
  };
  designcraft = {
    title = "DesignCraft";
    description = "Open-source page layout and publishing tool written from scratch in Rust";
  };
  soundcraft = {
    title = "SoundCraft";
    description = "Open-source digital audio workstation written from scratch in Rust";
  };
}
