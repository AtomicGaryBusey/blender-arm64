#!/usr/bin/env bash
# cwd_injection.sh <tree> <launcher-symlink> <workdir>
# Regression test for library injection from the current directory: builds a fake
# libXau.so.6 (a real dependency of libX11) whose constructor writes a marker, then runs
# the launcher symlink and the binary from that directory with LD_LIBRARY_PATH unset and
# set-but-empty handling left to the tree. PASS = the marker is never written and
# Blender's LD_LIBRARY_PATH-mangling `blender-launcher` script is not shipped.
set -uo pipefail
T=$(realpath "$1"); L=$2; W=$(realpath -m "$3"); mkdir -p "$W"
CC=${CC:-$(command -v cc || command -v gcc || true)}
fail=0
if [ -e "$T/blender-launcher" ]; then echo "FAIL: $T/blender-launcher is present"; fail=1; fi
if [ -z "$CC" ]; then echo "SKIP: no C compiler on the host to build the probe library"; exit $fail; fi
cat > "$W/inj.c" <<C
#include <fcntl.h>
#include <unistd.h>
__attribute__((constructor)) static void mark(void) {
  int fd = open("$W/INJECTED", O_WRONLY | O_CREAT, 0644); if (fd >= 0) close(fd); }
void XauDisposeAuth(void *a) {} void *XauGetBestAuthByAddr() { return 0; }
char *XauFileName(void) { return 0; } void *XauReadAuth(void *f) { return 0; }
C
"$CC" -shared -fPIC -o "$W/libXau.so.6" "$W/inj.c" || { echo "SKIP: probe library did not compile"; exit $fail; }
for prog in "$L" "$T/blender"; do
  rm -f "$W/INJECTED"
  ( cd "$W" && env -u LD_LIBRARY_PATH -u LD_PRELOAD "$prog" --version >/dev/null 2>&1 )
  if [ -e "$W/INJECTED" ]; then echo "FAIL: $prog loaded ./libXau.so.6 from the current directory"; fail=1
  else echo "PASS: $prog does not load libraries from the current directory"; fi
done
exit $fail
