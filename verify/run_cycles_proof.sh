#!/usr/bin/env bash
# run_cycles_proof.sh <tree> <outdir>
# Matrix: CPU baseline, CUDA, OPTIX, OPTIX+OIDN_GPU, CUDA+OIDN_GPU, OPTIX+OPTIX-denoiser.
# Evidence per case (all must hold for PASS):
#  E1 Cycles INFO log "Path tracing on: NVIDIA GB10 (<CUDA|OptiX>) [...]" (integrator/path_trace.cpp full_report)
#  E2 for denoise cases: "Denoising on: NVIDIA GB10 ..." (CPU fallback would print the CPU device)
#  E3 blender PID seen by `nvidia-smi --query-compute-apps` while rendering (per-PID, not the shared
#     utilization.gpu -- ollama/kokoro also use this GPU)
#  E4 PNG written, mean_rgb > 0.01; GPU render_seconds reported next to the CPU baseline.
set -uo pipefail
T=$(realpath "$1"); O=$(realpath -m "$2"); mkdir -p "$O"
here=$(cd "$(dirname "$0")" && pwd)
fail=0
run() { # name device denoise extra...
  local name=$1 dev=$2 den=$3; shift 3
  local log="$O/$name.log" smi="$O/$name.smi"
  : >"$smi"
  "$T/blender" -b --factory-startup --log-level info --log cycles --python-exit-code 3 \
     --python "$here/render_cycles_gpu.py" -- --device "$dev" --denoise "$den" \
     --out "$O/$name.png" --cycles-print-stats "$@" >"$log" 2>&1 &
  local pid=$!
  while kill -0 $pid 2>/dev/null; do
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null \
      | grep -E "^ *$pid," >>"$smi"
    sleep 0.5
  done
  wait $pid; local rc=$?
  local pt dn
  pt=$(grep -A1 -m1 'Path tracing on:' "$log" | tr -s ' ' | head -2 | tr '\n' ' ')
  dn=$(grep -m1 'Denoising on:' "$log" | tr -s ' ')
  local secs; secs=$(sed -n 's/.*render_seconds=\([0-9.]*\).*/\1/p' "$log")
  local ok=1
  [ $rc -eq 0 ] || ok=0
  case $dev in
    CUDA)  grep -q 'Path tracing on: NVIDIA GB10 (CUDA)'  "$log" || ok=0; [ -s "$smi" ] || ok=0 ;;
    OPTIX) grep -q 'Path tracing on: NVIDIA GB10 (OptiX)' "$log" || ok=0; [ -s "$smi" ] || ok=0 ;;
  esac
  case $den in
    OIDN_GPU|OPTIX) grep -q 'Denoising on: NVIDIA GB10' "$log" || ok=0 ;;
  esac
  printf '%-18s rc=%s secs=%-8s smi_samples=%-3s %s | %s | %s\n' "$name" "$rc" "$secs" \
    "$(wc -l <"$smi")" "$([ $ok = 1 ] && echo PASS || echo FAIL)" "$pt" "$dn"
  [ $ok = 1 ] || fail=1
}
run cpu_baseline     CPU   NONE
run cuda             CUDA  NONE
run optix            OPTIX NONE
run optix_oidn_gpu   OPTIX OIDN_GPU
run cuda_oidn_gpu    CUDA  OIDN_GPU
run optix_optixden   OPTIX OPTIX
# Strict variant using the add-on CLI override (engine.py --cycles-device -> _cycles.set_device_override;
# no matching device => dummy device "Found no Cycles device of the specified type" => render error)
run optix_override   OPTIX NONE --cycles-device OPTIX
exit $fail
