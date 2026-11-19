#!/usr/bin/env bash
# Rewrite a PGO profile so its source paths match the current build layout.
#
#   scripts/prepare-pgo-profile.sh <profile-in> <profile-out>
#
# LLVM records functions with internal linkage as "<source-path>;<function>",
# where the path is the one meson passes to the compiler -- relative to the
# build directory.  The committed profile was trained with the repository at
# <workspace>/limbo-dontknowhy and QEMU_BUILD at <workspace>/build/qemu-build,
# so its keys start with:
#
#   ../../limbo-dontknowhy/limbo-android-lib/src/main/jni/qemu/
#
# A fresh clone under any other name/location produces different keys and the
# static functions silently fall back to unprofiled code (external symbols are
# matched by mangled name and keep working).  This script maps the QEMU
# source-root part of every key onto the path meson will use now:
#
#   <relative path from $QEMU_BUILD to $QEMU_SRC>/
#
# Generated files (block/block-gen.c, trace/...) are already build-relative and
# are left untouched.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <profile-in> <profile-out>" >&2
    exit 2
fi

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

SRC_PROFILE=$1
OUT_PROFILE=$2
QEMU_SRC=${QEMU_SRC:-$JNI_ROOT/qemu}
QEMU_BUILD=${QEMU_BUILD:-$BUILD/qemu-build}
PROFDATA=$TOOLCHAIN/bin/llvm-profdata

if [ ! -f "$SRC_PROFILE" ]; then
    echo "error: profile not found: $SRC_PROFILE" >&2
    exit 1
fi
if [ ! -x "$PROFDATA" ]; then
    echo "error: llvm-profdata not found: $PROFDATA" >&2
    exit 1
fi

# realpath -m works even when the build directory has not been created yet.
REL_SRC=$(realpath -m --relative-to="$QEMU_BUILD" "$QEMU_SRC")
MARKER=/limbo-android-lib/src/main/jni/qemu/

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$PROFDATA" merge --text "$SRC_PROFILE" -o "$TMP/in.proftext"

awk -v rel="$REL_SRC" -v marker="$MARKER" '
    {
        if (index($0, ";") > 0) {
            i = index($0, marker)
            if (i > 0) {
                print rel "/" substr($0, i + length(marker))
                n++
                next
            }
        }
        print
    }
    END {
        if (n == 0) {
            print "error: no QEMU source-path keys found in profile" > "/dev/stderr"
            exit 1
        }
        printf "rewrote %d profile keys to %s/\n", n, rel > "/dev/stderr"
    }
' "$TMP/in.proftext" > "$TMP/out.proftext"

mkdir -p "$(dirname "$OUT_PROFILE")"
"$PROFDATA" merge "$TMP/out.proftext" -o "$OUT_PROFILE"
echo "wrote $OUT_PROFILE"
