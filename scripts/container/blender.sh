#!/usr/bin/env bash
# Configure, build and install Blender 5.2.2 (portable layout) inside the builder
# container, offline, as the unprivileged `builder` user.
#   BLENDER_GB10_M2=1  also enables milestone-2 features (OSL, USD/Hydra).
set -euo pipefail
source /repo/scripts/pins.env

SRC=/work/src/blender
B=/work/build/blender
OUT="/work/out/blender-${BLENDER_VERSION}"
JOBS="${JOBS:-12}"
CUDA_JOBS="${CUDA_JOBS:-2}"

[[ -d "$SRC/lib/linux_arm64/python" ]] || { echo "deps not harvested yet ($SRC/lib/linux_arm64)" >&2; exit 1; }
gcc --version | head -1 | grep -q ' 14\.' || { echo "gcc-14 required" >&2; exit 1; }

# Reproducible build date: the pinned Blender commit's timestamp.
SOURCE_DATE_EPOCH="$(git -C "$SRC" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH

extra=()
if [[ "${BLENDER_GB10_M2:-0}" == 1 ]]; then
  extra+=(-DWITH_CYCLES_OSL=ON -DWITH_USD=ON -DWITH_HYDRA=ON)
fi

cmake -G Ninja -C /repo/config/blender_gb10.cmake -S "$SRC" -B "$B" \
  -DCMAKE_INSTALL_PREFIX="$OUT" \
  -DCYCLES_CUDA_BINARIES_ARCH="$CYCLES_CUDA_ARCH" \
  "${extra[@]}"

# GPU kernels first, with low parallelism (each nvcc/OptiX job can take 3-12 GB RAM).
ninja -C "$B" -j"$CUDA_JOBS" cycles_kernel_cuda cycles_kernel_optix
ninja -C "$B" -j"$JOBS"
rm -rf "$OUT"
ninja -C "$B" install

# Policy check: nothing that must come from the host may be bundled.
bad="$(find "$OUT" \( -name 'libvulkan.so*' -o -name 'libcuda.so*' -o -name 'libnvoptix*' \
        -o -name 'libGL.so*' -o -name 'libEGL.so*' -o -name 'libGLX*' -o -name 'libc.so*' \
        -o -name 'libstdc++.so*' -o -name 'libX11.so*' -o -name 'libwayland-client.so*' \) -print)"
if [[ -n "$bad" ]]; then
  echo "ERROR: host-only libraries found in the install tree:" >&2
  echo "$bad" >&2
  exit 1
fi
cp /etc/blender-gb10/dpkg-manifest.txt "$OUT/blender-gb10-build-image-dpkg.txt"
echo "[blender.sh] installed portable tree: $OUT ($(du -sh "$OUT" | cut -f1))"
