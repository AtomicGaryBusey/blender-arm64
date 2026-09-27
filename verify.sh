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
mkdir -p "$E"
unset LD_LIBRARY_PATH
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
for k in version portable devices cycles vulkan; do
  printf '%-9s %s\n' "$k" "${RESULT[$k]:-NOT RUN}"
  [[ "${RESULT[$k]:-}" == PASS ]] || fail=1
done | tee "$E/summary.txt"
grep -q -v PASS "$E/summary.txt" && fail=1
echo "evidence: $E"
exit $fail
