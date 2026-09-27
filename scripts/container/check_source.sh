#!/usr/bin/env bash
# Assert that /work/src/blender is exactly BLENDER_COMMIT + /repo/patches/*.patch:
#  * HEAD is the pinned commit,
#  * there are no untracked files (build outputs live outside the tree),
#  * the working-tree diff equals the diff produced by applying the committed patches
#    to a scratch index of the pinned commit.
# Prints the sha256 of that diff (recorded in the install tree). Exit 1 on mismatch.
set -euo pipefail
source /repo/scripts/pins.env
cd /work/src/blender
fail() { echo "SOURCE-CHECK: FAIL: $*" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$BLENDER_COMMIT" ]] || fail "HEAD $(git rev-parse HEAD) != pinned $BLENDER_COMMIT"
untracked="$(git ls-files --others --exclude-standard --directory | head -5)"
[[ -z "$untracked" ]] || fail "untracked files in the source tree: $untracked"
tmp="$(mktemp -d /work/tmp.check_source.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp/index"
git read-tree "$BLENDER_COMMIT"
for p in /repo/patches/*.patch; do git apply --cached "$p"; done
git diff --cached "$BLENDER_COMMIT" > "$tmp/expected.diff"
unset GIT_INDEX_FILE
git diff "$BLENDER_COMMIT" > "$tmp/actual.diff"
cmp -s "$tmp/expected.diff" "$tmp/actual.diff" || { diff -u "$tmp/expected.diff" "$tmp/actual.diff" | head -40 >&2; fail "tree differs from pinned commit + committed patches"; }
sha="$(sha256sum < "$tmp/actual.diff" | cut -d' ' -f1)"
echo "SOURCE-CHECK: OK blender=$BLENDER_COMMIT patches-diff-sha256=$sha"
