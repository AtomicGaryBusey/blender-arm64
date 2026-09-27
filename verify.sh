#!/usr/bin/env bash
# verify.sh [tree] [evidence-dir]
# Host-side acceptance tests for the installed portable Blender tree. Runs on the host
# (not in Docker), without LD_LIBRARY_PATH, and writes all logs/images to the evidence dir.
#
#   1. version    `blender --version` reports 5.2.2 (via the ~/.local/bin/blender-gb10 launcher)
#   2. portable   verify/check_portable.sh: $ORIGIN RPATHs, clean-env ldd, no deps resolving to
#                 /usr/local,/opt,/home..., nothing host-only bundled, LD_DEBUG runtime trace,
#                 libcuda/libnvoptix from the host driver
#   3. devices    Cycles lists NVIDIA GB10 for CUDA and OPTIX (and reports OIDN capability)
#   4. cycles     renders on CPU, CUDA, OptiX, OIDN-GPU (CUDA+OptiX), OptiX denoiser, with the
#                 Cycles log line naming the GPU and the PID seen by nvidia-smi
#   5. vulkan     --gpu-backend vulkan: backend VULKAN on NVIDIA GB10 (background with and without
#                 display, GUI window on the host display) + EEVEE render under Vulkan
# Exit status is non-zero if any section fails.
set -uo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO/scripts/pins.env"
T="$(realpath "${1:-$HOME/.local/opt/blender-gb10-${BLENDER_VERSION}}")"
E="$(realpath -m "${2:-$REPO/_work/evidence/$(date -u +%Y%m%dT%H%M%SZ)}")"
LAUNCHER="${BLENDER_GB10_LAUNCHER:-$HOME/.local/bin/blender-gb10}"
V="$REPO/verify"
mkdir -p "$E/tmp"
unset LD_LIBRARY_PATH
# Keep every file Blender, the driver or we write inside the evidence directory:
# temp files, Blender user config/scripts/datafiles, CUDA/OptiX/GL shader caches.
export TMPDIR="$E/tmp"
export BLENDER_USER_CONFIG="$E/home/config" BLENDER_USER_SCRIPTS="$E/home/scripts" \
       BLENDER_USER_DATAFILES="$E/home/datafiles" BLENDER_USER_EXTENSIONS="$E/home/extensions" \
       BLENDER_USER_RESOURCES="$E/home/resources"
export CUDA_CACHE_PATH="$E/home/nv-cuda-cache" OPTIX_CACHE_PATH="$E/home/nv-optix-cache" \
       __GL_SHADER_DISK_CACHE_PATH="$E/home/nv-gl-cache" XDG_CACHE_HOME="$E/home/cache"
mkdir -p "$E/home"
# The GUI/Vulkan-on-display proofs need the host session; default to the local one.
if [[ -z "${DISPLAY:-}" && -S /tmp/.X11-unix/X0 ]]; then export DISPLAY=:0; fi
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then export XDG_RUNTIME_DIR="/run/user/$(id -u)"; fi
if [[ -z "${WAYLAND_DISPLAY:-}" && -S "${XDG_RUNTIME_DIR:-/nonexistent}/wayland-0" ]]; then export WAYLAND_DISPLAY=wayland-0; fi
declare -A RESULT
section() { echo; echo "=== $1 ==="; }
record() { RESULT[$1]=$2; echo "[$1] $2"; }

section "1. version"
{
  echo "tree: $T"; echo "launcher: $LAUNCHER -> $(readlink -f "$LAUNCHER" 2>/dev/null)"
  "$LAUNCHER" --version
} 2>&1 | tee "$E/1_version.log"
if grep -q "^Blender ${BLENDER_VERSION}" "$E/1_version.log"; then record version PASS; else record version FAIL; fi

section "2. portable (ldd / rpath / runtime loader trace)"
bash "$V/check_portable.sh" "$T" "$V/probe_cycles_devices.py" 2>&1 | tee "$E/2_portable.log"
if tail -1 "$E/2_portable.log" | grep -q 'PORTABLE-CHECK: PASS'; then record portable PASS; else record portable FAIL; fi
# Also keep a plain ldd of the binary for the record.
env -i PATH=/usr/bin:/bin ldd "$T/blender" > "$E/2_ldd_blender.txt" 2>&1

section "2b. hardening (build record, read-only tree, no library injection from CWD)"
{
  echo "--- build record"; cat "$T/blender-gb10-BUILDINFO.txt" 2>&1
  ok=1
  grep -q '^repo_uncommitted_files=0$' "$T/blender-gb10-BUILDINFO.txt" 2>/dev/null || { echo "FAIL: build record missing or built from a dirty checkout"; ok=0; }
  grep -q '^source_check=SOURCE-CHECK: OK' "$T/blender-gb10-BUILDINFO.txt" 2>/dev/null || { echo "FAIL: no source check in the build record"; ok=0; }
  w=$(find "$T" ! -type l -perm /222 | head -5)
  if [[ -n "$w" ]]; then echo "FAIL: writable files in the installed tree:"; echo "$w"; ok=0; else echo "PASS: installed tree is read-only"; fi
  bash "$V/cwd_injection.sh" "$T" "$LAUNCHER" "$E/2b_cwdinj" || ok=0
  [[ $ok == 1 ]] && echo "HARDENING: PASS" || echo "HARDENING: FAIL"
} 2>&1 | tee "$E/2b_hardening.log"
if grep -q 'HARDENING: PASS' "$E/2b_hardening.log"; then record hardening PASS; else record hardening FAIL; fi

section "3. Cycles device enumeration"
"$T/blender" -b --factory-startup --python-exit-code 3 --python "$V/probe_cycles_devices.py" \
  -- --need CUDA,OPTIX --name GB10 2>&1 | tee "$E/3_devices.log"
rc=${PIPESTATUS[0]}
if [[ $rc -eq 0 ]]; then record devices PASS; else record devices FAIL; fi

section "4. Cycles renders (CUDA, OptiX, OIDN GPU)"
bash "$V/run_cycles_proof.sh" "$T" "$E/4_cycles" 2>&1 | tee "$E/4_cycles.log"
rc=${PIPESTATUS[0]}
if [[ $rc -eq 0 ]]; then record cycles PASS; else record cycles FAIL; fi

section "5. Vulkan backend"
bash "$V/run_vulkan_proof.sh" "$T" "$E/5_vulkan" 2>&1 | tee "$E/5_vulkan.log"
rc=${PIPESTATUS[0]}
if [[ $rc -eq 0 ]]; then record vulkan PASS; else record vulkan FAIL; fi

section "summary"
fail=0
for k in version portable hardening devices cycles vulkan; do
  printf '%-9s %s\n' "$k" "${RESULT[$k]:-NOT RUN}"
  [[ "${RESULT[$k]:-}" == PASS ]] || fail=1
done | tee "$E/summary.txt"
grep -q -v PASS "$E/summary.txt" && fail=1
echo "evidence: $E"
exit $fail
