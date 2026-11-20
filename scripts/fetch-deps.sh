#!/usr/bin/env bash
# Download the source tarballs that the native build needs into $DEPS.
#
#   scripts/fetch-deps.sh
#
# Downloads land in $DEPS, which defaults to the repository's jni/ directory
# (see scripts/env.sh), so the tarballs sit next to the trees extracted from
# them.  Re-running is cheap: existing files are skipped.
# Set HTTP_PROXY/HTTPS_PROXY or GH_PROXY (e.g. https://gh-proxy.org/) if
# GitHub is not reachable directly.
set -euo pipefail

APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$APP_ROOT/scripts/env.sh"

mkdir -p "$DEPS"
GH_PROXY=${GH_PROXY:-}

# name|url|sha256 (empty sha256 = not verified)
FILES=(
  "qemu-11.1.3.tar.xz|https://download.qemu.org/qemu-11.1.3.tar.xz|5a8289c7940dc77d3873c81a6c29ba3afe1446fc9d36e77fa1658cdbecb84b22"
  "glib-2.90.1.tar.xz|https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz|93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396"
  "pixman-0.46.4.tar.xz|https://cairographics.org/releases/pixman-0.46.4.tar.xz|a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239"
  "libffi-3.4.3.tar.gz|https://github.com/libffi/libffi/releases/download/v3.4.3/libffi-3.4.3.tar.gz|4416dd92b6ae8fcb5b10421e711c4d3cb31203d77521a77d85d0102311e6c3b8"
  "SDL2-2.32.10.tar.gz|https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz|5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
  "zlib-ng-2.3.3.tar.gz|https://github.com/zlib-ng/zlib-ng/archive/refs/tags/2.3.3.tar.gz|f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1"
  "zstd-1.5.7.tar.gz|https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz|eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3"
  "pcre2-10.49.tar.gz|https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.gz|929f0b20e62879252a15886b06c89f1edef61a363cbd5826fb041080a5e557ae"
  "libiconv-1.18.tar.gz|https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz|3b08f5f4f9b4eb82f151a7040bfd6fe6c6fb922efe4b1659c66ea933276965e8"
  "proxy-libintl-0.5.tar.gz|https://github.com/frida/proxy-libintl/archive/refs/tags/0.5.tar.gz|f7a1cbd7579baaf575c66f9d99fb6295e9b0684a28b095967cfda17857595303"
  "libslirp-4.9.7.tar.gz|https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v4.9.7/libslirp-v4.9.7.tar.gz|"
)

for entry in "${FILES[@]}"; do
    IFS='|' read -r name url sha <<< "$entry"
    dst=$DEPS/$name
    if [ -f "$dst" ]; then
        echo "have   $name"
        continue
    fi
    # The libslirp git archive is named libslirp-v4.9.7/...; rename on extract.
    url2=$url
    case $url in
        https://github.com/*) [ -n "$GH_PROXY" ] && url2="${GH_PROXY%/}/$url" ;;
    esac
    echo "fetch  $name"
    curl -fL --retry 3 -o "$dst.part" "$url2"
    if [ -n "$sha" ]; then
        echo "$sha  $dst.part" | sha256sum -c - >/dev/null
    fi
    mv "$dst.part" "$dst"
done

# libslirp from gitlab extracts as libslirp-v4.9.7; normalise to the name the
# Makefile expects.
if [ -f "$DEPS/libslirp-v4.9.7.tar.gz" ] && [ ! -f "$DEPS/libslirp-4.9.7.tar.gz" ]; then
    mv "$DEPS/libslirp-v4.9.7.tar.gz" "$DEPS/libslirp-4.9.7.tar.gz"
fi
echo "deps are in $DEPS"
