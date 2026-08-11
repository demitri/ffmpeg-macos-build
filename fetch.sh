#!/usr/local/bash/bin/bash
# Fetch all ffmpeg 9.0 codec dependency sources.
# Fails loudly on any download or extraction error - never skips a source.
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${FFBUILD_WORKDIR:-$SELF/work}"
SRC="$WORKDIR"
TARBALLS="$SRC/tarballs"
mkdir -p "$TARBALLS"
cd "$SRC"

get() {  # get <url> <tarball-name> <expected-extract-dir>
    local url="$1" tb="$2" dir="$3"
    if [ -d "$dir" ]; then echo "== $dir already extracted"; return 0; fi
    if [ ! -f "$TARBALLS/$tb" ]; then
        echo "== downloading $tb"
        curl -fSL --retry 3 --max-time 600 -o "$TARBALLS/$tb.part" "$url"
        mv "$TARBALLS/$tb.part" "$TARBALLS/$tb"
    fi
    echo "== extracting $tb -> $dir"
    tar xf "$TARBALLS/$tb"
    [ -d "$dir" ] || { echo "FATAL: expected dir '$dir' not created by $tb" >&2; exit 1; }
}

clone() {  # clone <url> <branch-or-tag> <dir>
    local url="$1" ref="$2" dir="$3"
    if [ -d "$dir" ]; then echo "== $dir already cloned"; return 0; fi
    echo "== cloning $dir ($ref)"
    git clone --depth 1 --branch "$ref" "$url" "$dir"
}

# --- font / text stack ---
get "https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz" \
    libpng-1.6.58.tar.xz libpng-1.6.58
get "https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz" \
    freetype-2.14.3.tar.xz freetype-2.14.3
get "https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz" \
    fribidi-1.0.16.tar.xz fribidi-1.0.16
get "https://github.com/harfbuzz/harfbuzz/releases/download/14.3.0/harfbuzz-14.3.0.tar.xz" \
    harfbuzz-14.3.0.tar.xz harfbuzz-14.3.0
get "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.18.3/fontconfig-2.18.3.tar.bz2" \
    fontconfig-2.18.3.tar.bz2 fontconfig-2.18.3
get "https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz" \
    libass-0.17.5.tar.xz libass-0.17.5

# --- video codecs ---
clone "https://code.videolan.org/videolan/x264.git" stable x264
get "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.2.tar.gz" \
    x265_4.2.tar.gz x265_4.2
get "https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz" \
    libvpx-1.16.0.tar.gz libvpx-1.16.0
get "https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2" \
    dav1d-1.5.4.tar.bz2 dav1d-1.5.4
get "https://github.com/AOMediaCodec/SVT-AV1/archive/refs/tags/v4.2.0.tar.gz" \
    SVT-AV1-4.2.0.tar.gz SVT-AV1-4.2.0
clone "https://aomedia.googlesource.com/aom" v3.14.1 aom-3.14.1
get "https://github.com/webmproject/libwebp/archive/refs/tags/v1.6.0.tar.gz" \
    libwebp-1.6.0.tar.gz libwebp-1.6.0

# --- audio codecs ---
get "https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz" \
    opus-1.5.2.tar.gz opus-1.5.2
get "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" \
    lame-3.100.tar.gz lame-3.100
get "https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz" \
    libogg-1.3.6.tar.xz libogg-1.3.6
get "https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz" \
    libvorbis-1.3.7.tar.xz libvorbis-1.3.7

# --- scaling ---
get "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz" \
    zimg-3.0.6.tar.gz zimg-release-3.0.6

echo
echo "=== ALL SOURCES FETCHED ==="
ls -d "$SRC"/*/ | grep -v tarballs
