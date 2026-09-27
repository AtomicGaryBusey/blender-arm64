# Initial CMake cache for Blender 5.2.2 on NVIDIA DGX Spark (GB10), used with
#   cmake -C config/blender_gb10.cmake  (see scripts/container/blender.sh)
# Deliberately NOT based on build_files/cmake/config/blender_release.cmake, which FORCEs
# HIP/oneAPI/etc. ON. Milestone-2 features are switched by blender.sh (BLENDER_GB10_M2=1).

set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(WITH_LIBS_PRECOMPILED ON CACHE BOOL "")
set(LIBDIR /work/lib/linux_arm64 CACHE PATH "")      # harvested deps, outside the (pristine) source tree
set(WITH_INSTALL_PORTABLE ON CACHE BOOL "")
set(WITH_STRICT_BUILD_OPTIONS ON CACHE BOOL "")   # a missing library is a configure error, not a silently dropped feature
set(WITH_BUILDINFO ON CACHE BOOL "")

# --- Cycles / NVIDIA -------------------------------------------------------
set(WITH_CYCLES ON CACHE BOOL "")
set(WITH_CYCLES_DEBUG OFF CACHE BOOL "")          # upstream fork had this ON; never for a release build
set(WITH_CYCLES_DEVICE_CUDA ON CACHE BOOL "")
set(WITH_CYCLES_CUDA_BINARIES ON CACHE BOOL "")
set(CYCLES_CUDA_BINARIES_ARCH "sm_120" CACHE STRING "")  # SASS loaded on sm_121 via Cycles' minor-version fallback
set(WITH_CYCLES_DEVICE_OPTIX ON CACHE BOOL "")
set(OPTIX_ROOT_DIR /work/src/optix-dev CACHE PATH "")    # NVIDIA/optix-dev v9.0.0 headers
set(WITH_CUDA_DYNLOAD ON CACHE BOOL "")                  # libcuda is dlopen'ed from the host driver
set(WITH_CYCLES_DEVICE_HIP OFF CACHE BOOL "")
set(WITH_CYCLES_HIP_BINARIES OFF CACHE BOOL "")
set(WITH_CYCLES_DEVICE_HIPRT OFF CACHE BOOL "")
set(WITH_CYCLES_DEVICE_ONEAPI OFF CACHE BOOL "")
set(WITH_CYCLES_EMBREE ON CACHE BOOL "")
set(WITH_CYCLES_PATH_GUIDING ON CACHE BOOL "")
set(WITH_OPENIMAGEDENOISE ON CACHE BOOL "")
set(WITH_OPENVDB ON CACHE BOOL "")
set(WITH_OPENVDB_BLOSC ON CACHE BOOL "")
set(WITH_NANOVDB ON CACHE BOOL "")
set(WITH_CYCLES_OSL OFF CACHE BOOL "")
set(WITH_CYCLES_TEST_OSL OFF CACHE BOOL "")

# --- GPU backend / windowing -------------------------------------------------
set(WITH_VULKAN_BACKEND ON CACHE BOOL "")
set(WITH_BUNDLED_VULKAN_LOADER OFF CACHE BOOL "")  # patch 0008: use the host libvulkan.so.1 + NVIDIA ICD
set(WITH_OPENGL_BACKEND ON CACHE BOOL "")
set(WITH_GHOST_X11 ON CACHE BOOL "")
set(WITH_GHOST_WAYLAND ON CACHE BOOL "")
set(WITH_GHOST_WAYLAND_DYNLOAD ON CACHE BOOL "")
set(WITH_GHOST_WAYLAND_LIBDECOR ON CACHE BOOL "")
set(WITH_GHOST_SDL OFF CACHE BOOL "")
set(WITH_SDL OFF CACHE BOOL "")
set(WITH_INPUT_NDOF OFF CACHE BOOL "")
set(WITH_XR_OPENXR ON CACHE BOOL "")

# --- Python -----------------------------------------------------------------
set(WITH_PYTHON_INSTALL ON CACHE BOOL "")
set(WITH_PYTHON_INSTALL_NUMPY ON CACHE BOOL "")
set(WITH_PYTHON_INSTALL_ZSTANDARD ON CACHE BOOL "")
set(WITH_PYTHON_INSTALL_REQUESTS ON CACHE BOOL "")

# --- IO / media ---------------------------------------------------------------
set(WITH_CODEC_FFMPEG ON CACHE BOOL "")
set(WITH_CODEC_SNDFILE ON CACHE BOOL "")
set(WITH_AUDASPACE ON CACHE BOOL "")
set(WITH_OPENAL ON CACHE BOOL "")                 # libopenal is built by the deps builder and bundled
set(WITH_PULSEAUDIO ON CACHE BOOL "")
set(WITH_PULSEAUDIO_DYNLOAD ON CACHE BOOL "")
set(WITH_JACK ON CACHE BOOL "")
set(WITH_JACK_DYNLOAD ON CACHE BOOL "")
set(WITH_PIPEWIRE OFF CACHE BOOL "")        # needs libpipewire >= 1.1; Ubuntu 24.04 has 1.0.5 (host PipeWire serves Pulse clients)
set(WITH_PIPEWIRE_DYNLOAD OFF CACHE BOOL "")
set(WITH_IMAGE_OPENEXR ON CACHE BOOL "")
set(WITH_IMAGE_OPENJPEG ON CACHE BOOL "")
set(WITH_IMAGE_WEBP ON CACHE BOOL "")
set(WITH_IMAGE_CINEON ON CACHE BOOL "")
set(WITH_OPENCOLORIO ON CACHE BOOL "")
set(WITH_ALEMBIC ON CACHE BOOL "")
set(WITH_MATERIALX ON CACHE BOOL "")
set(WITH_USD OFF CACHE BOOL "")
set(WITH_HYDRA OFF CACHE BOOL "")
set(WITH_OPENSUBDIV ON CACHE BOOL "")
set(WITH_MANIFOLD ON CACHE BOOL "")
set(WITH_GMP ON CACHE BOOL "")
set(WITH_POTRACE ON CACHE BOOL "")
set(WITH_HARU ON CACHE BOOL "")
set(WITH_FFTW3 ON CACHE BOOL "")
set(WITH_RUBBERBAND ON CACHE BOOL "")
set(WITH_DRACO ON CACHE BOOL "")
set(WITH_MESHOPTIMIZER ON CACHE BOOL "")
set(WITH_HARFBUZZ ON CACHE BOOL "")
set(WITH_FRIBIDI ON CACHE BOOL "")
set(WITH_TBB_MALLOC_PROXY ON CACHE BOOL "")
set(WITH_TRACY OFF CACHE BOOL "")

# --- Build resource control (Blender autodetects from TOTAL RAM = 121 GB; only ~32 GB free) ---
set(WITH_NINJA_POOL_JOBS ON CACHE BOOL "")
set(NINJA_MAX_NUM_PARALLEL_COMPILE_JOBS 12 CACHE STRING "")
set(NINJA_MAX_NUM_PARALLEL_COMPILE_HEAVY_JOBS 3 CACHE STRING "")
set(NINJA_MAX_NUM_PARALLEL_LINK_JOBS 1 CACHE STRING "")
set(WITH_LINKER_MOLD OFF CACHE BOOL "")
