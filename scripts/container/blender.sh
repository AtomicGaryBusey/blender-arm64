#!/usr/bin/env bash
# Configure, build and install Blender 5.2.2 (portable layout) inside the builder
# container, offline, as the unprivileged `builder` user.
#   BLENDER_GB10_M2=1  also enables milestone-2 features (OSL, USD/Hydra).
set -euo pipefail
source /repo/scripts/pins.env

SRC=/work/src/blender
LIBDIR=/work/lib/linux_arm64
B=/work/build/blender
OUT="/work/out/blender-${BLENDER_VERSION}"
JOBS="${JOBS:-12}"
CUDA_JOBS="${CUDA_JOBS:-2}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$BLENDER_COMMIT_EPOCH}"

[[ -d "$LIBDIR/python" ]] || { echo "deps not harvested yet ($LIBDIR)" >&2; exit 1; }
gcc --version | head -1 | grep -q ' 14\.' || { echo "gcc-14 required" >&2; exit 1; }
source_check="$(/repo/scripts/container/check_source.sh)"
echo "$source_check"

extra=()
if [[ "${BLENDER_GB10_M2:-0}" == 1 ]]; then
  extra+=(-DWITH_CYCLES_OSL=ON -DWITH_USD=ON -DWITH_HYDRA=ON)
fi

cmake -G Ninja -C /repo/config/blender_gb10.cmake -S "$SRC" -B "$B" \
  -DLIBDIR="$LIBDIR" \
  -DCMAKE_INSTALL_PREFIX="$OUT" \
  -DCYCLES_CUDA_BINARIES_ARCH="$CYCLES_CUDA_ARCH" \
  "${extra[@]}"

# GPU kernels first, with low parallelism (each nvcc/OptiX job can take 3-12 GB RAM).
ninja -C "$B" -j"$CUDA_JOBS" cycles_kernel_cuda cycles_kernel_optix
ninja -C "$B" -j"$JOBS"
rm -rf "$OUT"
ninja -C "$B" install

# Blender's `blender-launcher` wrapper script prepends to LD_LIBRARY_PATH/LD_PRELOAD with
# an empty trailing element when they are unset (=> libraries load from the current
# directory) and may preload a host libtbb. The portable binary needs neither: RUNPATH
# is $ORIGIN/lib. Remove it; ~/.local/bin/blender-gb10 points at `blender` directly.
rm -f "$OUT/blender-launcher"

# Precompile Python bytecode so the read-only installed tree never needs to write .pyc.
"$OUT/${BLENDER_VERSION%.*}/python/bin/python3.13" -m compileall -q -j "$JOBS" \
  "$OUT/${BLENDER_VERSION%.*}" >/dev/null || true

# Policy check: nothing that must come from the host may be bundled.
bad="$(find "$OUT" \( -name 'libvulkan.so*' -o -name 'libcuda.so*' -o -name 'libnvoptix*' \
        -o -name 'libGL.so*' -o -name 'libEGL.so*' -o -name 'libGLX*' -o -name 'libc.so*' \
        -o -name 'libstdc++.so*' -o -name 'libX11.so*' -o -name 'libwayland-client.so*' \
        -o -name 'blender-launcher' \) -print)"
if [[ -n "$bad" ]]; then
  echo "ERROR: host-only libraries found in the install tree:" >&2
  echo "$bad" >&2
  exit 1
fi

cp /etc/blender-gb10/dpkg-manifest.txt "$OUT/blender-gb10-build-image-dpkg.txt"
cat > "$OUT/blender-gb10-BUILDINFO.txt" <<INFO
blender-gb10 build record
blender_version=${BLENDER_VERSION}
blender_commit=${BLENDER_COMMIT}
source_check=${source_check}
repo_head=${BLENDER_GB10_REPO_HEAD:-unknown}
repo_uncommitted_files=${BLENDER_GB10_REPO_DIRTY:-unknown}
builder_image_id=${BLENDER_GB10_IMAGE_ID:-unknown}
base_image=${BASE_IMAGE}
optix_headers_commit=${OPTIX_COMMIT}
cycles_cuda_arch=${CYCLES_CUDA_ARCH}
milestone2=${BLENDER_GB10_M2:-0}
source_date_epoch=${SOURCE_DATE_EPOCH}
INFO
echo "[blender.sh] installed portable tree: $OUT ($(du -sh "$OUT" | cut -f1))"
