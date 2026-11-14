#!/usr/bin/env bash
# Rewrite DT_NEEDED entries of the freshly linked QEMU/qemu-img shared objects
# so they match the file names shipped in jniLibs/arm64-v8a.
#
# The prebuilt libraries in $PREFIX/lib have real sonames (libglib-2.0.so.0,
# libpixman-1.so.0, ...) but Android packages the AAR-renamed copies
# (libglib-2.0.so, libpixman-1.so, ...).  Link against the sonames, then patch
# the consumers here.
#
# Usage: scripts/fix-needed.sh <shared-object> [<shared-object> ...]
set -eu

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

if [ "$PATCHELF" = false ]; then
    echo "error: patchelf not found (install it, e.g. apt install patchelf)" >&2
    exit 1
fi

for so in "$@"; do
    for pair in \
        libglib-2.0.so.0:libglib-2.0.so \
        libgio-2.0.so.0:libgio-2.0.so \
        libgobject-2.0.so.0:libgobject-2.0.so \
        libgmodule-2.0.so.0:libgmodule-2.0.so \
        libpixman-1.so.0:libpixman-1.so \
        libintl.so.8:libintl.so \
        libpcre2-8.so.0:libpcre2-8.so \
        libz.so.1:libz.so \
        libzstd.so.1:libzstd.so \
        libslirp.so.0:libslirp.so \
        libSDL2-2.0.so.0:libSDL2.so
    do
        from=${pair%%:*}
        to=${pair##*:}
        # --replace-needed is a no-op error when the entry is absent; check first.
        if "$PATCHELF" --print-needed "$so" | grep -qx "$from"; then
            "$PATCHELF" --replace-needed "$from" "$to" "$so"
        fi
    done
    echo "patched $so"
done
