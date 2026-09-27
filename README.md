# Blender 5.2.2 for NVIDIA DGX Spark (GB10, aarch64): safe, pinned, containerised

This repository builds **Blender 5.2.2** for the NVIDIA DGX Spark (GB10 Grace-Blackwell,
compute capability 12.1, Ubuntu 24.04 / DGX OS, driver R580) with:

| Feature | How |
|---|---|
| Cycles **CUDA** | `sm_120` cubin, CUDA 13.0.x. It runs natively on GB10's sm_121 because Cycles picks the `sm_12x` cubin. |
| Cycles **OptiX** | OptiX 9.0 headers from [NVIDIA/optix-dev](https://github.com/NVIDIA/optix-dev), which are public, so no NVIDIA account is needed. OptiX 9.1 needs an R590 driver, so 9.0 is the newest version R580 accepts. |
| **OpenImageDenoise** GPU | OIDN 2.5.0 with its CUDA device (`libOpenImageDenoise_device_cuda`), SASS for sm_120 |
| **Vulkan** GPU backend | `--gpu-backend vulkan`, using the host Vulkan loader and the NVIDIA ICD |
| Bundled Python 3.13 + NumPy 2.3 | Blender's pinned versions |
| OpenColorIO, OpenVDB + NanoVDB, Embree 4 (NEON), OpenEXR, OpenJPEG, WebP, FFmpeg 8.1, Alembic, MaterialX, OpenSubdiv, Manifold, OpenXR, path guiding (OpenPGL) | Blender's own dependency builder |
| Wayland + X11 windowing | GHOST Wayland (dynamically loaded, with libdecor) and X11 |

The output is a **self-contained portable tree** in Blender's `WITH_INSTALL_PORTABLE` layout
(`blender`, `lib/`, `5.2/`). Its binaries use `$ORIGIN`-relative RUNPATHs, so it runs on the host
without `LD_LIBRARY_PATH` and without installing any packages. It deliberately does **not**
bundle glibc, libstdc++, libGL/EGL/GLX, `libvulkan.so.1`, NVIDIA driver libraries
(`libcuda`, `libnvoptix`, …) or X11/Wayland/audio client libraries. Those come from the host.

## Quick start

```bash
git clone https://github.com/AtomicGaryBusey/blender-arm64.git && cd blender-arm64
git checkout spark-safe
./build.sh            # preflight, image, fetch, deps, blender, install, verify  (takes several hours)
blender-gb10          # ~/.local/bin/blender-gb10 -> ~/.local/opt/blender-gb10-5.2.2/blender
```

You can also run the steps one at a time: `./build.sh preflight|image|fetch|deps|blender|install|verify|prune|clean-docker`.

These environment variables tune the build:

| Variable | Default | Controls |
|---|---|---|
| `JOBS` | 12 | parallel compile jobs |
| `CUDA_JOBS` | 2 | parallel CUDA kernel jobs |
| `MEM_LIMIT` | 28g | container memory cap |
| `DISK_BUDGET_GB` | 60 | disk budget checked by preflight |
| `DEPS_WAVES` | `w1 … w7` (milestone 1) | which dependency waves to build |

Host requirements:

* aarch64
* NVIDIA driver 580 or newer
* Docker usable without sudo
* the NVIDIA container toolkit, so that `docker run --gpus all` works (only the preflight check needs it)
* about 60 GB of free disk and about 30 GB of free RAM during the build

**No sudo is used or needed.**

## What gets built, and from what

Everything is compiled from source inside the container, with two exceptions: the NVIDIA CUDA
toolkit, which comes in the pinned base image, and ISPC, which is the official release binary and
is only used as a compiler for OIDN's CPU kernels.

* **Blender** v5.2.2, git commit `d13f752e3b9c4f8c261cda552b1021f8bcc0382c`. It is fetched by
  commit and the commit is verified. The `lib/` and `tests/` submodules are not fetched.
* **Third-party libraries** come from Blender's own dependency builder (`build_files/build_environment`),
  with exactly the versions, URLs, hashes and patches Blender pins for 5.2.2. They are harvested into
  `lib/linux_arm64`, the layout Blender's CMake natively uses for precompiled libraries on
  Linux aarch64. Because of that layout, Blender's own install step bundles the libraries and sets
  `$ORIGIN/lib`. [DEPENDENCIES.md](DEPENDENCIES.md) has the full list with hashes and licenses.
* **Toolchain image**: [`Dockerfile`](Dockerfile). It uses `nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04`
  pinned by arm64 digest, plus Ubuntu build tools and `gcc-14` (Blender 5.2 requires GCC 14 or newer).
  The resolved Ubuntu package list is recorded in `_work/record/dpkg-manifest.txt` and inside
  the install tree (`blender-gb10-build-image-dpkg.txt`).
* **Patches**: [`patches/`](patches/README.md), each one documented.
* **Blender configuration**: [`config/blender_gb10.cmake`](config/blender_gb10.cmake). It sets
  `WITH_STRICT_BUILD_OPTIONS=ON`, so a missing library fails the configure step instead of silently
  dropping a feature. `WITH_CYCLES_DEBUG` is **off**.

Milestone 2 is optional and is enabled with `DEPS_WAVES="m2_llvm m2"` and `BLENDER_GB10_M2=1`. It
adds LLVM, OSL (Cycles OSL) and USD/Hydra. BUILD_STATE.md records what the current build includes.

## Security model

The upstream `builder.sh` this fork started from had several unsafe practices:

* it ran `sudo cp` over dpkg-owned files in `/usr`;
* it ran `sudo make install` for six libraries and Python into system prefixes;
* it built ten repositories at unpinned `HEAD` as root;
* it downloaded ceres over plain HTTP without a checksum.

All of that is gone. The build now follows these rules:

1. **No sudo, no root.** `build.sh` refuses to run as root. Every compile step runs in the
   container as the unprivileged `builder` user with the host UID, `--cap-drop ALL`,
   `--security-opt no-new-privileges` and a memory cap.
2. **Nothing is written outside a fixed set of places**:
   * this repository's git-ignored `_work/` directory;
   * the Docker artifacts the build creates, all labelled `org.zebeth.blender-gb10=1`;
   * `~/.local/opt/blender-gb10-5.2.2`;
   * the `~/.local/bin/blender-gb10` symlink.

   `/usr`, `/opt` and `/etc` are never touched.
3. **Everything is pinned.**
   * Git sources are pinned by commit and verified after fetch.
   * Tarballs are pinned by the hash Blender pins. The hash is checked at configure time with
     `FORCE_CHECK_HASH=ON` and again at extraction.
   * ISPC is pinned by sha256.
   * Python wheels are pinned by sha256 and installed offline with `pip --require-hashes`.
   * The base image is pinned by digest, and CUDA comes from that image.
4. **Network access only when fetching.** Only the `fetch` step (sources, wheels, dependency
   tarballs) has network access. Dependency and Blender builds run with `--network none`, so the
   build cannot pull anything that was not pinned and verified beforehand.
5. **Reproducible from the scripts.** There is no separate, unsigned prebuilt release. You build it
   yourself, and `verify.sh` checks the result.

The model has known limits:

* Ubuntu packages inside the image follow the `noble` archive. Their resolved versions are recorded, not frozen.
* The NVIDIA base image and the ISPC binary are trusted vendor binaries, pinned by digest and hash.

## Verifying a build

```bash
./verify.sh [tree] [evidence-dir]
```

This runs on the host, without `LD_LIBRARY_PATH`, and stores logs and images under
`_work/evidence/…`. It checks five things:

1. **Version.** `blender-gb10 --version` reports 5.2.2.
2. **Portability** (`verify/check_portable.sh`):
   * every RUNPATH is `$ORIGIN`-relative;
   * a clean-environment `ldd` of every ELF reports nothing missing;
   * nothing resolves from `/usr/local`, `/opt` or `/home`. This matters because the host has a CUDA
     toolkit in `/usr/local` that could hide a missing library;
   * only an allow-list of host libraries (glibc, libstdc++, GL/Vulkan loaders, NVIDIA driver,
     X11/Wayland/audio clients) comes from the host;
   * an `LD_DEBUG` trace of a real run shows `libcuda`/`libnvoptix` coming from the host driver directory.
3. **Devices.** Cycles lists the NVIDIA GB10 for CUDA and OPTIX.
4. **Cycles renders.** It renders on CPU, CUDA and OptiX, with OIDN on the GPU (CUDA and OptiX
   devices), and with the OptiX denoiser. GPU use is proven by Cycles' own log lines
   (`Path tracing on: NVIDIA GB10 (OptiX)`, `Denoising on: NVIDIA GB10 …`) and by the Blender PID
   appearing in `nvidia-smi`. OIDN silently falls back to the CPU if the GPU path fails, so the
   setting alone proves nothing.
5. **Vulkan.** With `--gpu-backend vulkan`, `gpu.platform.backend_type_get()` must return `'VULKAN'`
   with an NVIDIA GB10 renderer (not llvmpipe). This is checked in background mode with and without
   a display, and in a GUI window on the host display. An EEVEE render under Vulkan is also run.
   Blender silently falls back to OpenGL if Vulkan fails, so the backend is asserted rather than assumed.

## Notes for DGX Spark

* `cuMemGetInfo` under-reports free memory on DGX Spark because the unified memory's page cache is
  counted as used. This is a known NVIDIA issue. As a result, Cycles may report less free GPU memory
  than the system really has.
* The GPU is shared with anything else running, such as inference servers, so render times vary.

## Repository layout

| Path | Purpose |
|---|---|
| `build.sh` | host driver (preflight and the containerised steps) |
| `Dockerfile` | pinned toolchain image |
| `scripts/pins.env` | top-level pins (Blender, OptiX, base image, CUDA arch) |
| `scripts/container/` | steps run inside the container (fetch, patches, deps, blender) |
| `config/blender_gb10.cmake` | Blender CMake configuration |
| `patches/` | documented patches applied to the Blender tree |
| `deps/python-wheels.lock` | hash-locked Python wheels |
| `DEPENDENCIES.md` | full dependency manifest (version, URL, hashes, license) |
| `verify.sh`, `verify/` | acceptance tests |
| `BUILD_STATE.md` | build log, decisions, evidence |

## Credits

* **[CoconutMacaroon/blender-arm64](https://github.com/CoconutMacaroon/blender-arm64)**: the original
  project, and the proof that Blender with CUDA, OptiX and Vulkan runs on GB10. This fork keeps its
  MIT [LICENSE](LICENSE).
* **[mvalancy/blender-nvidia-gb10](https://github.com/mvalancy/blender-nvidia-gb10)**: notes on
  CUDA 13 / GB10 issues. Its Wayland `lib64` and FFmpeg libdrm findings informed patches 0003 and
  0004, which were re-implemented for 5.2.2 rather than copied. Its OIDN sm_70 patch turned out to
  be unnecessary for OIDN 2.5.0.
* **[lfdevs/blender-linux-arm64](https://github.com/lfdevs/blender-linux-arm64)**: evidence that
  Blender's dependency builder works on Linux aarch64.
* The portability checker and GPU proof scripts in `verify/` were written by the research scouts of
  the multi-agent session that produced this fork, then adapted here.
* The Blender Foundation, for the dependency builder, and NVIDIA, for the public OptiX headers.

Blender itself is GPL-2.0-or-later, and the bundled libraries carry their own licenses (see
DEPENDENCIES.md). The scripts in this repository are MIT-licensed.
