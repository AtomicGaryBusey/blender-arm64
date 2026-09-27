# blender -b --factory-startup --python-exit-code 3 --python probe_cycles_devices.py [-- --need CUDA,OPTIX --name GB10]
# Lists Cycles devices per backend through the add-on preferences API (5.2.2:
# intern/cycles/blender/addon/properties.py CyclesPreferences.refresh_devices/get_devices_for_type)
# and the raw _cycles.available_devices() tuples (intern/cycles/blender/python.cpp:
# (name, type, id, has_peer_memory, use_hardware_raytracing, OIDN-capable, OptiX-denoiser-capable,
#  has_execution_optimization)). Exits 0 only if every --need backend exposes a device whose name
# contains --name. sys.exit(n) is honoured by Blender (PyC_Err_CaptureSystemExitCode).
import sys, json
import bpy, _cycles

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
need = ["CUDA", "OPTIX"]; want = "GB10"
if "--need" in argv: need = argv[argv.index("--need") + 1].split(",")
if "--name" in argv: want = argv[argv.index("--name") + 1]

print("BLENDER", bpy.app.version_string, bpy.app.build_hash.decode(), bpy.app.build_branch.decode())
types = dict(zip(("CUDA", "OPTIX", "HIP", "METAL", "ONEAPI", "HIPRT"), _cycles.get_device_types()))
print("CYCLES_BUILD", json.dumps({"device_types": types,
      "with_openimagedenoise": bool(_cycles.with_openimagedenoise),
      "with_osl": bool(_cycles.with_osl), "with_embree": bool(_cycles.with_embree),
      "build_options.cycles": bpy.app.build_options.cycles}))

prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.refresh_devices()
ok = True
for t in need:
    raw = _cycles.available_devices(t)
    for r in raw:
        print(f"RAW {t}: name={r[0]!r} type={r[1]} id={r[2]} hwrt={r[4]} oidn={r[5]} optix_denoiser={r[6]}")
    devs = prefs.get_devices_for_type(t)
    lst = [{"name": d.name, "type": d.type, "id": d.id, "use": d.use} for d in devs]
    print(f"PREFS {t}:", json.dumps(lst))
    hit = [d for d in lst if d["type"] == t and want in d["name"]]
    print(f"RESULT {t}: {'OK' if hit else 'MISSING'}")
    ok &= bool(hit)
sys.exit(0 if ok else 1)
