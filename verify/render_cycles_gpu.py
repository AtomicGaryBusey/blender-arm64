# blender -b --factory-startup --log-level info --log cycles --python-exit-code 3 \
#   --python render_cycles_gpu.py -- --device OPTIX --denoise OIDN_GPU --out /path/out.png [--cycles-device OPTIX] [--cycles-print-stats]
# --device   CUDA | OPTIX | CPU
# --denoise  NONE | OIDN_GPU | OIDN_CPU | OPTIX
# Renders the factory-startup scene (cube/light/camera) and exits non-zero if the image is empty.
# GPU/denoiser proof is in the Cycles INFO log ("Full path tracing report": "Path tracing on: ...",
# "Denoising on: ...") -- parse it with run_cycles_proof.sh; Cycles silently falls back to CPU
# OIDN (integrator/denoiser.cpp get_effective_denoise_params) so the log line is the evidence.
import sys, time
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def opt(k, d):
    return argv[argv.index(k) + 1] if k in argv else d
DEV = opt("--device", "OPTIX"); DEN = opt("--denoise", "NONE"); OUT = opt("--out", "/tmp/cycles_proof.png")
SPP = int(opt("--samples", "128")); RES = int(opt("--res", "512"))

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
cp = bpy.context.preferences.addons["cycles"].preferences
if DEV != "CPU":
    cp.compute_device_type = DEV
    cp.refresh_devices()
    # Only the requested backend's GPU devices, no CPU in the multi-device.
    for d in cp.devices:
        d.use = (d.type == DEV)
    used = [(d.name, d.type) for d in cp.devices if d.use]
    print("PROOF selected devices:", used)
    if not used:
        print("PROOF ERROR: no", DEV, "device"); sys.exit(1)
    scene.cycles.device = 'GPU'
else:
    scene.cycles.device = 'CPU'

c = scene.cycles
if "--osl" in argv:
    c.shading_system = True      # Open Shading Language (CPU, or OptiX on the GPU)
    print("PROOF shading_system=OSL")
c.samples = SPP
c.use_adaptive_sampling = False
c.use_denoising = DEN != "NONE"
if DEN in ("OIDN_GPU", "OIDN_CPU"):
    c.denoiser = 'OPENIMAGEDENOISE'
    c.denoising_use_gpu = (DEN == "OIDN_GPU")
elif DEN == "OPTIX":
    c.denoiser = 'OPTIX'
scene.render.resolution_x = RES; scene.render.resolution_y = RES; scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = OUT

last_stats = []
def on_stats(s):          # bpy.app.handlers.render_stats: called with the stats string
    last_stats[:] = [s]
bpy.app.handlers.render_stats.append(on_stats)

t0 = time.time()
bpy.ops.render.render(write_still=True)
dt = time.time() - t0
print(f"PROOF device={DEV} denoise={DEN} spp={SPP} res={RES} render_seconds={dt:.3f}")
print("PROOF last render_stats:", last_stats[0] if last_stats else None)

img = bpy.data.images.load(OUT)
px = img.pixels[:]                        # RGBA floats
lum = sum(px[i] + px[i+1] + px[i+2] for i in range(0, len(px), 4)) / (len(px) / 4) / 3
print(f"PROOF image={OUT} size={tuple(img.size)} mean_rgb={lum:.4f}")
sys.exit(0 if lum > 0.01 else 2)
