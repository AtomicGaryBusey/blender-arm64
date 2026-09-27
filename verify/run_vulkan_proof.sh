#!/usr/bin/env bash
# run_vulkan_proof.sh <tree> <outdir>
set -uo pipefail
T=$(realpath "$1"); O=$(realpath -m "$2"); mkdir -p "$O"; here=$(cd "$(dirname "$0")" && pwd)
B="$T/blender"; fail=0
chk() { local name=$1 rc=$2 pat=$3; if [ "$rc" -eq 0 ] && grep -q "$pat" "$O/$name.log"; then echo "PASS $name"; else echo "FAIL $name rc=$rc"; fail=1; fi; }

# V0: Vulkan device enumeration straight from Blender (prints and exits; creator_args.cc --gpu-device help)
"$B" --gpu-device help >"$O/v0_devices.log" 2>&1; echo "V0 rc=$? :"; cat "$O/v0_devices.log" | head -20

# V1: background, display available (GHOST X11/Wayland off-screen system)
"$B" -b --gpu-backend vulkan --factory-startup --log-level info --log "gpu.vulkan,ghost" \
   --python-exit-code 3 --python "$here/probe_vulkan.py" >"$O/v1_bg_display.log" 2>&1
chk v1_bg_display $? "VULKAN_PROBE RESULT PASS"

# V2: background, NO display (forces GHOST_SystemHeadless -> Vulkan headless platform)
env -u DISPLAY -u WAYLAND_DISPLAY "$B" -b --gpu-backend vulkan --factory-startup --log-level info \
   --log "gpu.vulkan,ghost" --python-exit-code 3 --python "$here/probe_vulkan.py" >"$O/v2_bg_headless.log" 2>&1
chk v2_bg_headless $? "VULKAN_PROBE RESULT PASS"

# V3: GUI (opens a window on :0 / wayland-0 for ~2 s, exits via timer + os._exit)
timeout 120 "$B" --gpu-backend vulkan --factory-startup --python "$here/probe_vulkan.py" >"$O/v3_gui.log" 2>&1
chk v3_gui $? "VULKAN_PROBE RESULT PASS"

# V4: EEVEE render under Vulkan in background, with per-PID GPU sampling (Vulkan shows as type G/C+G)
"$B" -b --gpu-backend vulkan --factory-startup --log-level info --log "gpu.vulkan" --python-exit-code 3 \
   --python "$here/render_eevee_vulkan.py" -- --out "$O/eevee_vulkan.png" >"$O/v4_eevee.log" 2>&1 &
pid=$!; : >"$O/v4_eevee.pmon"
while kill -0 $pid 2>/dev/null; do nvidia-smi pmon -c 1 2>/dev/null | awk -v p=$pid '$2==p' >>"$O/v4_eevee.pmon"; sleep 0.5; done
wait $pid; rc=$?
chk v4_eevee $rc "EEVEE_PROOF backend=VULKAN"
echo "V4 pmon samples for pid $pid: $(wc -l <"$O/v4_eevee.pmon")"; grep EEVEE_PROOF "$O/v4_eevee.log"
exit $fail
