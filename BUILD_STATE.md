# BUILD_STATE — Blender 5.2.2 for DGX Spark (GB10, sm_121, aarch64)

Resumable progress log. Update "Completed steps" / "Next action" after every step.

## Goal
Safe, reproducible, Docker-contained build of Blender v5.2.2 with Cycles CUDA + OptiX, OIDN GPU
(CUDA), Vulkan backend; portable tree installed to `~/.local/opt/blender-gb10-5.2.2`, launcher
symlink `~/.local/bin/blender-gb10`.

## Hard constraints
- No sudo; writes only under ~/blender-arm64, own labelled Docker artifacts
  (`org.zebeth.blender-gb10=1`), ~/.local/opt/blender-gb10*, ~/.local/bin/blender-gb10.
- Disk: original cap 25 GB peak extra; director raised it to <= 120 GB after / was freed externally
  (377 GB free at 02:05). RAM: ~33 GB available -> deps -j12 (LLVM -j10), ninja pools 12/3/1,
  `--memory=28g`.

## Decisions (adjudicated — Strategy A)
1. **Blender source**: git shallow fetch of `d13f752e3b9c4f8c261cda552b1021f8bcc0382c` (tag v5.2.2);
   tree reset + patched + verified (`check_source.sh`) before every build step.
2. **Dependencies**: Blender 5.2.2's own `build_files/build_environment`, explicit waves of `external_*`
   targets, harvested to `_work/lib/linux_arm64` (Blender's native aarch64 precompiled layout, so Blender's
   install bundles libs and sets `$ORIGIN/lib`). All sources hash-checked (Blender pin + repo sha256 table).
3. **Base image**: `nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04@sha256:2396393d…a240` (arm64); gcc-14 14.2.
4. **OptiX headers** v9.0.0 (`fff65c2a…`); 9.1 needs R590.
5. **CUDA arch** `sm_120` cubin (loaded on sm_121); OptiX PTX compute_75 (Blender default for CUDA 13).
6. **ISPC** prebuilt v1.30.0 aarch64 (sha256 pinned) — no LLVM for milestone 1.
7. **OIDN 2.5.0** CUDA device ON, SASS 120.
8. **Python wheels** hash-locked, offline; requests/urllib3/certifi bumped for CVEs.
9. **Vulkan loader from host** (not bundled). PipeWire OFF (needs libpipewire >= 1.1; noble has 1.0.5).
10. Config `config/blender_gb10.cmake`, `WITH_STRICT_BUILD_OPTIONS=ON`, `WITH_CYCLES_DEBUG=OFF`.
11. M1 = required + Alembic + MaterialX. M2 = + OSL (+OptiX OSL) + USD/Hydra.

## Pins
| Item | Pin |
|---|---|
| Blender | v5.2.2 @ d13f752e3b9c4f8c261cda552b1021f8bcc0382c (commit time 1789398846 = SOURCE_DATE_EPOCH) |
| Base image | nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04@sha256:2396393dc8a031a6faf810894ec8e40c8d80e2a1177cfda0c2bf81acac9aa240 |
| OptiX headers | NVIDIA/optix-dev v9.0.0 @ fff65c2a7c592f1ea5f1661ad7d2381cf965f9bd |
| ISPC | ispc-v1.30.0-linux.aarch64.tar.gz sha256 509399c399ec162d746889458a10cc13797a1aed1c0164b2bd3faddf7d023f13 |
| Deps | Blender 5.2.2 versions.cmake + deps/source-sha256.txt (118 tarballs); see DEPENDENCIES.md |
| Python wheels | deps/python-wheels.lock |
| Image apt set | deps/dpkg-manifest.lock (453 packages; drift check on every image build) |

## Completed steps
- [x] Environment checked (driver 580.173.02, GB10 CC 12.1, overlay2 docker).
- [x] Scaffolding, patches, docs committed.
- [x] **Milestone 1** built (deps ~55 min, Blender ~55 min), installed, verify.sh 5/5 PASS
      (evidence `_work/evidence/20260927T111045Z`, summary below). Reported to director.
- [x] Security review repair (MEDIUM-1/2, LOW-1..6, INFO) implemented and committed.
- [x] **Final milestone-2 build from a clean, committed tree** — build dirs, harvest and output deleted
      first; sources re-reset/re-verified; tarballs re-verified (sha256 table). Runs:
      `_work/final-run.log` (preflight, image, fetch, deps w1..w7 11:38-12:28Z, LLVM 12:28-13:08Z; OSL
      configure failed offline because OSL git-clones robin-map -> fixed in patch 0007, commit 8da1f4d) and
      `_work/final-run2.log` (fetch, deps m2 OSL+USD 13:10Z, Blender M2 build+install). Build record:
      repo_head 8da1f4d, repo_uncommitted_files=0, patches-diff-sha256 a1829b2e…cb9a, image a1ab7bca201b.
- [x] Installed to ~/.local/opt/blender-gb10-5.2.2 (read-only), verify.sh 7/7 PASS
      (evidence `_work/evidence/20260927T141912Z`, below).

## Milestone-1 evidence (20260927T111045Z)
- version: `Blender 5.2.2 LTS` via ~/.local/bin/blender-gb10.
- portable: `PORTABLE-CHECK: PASS` — 149 ELF files, all RUNPATH `$ORIGIN…`, clean-env ldd no missing,
  runtime LD_DEBUG: 110 objects initialised, 51 in-tree; libcuda/libnvoptix from /usr/lib/aarch64-linux-gnu.
  `ldd blender`: bundled libs from the tree; libvulkan.so.1, libX11, libstdc++, libc from the host.
- devices: `RAW CUDA: name='NVIDIA GB10' … oidn=True`, `RAW OPTIX: name='NVIDIA GB10' … oidn=True optix_denoiser=True`.
- cycles (all PASS; "Path tracing on:" line from Cycles' own report + PID in nvidia-smi compute-apps):
  cuda `NVIDIA GB10 (CUDA)` 1.15 s; optix `NVIDIA GB10 (OptiX)` 1.75 s; optix_oidn_gpu / cuda_oidn_gpu
  `Denoising on: NVIDIA GB10 (OptiX|CUDA)`; optix denoiser; `--cycles-device OPTIX` override; CPU baseline 1.97 s
  (512x512, 128 spp default cube).
- vulkan: V1 bg+display, V2 headless, V3 GUI on :0 — `backend VULKAN, renderer 'NVIDIA GB10', version
  'NVIDIA 580.173.02'`; V4 EEVEE under Vulkan: renderer 'NVIDIA GB10', mean_rgb 0.2504, 12 pmon samples.

## Final (milestone 2) evidence — `_work/evidence/20260927T141912Z`
- version: `Blender 5.2.2 LTS`, build date 2026-09-14 15:14:06 (= pinned commit time), via ~/.local/bin/blender-gb10.
- portable: `PORTABLE-CHECK: PASS` — 190 ELF files; runtime trace 121 objects initialised, 59 in-tree;
  libcuda/libnvoptix from the host driver dir; nothing from /usr/local, /opt, /home (outside the tree).
- hardening: build record clean (`repo_uncommitted_files=0`, `SOURCE-CHECK: OK`), tree read-only, CWD
  `libXau.so.6` injection probe not loaded via symlink or binary; `blender-launcher` not shipped.
- devices: CUDA `NVIDIA GB10` oidn=True; OPTIX `NVIDIA GB10` oidn=True optix_denoiser=True.
- features: build_options cycles/openvdb/alembic/ffmpeg/sndfile/openexr/openjpeg/webp/opencolorio/opensubdiv/
  openxr/openal/pulseaudio/jack/haru/potrace/fluid/libmv/usd/cycles_osl all True; Cycles with_osl/embree/OIDN
  True; Python 3.13.13, NumPy 2.3.4, OCIO 2.5.0, requests 2.34.2, urllib3 2.8.0; Alembic export; USD
  export+import round trip (3 -> 7 objects).
- cycles: CPU 1.95 s; CUDA 1.44 s (`Path tracing on: NVIDIA GB10 (CUDA)`); OptiX 3.40 s (`(OptiX)`);
  OIDN on GPU with OptiX and CUDA devices (`Denoising on: NVIDIA GB10 (OptiX|CUDA)`); OptiX denoiser;
  `--cycles-device OPTIX` override; OSL on CPU 2.60 s; **OSL on OptiX 591.8 s** (first-run JIT of OSL
  kernels; cached afterwards in the OptiX cache). PID present in nvidia-smi compute-apps for every GPU case.
- vulkan: V1 background+display, V2 headless, V3 GUI window on :0 — backend VULKAN, renderer 'NVIDIA GB10',
  device_type NVIDIA (llvmpipe listed as device 1, not used); V4 EEVEE render under Vulkan, mean_rgb 0.2504.

## Disk usage log
- 01:35 start: / avail 38 GB (budget 25 GB) — 02:05 / avail 377 GB (freed externally; budget 120 GB).
- M1 peak: _work ≈ 8 GB (deps pruned per wave: build/deps ≤ 1.4 GB) + install 0.8 GB + image 7.3 GB
  → ≈ 17 GB peak extra.
- M2 final run, measured just before pruning: _work 13 GB (build/deps 4.1, build/blender 2.6, lib 1.5,
  out 1.1, src 2.0, packages 1.7) + install 1.1 GB + images 7.3 GB (devel base 6.5 + layer 0.7). Peak during
  the LLVM build was higher (LLVM tree, estimated +4-5 GB) → **peak ≈ 25-27 GB extra**, plus ≈3.2 GB of
  BuildKit cache left from the first two image builds (see below). Within the revised 120 GB cap; slightly
  above the original 25 GB budget.
- After `./build.sh prune`: _work 6.2 GB + install 1.1 GB + image 7.3 GB.

## Docker artifacts created
- image `blender-gb10-builder:5.2.2` (labelled; classic builder, intermediate layers labelled).
- pulled base images: nvcr.io/nvidia/cuda@sha256:2396393d… (13.0.3-devel, parent of the builder image, kept
  for rebuilds); @sha256:56d9d818… (13.0.3-base, first attempt) — **removed**.
- removed: two superseded builder images (fc9d37d8199f, 9bcfeab2882e, fb83089a2627), test image
  blender-gb10-lbtest. `./build.sh clean-docker` removes the rest (labelled images + base image).
- containers: all `--rm`.
- **Leftover**: ≈3.2 GB of BuildKit cache records from the first two image builds (default builder,
  before the switch to the classic builder). `docker builder prune --filter id=…` does not remove them on
  this Docker 29.6 daemon, and an unfiltered prune would also delete other projects' cache (1.8 GB) —
  left for the user to decide.

## Remaining limitations
- Ubuntu apt packages are recorded/drift-checked (deps/dpkg-manifest.lock), not frozen: snapshot.ubuntu.com
  returns 401 for ubuntu-ports.
- ≈3.2 GB BuildKit cache from the first two image builds could not be pruned selectively on Docker 29.6
  (`--filter id=` removes nothing); an unfiltered `docker builder prune` would also remove other projects'
  cache — user decision.
- PipeWire audio backend OFF (Ubuntu 24.04 libpipewire 1.0.5 < 1.1 required); PulseAudio/JACK ON (dynload).
- OSL on OptiX: first render JIT-compiles for ~10 min.
- ~/.config/blender/5.2 exists (created 04:10 by the milestone-1 verify run, before verify was sandboxed); it
  now also holds another agent's MCP extension, so it was left in place.

## Next action
Done. Independent verification by the director's verifier; push decision is the user's.
