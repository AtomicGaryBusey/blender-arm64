# BUILD_STATE — Blender 5.2.2 for DGX Spark (GB10, sm_121, aarch64)

Resumable progress log. Update "Completed steps" / "Next action" after every step.

## Goal
Safe, reproducible, Docker-contained build of Blender v5.2.2 with Cycles CUDA + OptiX, OIDN GPU
(CUDA), Vulkan backend; portable tree installed to `~/.local/opt/blender-gb10-5.2.2`, launcher
symlink `~/.local/bin/blender-gb10`.

## Hard constraints
- No sudo; writes only under ~/blender-arm64, own labelled Docker artifacts
  (`org.zebeth.blender-gb10=1`), ~/.local/opt/blender-gb10*, ~/.local/bin/blender-gb10.
- Disk: original cap 25 GB peak extra; director raised it to <= 120 GB after / was freed
  (377 GB free at 02:05). RAM: ~33 GB available -> deps -j12, ninja pools 12/3/1, --memory=28g.

## Decisions (adjudicated, see scratchpad ADJUDICATION.md — Strategy A)
1. **Blender source**: git shallow fetch of pinned commit `d13f752e3b9c4f8c261cda552b1021f8bcc0382c`
   (tag v5.2.2). No lib/ or tests/ submodules (no official lib/linux_arm64 for 5.2.2 is used).
2. **Dependencies**: Blender 5.2.2's own `build_files/build_environment`, all versions/hashes/patches as
   pinned in `versions.cmake`, built in waves of explicit `external_*` targets, harvested into
   `lib/linux_arm64` (Blender's native precompiled layout -> Blender's install bundles libs + `$ORIGIN/lib`).
   All sources downloaded and hash-checked at configure (`FORCE_CHECK_HASH=ON`).
3. **Base image**: `nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04` @ arm64 digest
   `sha256:2396393dc8a031a6faf810894ec8e40c8d80e2a1177cfda0c2bf81acac9aa240` (CUDA 13.0.x only).
4. **Compiler**: gcc-14/g++-14 14.2.0 (noble-updates) — Blender 5.2 rejects GCC < 14; host libstdc++ is 14.2.
5. **OptiX headers**: NVIDIA/optix-dev v9.0.0 `fff65c2a7c592f1ea5f1661ad7d2381cf965f9bd`
   (9.1 needs R590; host driver 580 rejects its ABI).
6. **CUDA arch**: `CYCLES_CUDA_BINARIES_ARCH=sm_120` (sm_120 SASS runs on sm_121; Cycles looks for
   sm_121 then sm_120 cubins). No Cycles patch.
7. **ISPC**: official prebuilt v1.30.0 aarch64, sha256 `509399c3...3f13` (patch 0001) — no LLVM needed
   for milestone 1.
8. **OIDN 2.5.0** with `OIDN_DEVICE_CUDA=ON` (upstream recipe on ARM Linux) + SASS list `120` (patch 0005).
9. **Python site-packages**: hash-locked wheels (deps/python-wheels.lock), installed offline (patch 0006).
10. **Vulkan loader not bundled** (patch 0008, `WITH_BUNDLED_VULKAN_LOADER=OFF`): host libvulkan.so.1 + NVIDIA ICD.
11. Blender config: `config/blender_gb10.cmake` (not blender_release.cmake), `WITH_STRICT_BUILD_OPTIONS=ON`,
    JACK/Pulse/PipeWire DYNLOAD, WITH_CYCLES_DEBUG OFF.
12. Milestones: M1 = required features + Alembic + MaterialX -> build, install, verify, report to director.
    M2 = OSL (+OptiX OSL, fallback CPU-only) + USD/Hydra.

## Pins
| Item | Pin |
|---|---|
| Blender | v5.2.2 @ d13f752e3b9c4f8c261cda552b1021f8bcc0382c |
| Base image | nvcr.io/nvidia/cuda:13.0.3-devel-ubuntu24.04@sha256:2396393dc8a031a6faf810894ec8e40c8d80e2a1177cfda0c2bf81acac9aa240 |
| OptiX headers | NVIDIA/optix-dev v9.0.0 @ fff65c2a7c592f1ea5f1661ad7d2381cf965f9bd |
| ISPC | ispc-v1.30.0-linux.aarch64.tar.gz sha256 509399c399ec162d746889458a10cc13797a1aed1c0164b2bd3faddf7d023f13 |
| Deps | Blender 5.2.2 versions.cmake (see DEPENDENCIES.md) |
| Python wheels | deps/python-wheels.lock |

## Completed steps
- [x] Environment checked (driver 580.173.02, GB10 CC 12.1, overlay2 docker).
- [x] Blender 5.2.2 fetched (shallow, 1.1 GB) + optix-dev v9.0.0 fetched, both commit-verified.
- [x] Scaffolding committed: 051734e (remove unsafe), 9704488 (toolchain/driver), ecfe8c5 (patches), 814258f (wheel lock).
- [x] First deps configure (pre-adjudication, base image variant) downloaded 876 MB, all hash-checked.
      Note: at that time ADJUDICATION.md did not exist yet; it was configure/download only (no build).
- [ ] Image rebuild on CUDA devel base (in progress).
- [ ] deps configure (re-run with final patches), deps waves w1..w7, harvest.
- [ ] Blender M1 build/install, verify.sh, report to director.
- [ ] M2 (OSL, USD/Hydra).

## Disk usage log
- 01:35 start: / avail 38 GB.
- 02:05 / avail 377 GB (freed externally). _work = 2.0 GB + 0.9 GB packages.

## Docker artifacts created (all labelled org.zebeth.blender-gb10=1 where Docker allows)
- image `blender-gb10-builder:5.2.2` (label set).
- pulled base images (pulls cannot carry labels): nvcr.io/nvidia/cuda@sha256:56d9d818… (13.0.3-base, first
  attempt; to be removed at cleanup), nvcr.io/nvidia/cuda@sha256:2396393d… (13.0.3-devel).
- containers: all `docker run --rm` (none persist).

## Next action
When image build finishes: `docker run ... deps.sh configure` (network) then `./build.sh deps` in background.
