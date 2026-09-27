#!/usr/bin/env bash
# Reset the Blender tree to the pinned commit, remove anything untracked, apply
# /repo/patches/*.patch in order, then verify the tree (check_source.sh).
# Destructive by design: local edits in /work/src/blender are discarded.
set -euo pipefail
source /repo/scripts/pins.env
cd /work/src/blender
git reset -q --hard "$BLENDER_COMMIT"
git clean -q -ffdx
for p in /repo/patches/*.patch; do
  git apply --check "$p" || { echo "ERROR: patch does not apply to the pinned tree: $p" >&2; exit 1; }
  git apply "$p"
  echo "applied: $(basename "$p")"
done
/repo/scripts/container/check_source.sh
