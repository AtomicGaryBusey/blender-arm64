#!/usr/bin/env bash
# Build Blender's third-party libraries with Blender's own deps builder
# (build_files/build_environment), exactly at the versions/hashes/patches pinned by
# Blender 5.2.2, harvesting into src/blender/lib/linux_arm64 (Blender's precompiled
# library layout for Linux aarch64). Runs inside the builder container as `builder`.
#
#   deps.sh configure        -- networked: configure + download every source tarball
#                               (hash-checked against versions.cmake, FORCE_CHECK_HASH=ON)
#   deps.sh build [waves]    -- offline (--network none): build the given waves (default:
#                               milestone 1 = w1..w7) one package at a time, pruning build
#                               trees after each wave, then harvest (cmake --install).
#   deps.sh harvest          -- only re-run the harvest step
set -euo pipefail
source /repo/scripts/pins.env

SRC=/work/src/blender
B=/work/build/deps
HARVEST="$SRC/lib/linux_arm64"
JOBS="${JOBS:-12}"
REQ="$B/site-packages-requirements.txt"

configure() {
  mkdir -p "$B" /work/packages/deps
  # pip requirements with hashes from the repo's lock file.
  awk '!/^#/ && NF==3 {print $1 " --hash=sha256:" $3}' /repo/deps/python-wheels.lock > "$REQ"
  cmake -S "$SRC/build_files/build_environment" -B "$B" -G "Unix Makefiles" \
    -DHARVEST_TARGET="$HARVEST" \
    -DPACKAGE_DIR=/work/packages/deps \
    -DDOWNLOAD_DIR="$B/downloads" \
    -DMAKE_THREADS="$JOBS" \
    -DBUILD_MODE=Release \
    -DFORCE_CHECK_HASH=ON \
    -DCUDAToolkit_ROOT=/usr/local/cuda-13.0 \
    -DOIDN_CUDA_SM_LIST="$OIDN_CUDA_SM_LIST" \
    -DPYTHON_SITE_PACKAGES_WHEELHOUSE=/work/packages/wheels \
    -DPYTHON_SITE_PACKAGES_REQUIREMENTS="$REQ"
}

# Waves (targets pull in their own dependencies). A later wave only needs the earlier
# waves' installed LIBDIR (build/deps/Release), never their source/build trees.
declare -A WAVE=(
  [w1]="external_python external_python_site_packages external_numpy external_zstandard"
  [w2]="external_tbb external_ispc external_embree external_openpgl external_openimagedenoise external_sse2neon"
  [w3]="external_openexr external_openimageio external_opencolorio external_webp external_openjpeg"
  [w4]="external_openvdb external_opensubdiv external_alembic external_materialx"
  [w5]="external_ffmpeg external_sndfile external_flac external_openal external_fftw3_double external_fftw3_float"
  [w6]="external_shaderc external_vulkan_loader external_vulkan_memory_allocator external_spirv_reflect external_wayland external_wayland_protocols external_xr_openxr_sdk"
  [w7]="external_epoxy external_freetype external_harfbuzz external_fribidi external_gmp external_potrace external_haru external_manifold external_eigen external_ceres external_draco external_meshoptimizer external_rubberband external_pugixml"
  [m2_llvm]="external_llvm"
  [m2]="external_osl external_usd"
)

# Delete source+build trees of every package that has finished installing into LIBDIR,
# keeping the ExternalProject stamps so make does not redo them.
prune_done() {
  local stamp name dir
  for stamp in "$B"/build/*/src/*-stamp/*-done; do
    [[ -e "$stamp" ]] || continue
    name="$(basename "$stamp" -done)"            # external_<pkg>
    dir="$(dirname "$(dirname "$stamp")")"       # build/<pkg>/src
    if [[ -d "$dir/$name" || -d "$dir/$name-build" ]]; then
      rm -rf "${dir:?}/$name" "${dir:?}/$name-build"
    fi
  done
  rm -rf "${B:?}/downloads"
  echo "[deps.sh] pruned; build/deps=$(du -sh "$B" | cut -f1), free=$(df -BG --output=avail /work | tail -1 | tr -d ' ')"
}

harvest() {
  cmake --install "$B"
  echo "[deps.sh] harvested to $HARVEST ($(du -sh "$HARVEST" | cut -f1))"
}

build() {
  [[ -f "$B/Makefile" ]] || { echo "run 'deps.sh configure' first" >&2; exit 1; }
  local waves=("$@") w
  [[ ${#waves[@]} -gt 0 ]] || waves=(w1 w2 w3 w4 w5 w6 w7)
  cd "$B"
  for w in "${waves[@]}"; do
    [[ -n "${WAVE[$w]:-}" ]] || { echo "unknown wave $w" >&2; exit 2; }
    echo "[deps.sh] === wave $w: ${WAVE[$w]} ($(date -u +%FT%TZ))"
    # One project at a time, each with $JOBS jobs (Blender's own wrapper).
    "$SRC/build_files/build_environment/linux/make_deps_wrapper.sh" -s -j"$JOBS" ${WAVE[$w]}
    prune_done
  done
  harvest
}

case "${1:-}" in
  configure) configure ;;
  build) shift; build "$@" ;;
  harvest) harvest ;;
  *) echo "usage: deps.sh configure|build [waves]|harvest" >&2; exit 2 ;;
esac
