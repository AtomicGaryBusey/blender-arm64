# Sourced by bundle_portable.sh and check_portable.sh.
# SONAMEs that MUST come from the host (never copied into <tree>/lib).
# Basis: Blender 5.2.2 tools/check_blender_release/check_static_binaries.py ALLOWED_LIBS
# (glibc family, libstdc++/libgcc_s, X11 set, libdrm, libGL/libGLU/libOpenGL/libGLX, libxcb,
# libcrypt, libuuid, and libncursesw/libpanelw/libtinfo for Python's _curses) + GPU-driver-coupled libs (NVIDIA userspace must match the kernel driver)
# + display/audio client libs whose plugins/protocols are tied to the host daemons.
HOST_ALLOW_RE='^('\
'ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libmvec\.so\.1|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libutil\.so\.1|libresolv\.so\.2|libanl\.so\.1|'\
'libstdc\+\+\.so\.6|libgcc_s\.so\.1|libatomic\.so\.1|libgomp\.so\.1|'\
'libGL\.so\.1|libGLX\.so\.0|libEGL\.so\.1|libOpenGL\.so\.0|libGLdispatch\.so\.0|libGLESv2\.so\.2|libGLU\.so\.1|libgbm\.so\.1|libdrm\.so\.2|libglapi\.so\.0|'\
'libvulkan\.so\.1|'\
'libcuda\.so\.1|libnvoptix\.so\.1|libnvidia-[A-Za-z0-9_.-]+|libnvcuvid\.so\.1|libGLX_nvidia\.so\.0|libEGL_nvidia\.so\.0|'\
'libX11\.so\.6|libX11-xcb\.so\.1|libXext\.so\.6|libXrender\.so\.1|libXxf86vm\.so\.1|libXi\.so\.6|libXfixes\.so\.3|libXrandr\.so\.2|libXcursor\.so\.1|libXinerama\.so\.1|libXau\.so\.6|libXdmcp\.so\.6|libICE\.so\.6|libSM\.so\.6|libXt\.so\.6|'\
'libxcb[A-Za-z0-9_-]*\.so\.[0-9]+|libxkbcommon\.so\.0|libxkbcommon-x11\.so\.0|libwayland-(client|cursor|egl)\.so\.[01]|libdecor-0\.so\.0|'\
'libasound\.so\.2|libpulse\.so\.0|libpulse-simple\.so\.0|libjack\.so\.0|libpipewire-0\.3\.so\.0|'\
'libcrypt\.so\.1|libuuid\.so\.1|libz\.so\.1|'\
'libncursesw\.so\.6|libpanelw\.so\.6|libtinfo\.so\.6'\
')$'
# Directories a host-provided library may legitimately resolve to.
HOST_SYS_DIR_RE='^/(usr/)?lib(/aarch64-linux-gnu)?(/[^/]+)*$'
# Prefixes that are container/build-only (or host paths that would MASK a missing bundled lib,
# e.g. host /usr/local/cuda providing libcudart/libnvrtc). Any hit is a failure.
FORBIDDEN_PREFIX_RE='^/(usr/local|opt|home|root|build|src|work|tmp|var)/'
