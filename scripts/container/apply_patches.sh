#!/usr/bin/env bash
# Apply /repo/patches/*.patch to the pinned Blender tree, idempotently.
# A patch that is already applied (reverse-applies cleanly) is skipped; a patch that
# neither applies nor reverse-applies is a hard error.
set -euo pipefail
cd /work/src/blender
for p in /repo/patches/*.patch; do
  if git apply --check -R "$p" 2>/dev/null; then
    echo "already applied: $(basename "$p")"
  elif git apply --check "$p"; then
    git apply "$p"
    echo "applied: $(basename "$p")"
  else
    echo "ERROR: patch does not apply: $p" >&2
    exit 1
  fi
done
