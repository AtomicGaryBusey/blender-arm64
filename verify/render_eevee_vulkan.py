# blender -b --gpu-backend vulkan --factory-startup --log-level info --log "gpu.vulkan" \
#   --python-exit-code 3 --python render_eevee_vulkan.py -- --out /path/eevee.png
# EEVEE engine id in 5.2.2 is 'BLENDER_EEVEE' (draw/engines/eevee/eevee_engine.cc).
# gpu.init() first, so the backend/renderer can be asserted BEFORE rendering; the render then
# reuses that context (DRW_gpu_context_enable only calls WM_init_gpu when no context exists).
import sys, time, bpy, gpu
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[argv.index("--out") + 1] if "--out" in argv else "/tmp/eevee_vulkan.png"

gpu.init()
be, ren = gpu.platform.backend_type_get(), gpu.platform.renderer_get()
print("EEVEE_PROOF backend=%s renderer=%r vendor=%r" % (be, ren, gpu.platform.vendor_get()))
if be != 'VULKAN' or 'GB10' not in ren:
    print("EEVEE_PROOF FAIL: not Vulkan on GB10"); sys.exit(1)

s = bpy.context.scene
s.render.engine = 'BLENDER_EEVEE'
s.eevee.taa_render_samples = 16
s.render.resolution_x = s.render.resolution_y = 512; s.render.resolution_percentage = 100
s.render.image_settings.file_format = 'PNG'; s.render.filepath = OUT
t0 = time.time(); bpy.ops.render.render(write_still=True); dt = time.time() - t0
img = bpy.data.images.load(OUT); px = img.pixels[:]
mean = sum(px[i] + px[i+1] + px[i+2] for i in range(0, len(px), 4)) / (len(px) / 4) / 3
print(f"EEVEE_PROOF render_seconds={dt:.3f} mean_rgb={mean:.4f} size={tuple(img.size)}")
sys.exit(0 if mean > 0.01 else 2)
