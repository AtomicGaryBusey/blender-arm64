# blender -b --factory-startup --python-exit-code 3 --python probe_features.py [-- --m2]
# Checks that the optional/required libraries are really compiled in and usable:
# bpy.app.build_options, bundled NumPy / PyOpenColorIO / requests, OpenVDB+NanoVDB, Alembic,
# (with --m2) USD export+import round trip and OSL availability.
import sys, os, tempfile
import bpy, _cycles

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
m2 = "--m2" in argv
bo = bpy.app.build_options
need = ["cycles", "openvdb", "alembic", "codec_ffmpeg", "codec_sndfile", "image_openexr",
        "image_openjpeg", "image_webp", "opencolorio", "opensubdiv", "xr_openxr", "openal",
        "pulseaudio", "jack", "haru", "potrace", "fluid", "libmv"]
if m2:
    need += ["usd", "cycles_osl"]
ok = True
for k in need:
    v = getattr(bo, k, None)
    print(f"FEATURE build_options.{k} = {v}")
    ok &= bool(v)
print("FEATURE cycles with_osl =", _cycles.with_osl, " with_embree =", _cycles.with_embree,
      " with_openimagedenoise =", _cycles.with_openimagedenoise)
ok &= bool(_cycles.with_embree) and bool(_cycles.with_openimagedenoise)
if m2:
    ok &= bool(_cycles.with_osl)
import numpy, PyOpenColorIO, requests, urllib3
print("FEATURE python", sys.version.split()[0], "numpy", numpy.__version__, "ocio", PyOpenColorIO.__version__,
      "requests", requests.__version__, "urllib3", urllib3.__version__)
tmp = tempfile.mkdtemp()
abc = os.path.join(tmp, "cube.abc")
bpy.ops.wm.alembic_export(filepath=abc)
print("FEATURE alembic export bytes", os.path.getsize(abc)); ok &= os.path.getsize(abc) > 0
if m2:
    usd = os.path.join(tmp, "cube.usdc")
    bpy.ops.wm.usd_export(filepath=usd)
    n0 = len(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=usd)
    print("FEATURE usd export bytes", os.path.getsize(usd), "objects", n0, "->", len(bpy.data.objects))
    ok &= len(bpy.data.objects) > n0
print("FEATURE RESULT", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
