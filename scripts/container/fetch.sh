#!/usr/bin/env bash
# Fetch pinned sources into /work/src (runs in the builder container, unprivileged,
# network enabled). Every git source is fetched by exact commit and verified; every
# file download is verified against a sha256 before use.
set -euo pipefail
source /repo/scripts/pins.env

SRC=/work/src
mkdir -p "$SRC" /work/packages

# git_pin <dir> <url> <commit>: shallow-fetch exactly <commit>; refuse anything else.
git_pin() {
  local dir="$1" url="$2" commit="$3"
  if [[ -d "$dir/.git" ]]; then
    local head
    head="$(git -C "$dir" rev-parse HEAD)"
    [[ "$head" == "$commit" ]] || { echo "ERROR: $dir is at $head, expected $commit" >&2; exit 1; }
    echo "ok: $dir @ $commit"
    return
  fi
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  git -C "$dir" -c protocol.version=2 fetch --depth 1 --no-tags origin "$commit"
  git -C "$dir" checkout -q --detach FETCH_HEAD
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]] || { echo "ERROR: commit mismatch for $url" >&2; exit 1; }
  echo "fetched: $dir @ $commit"
}

git_pin "$SRC/blender"   "$BLENDER_GIT_URL" "$BLENDER_COMMIT"
git_pin "$SRC/optix-dev" "$OPTIX_GIT_URL"   "$OPTIX_COMMIT"
[[ -z "$(git -C "$SRC/optix-dev" status --porcelain --untracked-files=all)" ]] \
  || { echo "ERROR: $SRC/optix-dev has local modifications" >&2; exit 1; }
[[ "$(git -C "$SRC/blender" log -1 --format=%ct)" == "$BLENDER_COMMIT_EPOCH" ]] \
  || { echo "ERROR: BLENDER_COMMIT_EPOCH does not match the commit time" >&2; exit 1; }

# Reset the Blender tree to the pin and apply this repository's patches (verified).
/repo/scripts/container/apply_patches.sh

# Pure-python wheels for Blender's bundled Python site-packages, hash-locked.
# (Replaces the upstream unhashed `pip install --no-binary :all:` from PyPI.)
mkdir -p /work/packages/wheels
while read -r name url sha; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  f="/work/packages/wheels/$(basename "$url")"
  if [[ ! -f "$f" ]] || ! echo "$sha  $f" | sha256sum -c --quiet - 2>/dev/null; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$f.tmp" "$url"
    echo "$sha  $f.tmp" | sha256sum -c --quiet - || { echo "ERROR: sha256 mismatch for $url" >&2; rm -f "$f.tmp"; exit 1; }
    mv "$f.tmp" "$f"
  fi
done < /repo/deps/python-wheels.lock
# Drop wheels that are no longer in the lock (e.g. after a version bump).
for f in /work/packages/wheels/*.whl; do
  grep -q "/$(basename "$f") " /repo/deps/python-wheels.lock || rm -f "$f"
done
echo "wheels verified: $(ls /work/packages/wheels | wc -l)"
