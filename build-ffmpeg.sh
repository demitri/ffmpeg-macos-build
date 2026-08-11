#!/usr/local/bash/bin/bash
# Configure, build and stage ffmpeg 9.0 against the static codec deps.
#
# ffmpeg is configured with its real final prefix (/usr/local/ffmpeg-9.0) and
# installed into a DESTDIR stage, because /usr/local is root-owned here and
# sudo is password-gated. One `sudo rsync` publishes it afterwards.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${FFBUILD_WORKDIR:-$SELF/work}"

# Override these to build a different FFmpeg release.
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0}"
FF="${FFMPEG_SRC:-/usr/local/src/ffmpeg-$FFMPEG_VERSION}"
DEPS="$WORKDIR/prefix"
STAGE="$WORKDIR/ffmpeg-stage"
PREFIX="${FFMPEG_PREFIX:-/usr/local/ffmpeg-$FFMPEG_VERSION}"

[ -d "$FF" ] || { echo "FATAL: no FFmpeg source at $FF" >&2; exit 1; }
JOBS="$(sysctl -n hw.ncpu)"

export PATH="/usr/local/pkg-config-0.29.2/bin:/usr/local/make-4.4.1/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
unset LDFLAGS CPPFLAGS CFLAGS CXXFLAGS PYTHONPATH DYLD_LIBRARY_PATH LD_LIBRARY_PATH || true
case ":$PATH:" in *anaconda*) echo "FATAL: anaconda in PATH" >&2; exit 1;; esac

export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig:/usr/local/zlib/lib/pkgconfig:/usr/local/openssl/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1).0"

# Every external library we require. If configure enables fewer than this,
# the build is wrong and must fail rather than quietly ship a weaker ffmpeg.
REQUIRED=(
    libx264 libx265 libvpx libdav1d libsvtav1 libaom
    libopus libmp3lame libvorbis libfdk_aac
    libass libfreetype libfontconfig libharfbuzz
    libwebp libzimg
    videotoolbox audiotoolbox openssl
)

cd "$FF"
make distclean >/dev/null 2>&1 || true

./configure \
    --prefix="$PREFIX" \
    --enable-gpl \
    --enable-nonfree \
    --enable-libx264 --enable-libx265 --enable-libvpx \
    --enable-libdav1d --enable-libsvtav1 --enable-libaom \
    --enable-libopus --enable-libmp3lame --enable-libvorbis --enable-libfdk-aac \
    --enable-libass --enable-libfreetype --enable-libfontconfig --enable-libharfbuzz \
    --enable-libwebp --enable-libzimg \
    --enable-videotoolbox --enable-audiotoolbox \
    --enable-openssl \
    --pkg-config-flags=--static \
    --disable-ffplay \
    --extra-cflags="-I$DEPS/include" \
    --extra-ldflags="-L$DEPS/lib"

# --- assert every required component actually got enabled -------------------
missing=()
for c in "${REQUIRED[@]}"; do
    if ! grep -qi "^CONFIG_${c}=yes" ffbuild/config.mak; then missing+=("$c"); fi
done
if [ "${#missing[@]}" -ne 0 ]; then
    echo "FATAL: configure did not enable: ${missing[*]}" >&2
    exit 1
fi
echo "=== all ${#REQUIRED[@]} required components enabled ==="

make -j"$JOBS"
rm -rf "$STAGE"
make install DESTDIR="$STAGE"

echo
echo "=== BUILD COMPLETE ==="
"$STAGE$PREFIX/bin/ffmpeg" -version
