#!/usr/bin/env bash
# Host-side driver for the containerised Blender 5.2.2 build for NVIDIA DGX Spark (GB10).
#
# Security model (see README.md):
#   * never uses sudo and refuses to run as root;
#   * every compile step runs inside the pinned builder image as the unprivileged
#     `builder` user (host UID/GID), with all capabilities dropped and
#     no-new-privileges; compile steps run with --network none;
#   * nothing is written outside this repository (_work/ scratch), the Docker
#     artifacts it creates (all labelled org.zebeth.blender-gb10=1),
#     ~/.local/opt/blender-gb10-<ver> and the ~/.local/bin/blender-gb10 symlink.
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
  docker info >/dev/null 2>&1 || die "docker daemon not reachable (is your user in the docker group?)"
  docker run --rm --label "$LABEL" --gpus all "$BASE_IMAGE" nvidia-smi -L >/dev/null 2>&1 \
    || die "'docker run --gpus all' failed: install/configure nvidia-container-toolkit"
  mkdir -p "$WORK"
  local free_gb
  free_gb="$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)"
  local need=$(( DISK_BUDGET_GB - $(du -s -BG "$WORK" 2>/dev/null | cut -f1 | tr -dc 0-9) ))
  (( need < 0 )) && need=0
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
    -v "$REPO:/repo:ro" \
    -v "$WORK:/work" \
    -w /work \
    "$IMAGE" "$@"
}

image() {
  log "building toolchain image $IMAGE"
  docker build --label "$LABEL" \
    --build-arg BUILDER_UID="$(id -u)" --build-arg BUILDER_GID="$(id -g)" \
    -t "$IMAGE" -f "$REPO/Dockerfile" "$REPO"
  mkdir -p "$WORK/record"
  docker run --rm --label "$LABEL" "$IMAGE" cat /etc/blender-gb10/dpkg-manifest.txt \
    > "$WORK/record/dpkg-manifest.txt"
}

fetch() {
  log "fetching pinned sources (network enabled for this step only)"
  in_container bridge /repo/scripts/container/fetch.sh
  # Blender's deps builder downloads every package at configure time and checks the
  # hash pinned in versions.cmake; this configure is the only networked container step.
  in_container bridge /repo/scripts/container/deps.sh configure
}

deps() {
  log "building dependencies (offline)"
  # DEPS_WAVES: space-separated wave names (see scripts/container/deps.sh); default milestone 1.
  # shellcheck disable=SC2086
  in_container none /repo/scripts/container/deps.sh build ${DEPS_WAVES:-}
}

blender() {
  log "building Blender (offline)"
  in_container none /repo/scripts/container/blender.sh
}

install_host() {
  log "installing portable tree to $PREFIX"
  local src="$WORK/out/blender-${BLENDER_VERSION}"
  [[ -x "$src/blender" ]] || die "no build output at $src"
  mkdir -p "$(dirname "$PREFIX")" "$(dirname "$LAUNCHER")"
  rsync -a --delete "$src/" "$PREFIX/"
  ln -sfn "$PREFIX/blender" "$LAUNCHER"
  log "  launcher: $LAUNCHER -> $PREFIX/blender"
}

verify() { "$REPO/verify.sh"; }

# Remove intermediate build trees that are not needed to rebuild Blender itself.
prune() {
  log "pruning intermediates"
  rm -rf "$WORK/build/deps" "$WORK/build/blender"
}

clean_docker() {
  log "removing Docker artifacts created by this project (label $LABEL only)"
  docker ps -aq --filter "label=$LABEL" | xargs -r docker rm -f
  docker images -q --filter "label=$LABEL" | sort -u | xargs -r docker rmi -f
  docker builder prune -f --filter "label=$LABEL" || true
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
