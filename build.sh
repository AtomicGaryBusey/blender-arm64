#!/usr/bin/env bash
# Host-side driver for the containerised Blender 5.2.2 build for NVIDIA DGX Spark (GB10).
#
# Security model (see README.md):
#   * never uses sudo and refuses to run as root;
#   * every container runs as the unprivileged host UID/GID with all capabilities
#     dropped and no-new-privileges; compile steps (deps, blender) run with
#     --network none. Only `image` (apt) and `fetch` (pinned sources) use the network;
#   * builds refuse to run from a dirty checkout, and the Blender tree is verified to be
#     exactly the pinned commit + patches/ before every build step;
#   * nothing is written outside this repository (_work/ scratch), the Docker
#     artifacts it creates (all labelled org.zebeth.blender-gb10=1, plus the pinned
#     base image it pulls), ~/.local/opt/blender-gb10-<ver> and ~/.local/bin/blender-gb10.
#
# Usage: ./build.sh [step ...]
#   steps: preflight image fetch deps blender install verify prune clean-docker all
#   default: all  (= preflight image fetch deps blender install verify)
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/pins.env
source "$REPO/scripts/pins.env"

WORK="${BLENDER_GB10_WORK:-$REPO/_work}"
IMAGE="blender-gb10-builder:${BLENDER_VERSION}"
LABEL="org.zebeth.blender-gb10=1"
JOBS="${JOBS:-12}"                    # C/C++ parallelism (RAM ~33 GB available on the reference host)
CUDA_JOBS="${CUDA_JOBS:-2}"           # parallel nvcc/OptiX kernel jobs (3-12 GB each)
MEM_LIMIT="${MEM_LIMIT:-28g}"         # container memory cap: protects the host from OOM
DISK_BUDGET_GB="${DISK_BUDGET_GB:-60}"
MIN_DRIVER="580"                      # CUDA 13.0 needs R580+; OptiX 9.0 ABI needs R570+
PREFIX="${BLENDER_GB10_PREFIX:-$HOME/.local/opt/blender-gb10-${BLENDER_VERSION}}"
LAUNCHER="${BLENDER_GB10_LAUNCHER:-$HOME/.local/bin/blender-gb10}"

log()  { printf '\033[1;34m[build.sh]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[build.sh] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Builds must come from a fully committed checkout so the output is attributable.
require_clean_repo() {
  [[ "${BLENDER_GB10_ALLOW_DIRTY:-0}" == 1 ]] && { log "WARNING: BLENDER_GB10_ALLOW_DIRTY=1, not checking the checkout"; return; }
  local dirty
  # BUILD_STATE.md is the progress log, not a build input.
  dirty="$(git -C "$REPO" status --porcelain --untracked-files=all -- . ':!BUILD_STATE.md')"
  [[ -z "$dirty" ]] || die "the repository has uncommitted changes; commit them first (or BLENDER_GB10_ALLOW_DIRTY=1 for experiments):
$dirty"
}

# ---------------------------------------------------------------------------
preflight() {
  log "preflight"
  [[ $EUID -ne 0 ]] || die "do not run as root (no sudo is needed or wanted)"
  [[ "$(uname -m)" == "aarch64" ]] || die "this build targets aarch64 (found $(uname -m))"
  command -v nvidia-smi >/dev/null || die "nvidia-smi not found: NVIDIA driver missing"
  local drv
  drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
  [[ -n "$drv" ]] || die "could not read NVIDIA driver version"
  (( ${drv%%.*} >= MIN_DRIVER )) || die "NVIDIA driver $drv < required $MIN_DRIVER"
  log "  driver $drv, GPU: $(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader | head -1)"
  command -v docker >/dev/null || die "docker not found"
  command -v git >/dev/null || die "git not found"
  docker info >/dev/null 2>&1 || die "docker daemon not reachable (is your user in the docker group?)"
  docker run --rm --label "$LABEL" --gpus all --network none --user "$(id -u):$(id -g)" \
    --cap-drop ALL --security-opt no-new-privileges "$BASE_IMAGE" nvidia-smi -L >/dev/null 2>&1 \
    || die "'docker run --gpus all' failed: install/configure nvidia-container-toolkit"
  mkdir -p "$WORK"
  local free_gb used_gb need
  free_gb="$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)"
  used_gb="$(du -s -BG "$WORK" 2>/dev/null | cut -f1 | tr -dc 0-9)"
  need=$(( DISK_BUDGET_GB - used_gb )); (( need < 0 )) && need=0
  (( free_gb >= need + 5 )) || die "only ${free_gb} GB free on $(df --output=target "$WORK" | tail -1); need ~$((need + 5)) GB (budget ${DISK_BUDGET_GB} GB + 5 GB margin)"
  log "  disk: ${free_gb} GB free, _work uses $(du -sh "$WORK" | cut -f1)"
}

# Run a command inside the builder image as the unprivileged user.
# $1 = network mode (none|bridge), rest = command.
in_container() {
  local net="$1"; shift
  docker run --rm --label "$LABEL" \
    --network "$net" \
    --user "$(id -u):$(id -g)" \
    --cap-drop ALL --security-opt no-new-privileges \
    --memory "$MEM_LIMIT" --memory-swap "$MEM_LIMIT" \
    -e JOBS="$JOBS" -e CUDA_JOBS="$CUDA_JOBS" \
    -e SOURCE_DATE_EPOCH="$BLENDER_COMMIT_EPOCH" \
    -e BLENDER_GB10_REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)" \
    -e BLENDER_GB10_REPO_DIRTY="$(git -C "$REPO" status --porcelain --untracked-files=all -- . ':!BUILD_STATE.md' | wc -l)" \
    -e BLENDER_GB10_IMAGE_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE")" \
    -e BLENDER_GB10_M2="${BLENDER_GB10_M2:-0}" \
    -v "$REPO:/repo:ro" \
    -v "$WORK:/work" \
    -w /work \
    "$IMAGE" "$@"
}

image() {
  require_clean_repo
  log "building toolchain image $IMAGE"
  # Classic builder: every layer, intermediate ones included, carries the project label
  # (LABEL is the first instruction), so clean-docker removes all of it, and no BuildKit
  # cache records are left behind in the shared build cache.
  DOCKER_BUILDKIT=0 docker build --label "$LABEL" \
    --build-arg BUILDER_UID="$(id -u)" --build-arg BUILDER_GID="$(id -g)" \
    -t "$IMAGE" -f "$REPO/Dockerfile" "$REPO"
  mkdir -p "$WORK/record"
  docker run --rm --label "$LABEL" --network none --user "$(id -u):$(id -g)" --cap-drop ALL \
    --security-opt no-new-privileges "$IMAGE" cat /etc/blender-gb10/dpkg-manifest.txt \
    > "$WORK/record/dpkg-manifest.txt"
  if ! diff -u "$REPO/deps/dpkg-manifest.lock" "$WORK/record/dpkg-manifest.txt" > "$WORK/record/dpkg-manifest.diff"; then
    if [[ "${BLENDER_GB10_STRICT_APT:-0}" == 1 ]]; then
      die "image package set differs from deps/dpkg-manifest.lock (see $WORK/record/dpkg-manifest.diff)"
    fi
    log "WARNING: image package set differs from deps/dpkg-manifest.lock ($(grep -c '^[+-][^+-]' "$WORK/record/dpkg-manifest.diff") lines, see _work/record/dpkg-manifest.diff)"
  else
    log "  image package set matches deps/dpkg-manifest.lock"
  fi
}

fetch() {
  require_clean_repo
  log "fetching pinned sources (network enabled for this step only)"
  in_container bridge /repo/scripts/container/fetch.sh
  # Blender's deps builder downloads every package at configure time and checks the
  # hash pinned in versions.cmake (plus our sha256 table); this is the only networked
  # container step besides fetch.sh.
  in_container bridge /repo/scripts/container/deps.sh configure
}

deps() {
  require_clean_repo
  log "building dependencies (offline)"
  # DEPS_WAVES: space-separated wave names (see scripts/container/deps.sh); default milestone 1.
  # shellcheck disable=SC2086
  in_container none /repo/scripts/container/deps.sh build ${DEPS_WAVES:-}
}

blender() {
  require_clean_repo
  log "building Blender (offline)"
  in_container none /repo/scripts/container/blender.sh
}

install_host() {
  local src="$WORK/out/blender-${BLENDER_VERSION}"
  [[ -x "$src/blender" ]] || die "no build output at $src"
  # rsync --delete below: only ever operate on a directory that is clearly ours.
  [[ "$(basename "$PREFIX")" == blender-gb10-* ]] || die "refusing to install into '$PREFIX' (basename must match blender-gb10-*)"
  if [[ -e "$PREFIX" && ! -f "$PREFIX/.blender-gb10-install" ]]; then
    [[ -z "$(ls -A "$PREFIX" 2>/dev/null)" ]] || die "refusing to overwrite '$PREFIX': it is not empty and has no .blender-gb10-install marker"
  fi
  log "installing portable tree to $PREFIX"
  mkdir -p "$PREFIX" "$(dirname "$LAUNCHER")"
  chmod -R u+w "$PREFIX"
  rsync -a --delete "$src/" "$PREFIX/"
  echo "blender-gb10 portable install; managed by $REPO/build.sh" > "$PREFIX/.blender-gb10-install"
  # The installed tree is read-only: nothing (Python bytecode caches, add-on installs, ...)
  # can modify it at run time. build.sh re-enables writes only to replace it.
  chmod -R a-w "$PREFIX"
  ln -sfn "$PREFIX/blender" "$LAUNCHER"
  log "  launcher: $LAUNCHER -> $PREFIX/blender"
}

verify() { "$REPO/verify.sh"; }

# Remove intermediate build trees that are not needed to rebuild Blender itself.
prune() {
  log "pruning intermediates"
  rm -rf "${WORK:?}/build/deps" "${WORK:?}/build/blender"
}

clean_docker() {
  log "removing Docker artifacts created by this project (label $LABEL + the pinned base image)"
  docker ps -aq --filter "label=$LABEL" | xargs -r docker rm -f
  docker images -aq --filter "label=$LABEL" | sort -u | xargs -r docker rmi -f
  # The base image is pulled by digest only for this project.
  docker image rm "$BASE_IMAGE" 2>/dev/null || true
}

main() {
  local steps=("$@")
  [[ ${#steps[@]} -gt 0 ]] || steps=(all)
  for s in "${steps[@]}"; do
    case "$s" in
      preflight) preflight ;;
      image) image ;;
      fetch) fetch ;;
      deps) deps ;;
      blender) blender ;;
      install) install_host ;;
      verify) verify ;;
      prune) prune ;;
      clean-docker) clean_docker ;;
      all) preflight; image; fetch; deps; blender; install_host; verify ;;
      *) die "unknown step '$s'" ;;
    esac
  done
}
main "$@"
