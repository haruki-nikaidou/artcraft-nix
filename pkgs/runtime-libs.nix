# Libraries the apps open at run time with dlopen(), so nothing in their ELF headers names them:
# winit loads libwayland-client, libxkbcommon and the X11 libraries, wgpu the Vulkan loader or
# libEGL/libGL, rfd libdbus-1 (xdg-desktop-portal file dialogs) and FilmCraft libva (hardware video
# decoding). Both builders add them to the binaries' RUNPATH; the GPU drivers themselves come from
# /run/opengl-driver (autoAddDriverRunpath).
{
  alsa-lib,
  dbus,
  libglvnd,
  libva,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  vulkan-loader,
  wayland,
}:

[
  alsa-lib
  dbus
  libglvnd
  libva
  libx11
  libxcb
  libxcursor
  libxi
  libxkbcommon
  libxrandr
  libxrender
  vulkan-loader
  wayland
]
