#!/usr/bin/env bash
# check_portable.sh <tree> [probe.py]
# Run ON THE HOST. Exit 0 only if:
#  S1 every RPATH/RUNPATH in the tree is $ORIGIN-relative (no absolute build/container path);
#  S2 host `ldd` (clean env, no LD_LIBRARY_PATH) of every ELF has no "not found" / "version ... not found";
#  S3 every resolved dependency is inside <tree>, or is a HOST_ALLOW_RE soname in a host system dir;
#  S4 nothing resolves under a forbidden prefix (/usr/local, /opt, /home, ...);
#  R1 (runtime, LD_DEBUG) every object actually mapped while running a probe (includes dlopen:
#     libcuda, libnvoptix, OIDN devices, Vulkan ICD, wayland) is inside <tree> or in a host system
#     dir, never under a forbidden prefix, and no bundled soname is ALSO loaded from the host;
#  R2 libcuda.so.1 and libnvoptix.so.1 were loaded from the host driver dir.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/host_allow.sh"
T=$(realpath "$1"); PROBE=${2:-$here/probe_cycles_devices.py}
fail=0; err() { echo "FAIL: $*"; fail=1; }
is_elf() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(head -c4 "$1" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ]; }
CLEAN_ENV=(env -i HOME="$HOME" PATH=/usr/bin:/bin USER="${USER:-}" DISPLAY="${DISPLAY:-}" TMPDIR="${TMPDIR:-/tmp}" \
           WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}")
# Pass through the verify.sh sandboxing of Blender user dirs and driver caches (no LD_* vars).
for v in BLENDER_USER_CONFIG BLENDER_USER_SCRIPTS BLENDER_USER_DATAFILES BLENDER_USER_EXTENSIONS \
         BLENDER_USER_RESOURCES CUDA_CACHE_PATH OPTIX_CACHE_PATH __GL_SHADER_DISK_CACHE_PATH XDG_CACHE_HOME; do
  [ -n "${!v:-}" ] && CLEAN_ENV+=("$v=${!v}")
done

n=0
while IFS= read -r -d '' f; do
  is_elf "$f" || continue; n=$((n+1))
  # S1
  while read -r rp; do
    IFS=: read -ra parts <<<"$rp"
    for p in "${parts[@]}"; do [[ $p == '$ORIGIN'* ]] || err "S1 $f has non-\$ORIGIN rpath entry '$p'"; done
  done < <(readelf -d "$f" 2>/dev/null | sed -n 's/.*(R\(UN\)\{0,1\}PATH).*\[\(.*\)\]/\2/p')
  readelf -d "$f" 2>/dev/null | grep -q '(NEEDED)' || continue
  out=$("${CLEAN_ENV[@]}" ldd "$f" 2>&1)
  # S2
  grep -E 'not found' <<<"$out" | while read -r l; do echo "FAIL: S2 $f: $l"; done
  grep -qE 'not found' <<<"$out" && fail=1
  # S3/S4
  while read -r so arrow path _; do
    [ "$arrow" = "=>" ] || continue
    [ "$path" = "not" ] && continue
    rpth=$(realpath "$path")
    case "$rpth" in "$T"/*) continue ;; esac
    [[ $rpth =~ $FORBIDDEN_PREFIX_RE ]] && { err "S4 $f: $so -> $rpth (forbidden prefix)"; continue; }
    if [[ $so =~ $HOST_ALLOW_RE ]] && [[ $(dirname "$rpth") =~ $HOST_SYS_DIR_RE ]]; then continue; fi
    # a transitive dep of a host-allowed lib is fine only if it lives in a host system dir
    [[ $(dirname "$rpth") =~ $HOST_SYS_DIR_RE ]] && ! grep -q "(NEEDED).*\[$so\]" <(readelf -d "$f") && continue
    err "S3 $f: direct dep $so resolves to host $rpth but is not host-allowed (must be bundled)"
  done <<<"$out"
done < <(find "$T" -type f -print0)
echo "static: checked $n ELF files"

# Runtime check with the loader's own trace (catches dlopen).
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check_portable.XXXXXX")
"${CLEAN_ENV[@]}" LD_DEBUG=files LD_DEBUG_OUTPUT="$tmp/ld" \
  "$T/blender" -b --factory-startup --python-exit-code 3 --python "$PROBE" >"$tmp/probe.log" 2>&1
rc=$?; echo "probe exit=$rc (log $tmp/probe.log)"; [ $rc -eq 0 ] || err "R0 probe failed rc=$rc"
paths=$(cat "$tmp"/ld.* 2>/dev/null | sed -n 's/.*calling init: \(.*\)$/\1/p' | sort -u)
for p in $paths; do
  rp=$(realpath "$p" 2>/dev/null || echo "$p")
  case "$rp" in "$T"/*) continue ;; esac
  [[ $rp =~ $FORBIDDEN_PREFIX_RE ]] && { err "R1 loaded from forbidden prefix: $rp"; continue; }
  [[ $(dirname "$rp") =~ $HOST_SYS_DIR_RE ]] || err "R1 loaded from unexpected dir: $rp"
  b=$(basename "$p"); [ -e "$T/lib/$b" ] && err "R1 $b loaded from host ($rp) although bundled"
done
grep -qE 'calling init: (/usr)?/lib/aarch64-linux-gnu/libcuda\.so(\.1)?$' "$tmp"/ld.* || err "R2 libcuda.so.1 not loaded from host driver dir"
grep -qE 'calling init: (/usr)?/lib/aarch64-linux-gnu/libnvoptix\.so\.1$' "$tmp"/ld.* || err "R2 libnvoptix.so.1 not loaded from host driver dir"
echo "runtime: $(echo "$paths" | wc -l) objects initialised; in-tree: $(echo "$paths" | grep -c "^$T/")"
[ $fail -eq 0 ] && echo "PORTABLE-CHECK: PASS" || echo "PORTABLE-CHECK: FAIL"
exit $fail
