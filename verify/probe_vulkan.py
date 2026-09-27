# Vulkan backend probe. Works in both modes:
#  background: blender -b --gpu-backend vulkan --factory-startup \
#                --log-level info --log "gpu.vulkan,ghost" --python-exit-code 3 --python probe_vulkan.py
#  GUI:        blender --gpu-backend vulkan --factory-startup --python probe_vulkan.py   (needs DISPLAY/WAYLAND)
# In -b the GPU module is not initialised until something needs it; gpu.init() (5.2.2,
# source/blender/python/gpu/gpu_py_api.cc) calls WM_init_gpu() -> wm_ghost_init_background()
# (tries X11/Wayland off-screen first, then GHOST_SystemHeadless which has a Vulkan headless
# platform). gpu.platform.*_get() raise SystemError if the GPU is not initialised.
# IMPORTANT: GPU_backend_type_selection_detect() silently falls back to OpenGL when Vulkan is
# unsupported, so the backend must be asserted, not assumed. llvmpipe is also a Vulkan device
# on this host, so the renderer must be asserted too.
import sys, os, bpy, gpu

def report_and_exit():
    try:
        be = gpu.platform.backend_type_get()
        info = dict(backend=be, vendor=gpu.platform.vendor_get(), renderer=gpu.platform.renderer_get(),
                    version=gpu.platform.version_get(), device_type=gpu.platform.device_type_get(),
                    devices=[(d.index, d.identifier, d.name) for d in gpu.platform.devices_get()],
                    background=bpy.app.background)
    except Exception as e:
        print("VULKAN_PROBE ERROR", repr(e)); sys.stdout.flush(); os._exit(4)
    print("VULKAN_PROBE", info)
    ok = be == 'VULKAN' and 'GB10' in info['renderer'] and info['device_type'] == 'NVIDIA'
    print("VULKAN_PROBE RESULT", "PASS" if ok else "FAIL"); sys.stdout.flush()
    if bpy.app.background:
        sys.exit(0 if ok else 1)
    # GUI: quit from the event loop; os._exit keeps the exit code deterministic
    # (wm.quit_blender always exits 0 and is deferred to the next loop iteration).
    os._exit(0 if ok else 1)

if bpy.app.background:
    gpu.init()
    report_and_exit()
else:
    def _tick():
        report_and_exit()
    bpy.app.timers.register(_tick, first_interval=2.0)
