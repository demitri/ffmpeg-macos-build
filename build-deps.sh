#!/usr/local/bash/bin/bash
# Build all ffmpeg 9.0 codec dependencies as static libraries.
#
# All packages install into one self-contained prefix under this source tree.
# Because every codec lib is static (.a), it is linked *into* the ffmpeg binary,
# so this prefix never appears at runtime and needs no privileged install.
# Only ffmpeg itself is destined for /usr/local (which is root-owned here, with
# password-gated sudo, so that one install is staged for a single sudo step).
#
# Anaconda is deliberately absent from PATH, PKG_CONFIG_PATH and all -I/-L
# flags. meson is invoked by absolute path purely as a build tool (it emits
# ninja files and links nothing), so no anaconda code enters any artifact.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${FFBUILD_WORKDIR:-$SELF/work}"
SRC="$WORKDIR"
DEPS="$SRC/prefix"
LOGS="$SRC/logs"
JOBS="$(sysctl -n hw.ncpu)"

# --- anaconda-free toolchain ---------------------------------------------
export PATH="/usr/local/cmake-4.2.3/bin:/usr/local/pkg-config-0.29.2/bin:/usr/local/make-4.4.1/bin:/usr/local/autoconf-2.73/bin:/usr/local/automake-1.16.5/bin:/usr/local/libtool-2.5.4/bin:/usr/local/m4-1.4.21/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
MESON="/usr/local/anaconda/bin/meson"   # build tool only; nothing links to it
NINJA="$(command -v ninja)"
[ -x "$NINJA" ] || { echo "FATAL: ninja not found on PATH" >&2; exit 1; }
[ -x "$MESON" ] || { echo "FATAL: meson not found at $MESON" >&2; exit 1; }
MESON_VER="$("$MESON" --version)"
MESON_MIN="1.11.0"
if [ "$(printf '%s\n%s\n' "$MESON_MIN" "$MESON_VER" | sort -V | head -1)" != "$MESON_MIN" ]; then
    echo "FATAL: meson $MESON_VER < $MESON_MIN (fontconfig 2.18.3 requires it)" >&2; exit 1
fi

unset PKG_CONFIG_PATH LDFLAGS CPPFLAGS CFLAGS CXXFLAGS PYTHONPATH \
      DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH LD_LIBRARY_PATH || true

case ":$PATH:" in *:/usr/local/anaconda/bin:*)
    echo "FATAL: anaconda leaked into PATH" >&2; exit 1;; esac

# aclocal only searches automake's own share/aclocal, so libtool 2.5.4's m4
# macros (LT_INIT et al) are invisible to autoreconf without this. Any package
# whose autogen.sh runs autoreconf needs it.
export ACLOCAL_PATH="/usr/local/libtool-2.5.4/share/aclocal"

export MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1).0"

# All deps share one real, writable prefix, so pkg-config needs no sysroot
# trickery and system libs (zlib, openssl) resolve at their true paths.
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig:/usr/local/zlib/lib/pkgconfig:/usr/local/openssl/lib/pkgconfig"

mkdir -p "$DEPS" "$LOGS"

pfx() { echo "$DEPS"; }   # single shared prefix for all static deps
run() {  # run <pkgname> <shell-fn>
    local name="$1" fn="$2"
    if [ -f "$LOGS/$name.done" ]; then echo "== SKIP $name (already built)"; return 0; fi
    echo "== BUILD $name"
    ( set -euo pipefail; "$fn" ) \
        > "$LOGS/$name.log" 2>&1 \
        || { echo "FATAL: $name failed; see $LOGS/$name.log" >&2; tail -40 "$LOGS/$name.log" >&2; exit 1; }
    rm -f "$DEPS"/lib/*.la
    touch "$LOGS/$name.done"
    echo "   ok -> $(pfx "$name")"
}

# ---------------------------------------------------------------- font stack
b_libpng() {
    cd "$SRC/libpng-1.6.58"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx libpng-1.6.58)" --disable-shared --enable-static \
        --with-zlib-prefix=/usr/local/zlib
    make -j"$JOBS" && make install
}
b_freetype_pass1() {
    cd "$SRC/freetype-2.14.3"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx freetype-2.14.3)" --disable-shared --enable-static \
        --without-harfbuzz --with-brotli=no --with-bzip2=yes --with-png=yes
    make -j"$JOBS" && make install
}
b_fribidi() {
    cd "$SRC/fribidi-1.0.16"
    rm -rf _b && "$MESON" setup _b --prefix="$(pfx fribidi-1.0.16)" \
        --default-library=static --buildtype=release -Ddocs=false -Dbin=false
    "$NINJA" -C _b && "$NINJA" -C _b install
}
b_harfbuzz() {
    cd "$SRC/harfbuzz-14.3.0"
    rm -rf _b && "$MESON" setup _b --prefix="$(pfx harfbuzz-14.3.0)" \
        --default-library=static --buildtype=release \
        -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
        -Dicu=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled
    "$NINJA" -C _b && "$NINJA" -C _b install
}
b_freetype() {   # pass 2: now with harfbuzz for better autohinting
    cd "$SRC/freetype-2.14.3"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx freetype-2.14.3)" --disable-shared --enable-static \
        --with-harfbuzz=yes --with-brotli=no --with-bzip2=yes --with-png=yes
    make -j"$JOBS" && make install
}
b_fontconfig() {
    cd "$SRC/fontconfig-2.18.3"
    rm -rf _b && "$MESON" setup _b --prefix="$(pfx fontconfig-2.18.3)" \
        --default-library=static --buildtype=release \
        -Dxml-backend=expat -Dtests=disabled -Dtools=disabled -Ddoc=disabled -Dnls=disabled
    "$NINJA" -C _b && "$NINJA" -C _b install
}
b_libass() {
    cd "$SRC/libass-0.17.5"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx libass-0.17.5)" --disable-shared --enable-static
    make -j"$JOBS" && make install
}

# -------------------------------------------------------------- video codecs
b_x264() {
    cd "$SRC/x264"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx x264-stable)" --enable-static --enable-pic \
        --disable-cli --disable-opencl
    make -j"$JOBS" && make install
}
b_x265() {
    # 12-bit and 10-bit are built as static sublibraries and folded into the
    # 8-bit build, giving one libx265 with full bit-depth support.
    local S="$SRC/x265_4.2/source" P; P="$(pfx x265-4.2)"
    cd "$S"; rm -rf b12 b10 b8; mkdir -p b12 b10 b8
    cmake -S "$S" -B b12 -DCMAKE_INSTALL_PREFIX="$P" -DHIGH_BIT_DEPTH=ON \
        -DMAIN12=ON -DEXPORT_C_API=OFF -DENABLE_CLI=OFF -DENABLE_SHARED=OFF \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build b12 -j"$JOBS"
    cmake -S "$S" -B b10 -DCMAKE_INSTALL_PREFIX="$P" -DHIGH_BIT_DEPTH=ON \
        -DEXPORT_C_API=OFF -DENABLE_CLI=OFF -DENABLE_SHARED=OFF \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build b10 -j"$JOBS"
    cp b12/libx265.a b8/libx265_main12.a
    cp b10/libx265.a b8/libx265_main10.a
    cmake -S "$S" -B b8 -DCMAKE_INSTALL_PREFIX="$P" -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
        -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build b8 -j"$JOBS"
    cd b8
    mv libx265.a libx265_main.a
    # Must be Apple's libtool: it merges static archives. GNU libtool is first
    # on PATH here and rejects -static, so call the system one by full path.
    /usr/bin/libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a
    cmake --install .
}
b_libvpx() {
    cd "$SRC/libvpx-1.16.0"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx libvpx-1.16.0)" --disable-shared --enable-static \
        --disable-examples --disable-unit-tests --disable-tools --disable-docs \
        --enable-vp9-highbitdepth --enable-pic
    make -j"$JOBS" && make install
}
b_dav1d() {
    cd "$SRC/dav1d-1.5.4"
    rm -rf _b && "$MESON" setup _b --prefix="$(pfx dav1d-1.5.4)" \
        --default-library=static --buildtype=release -Denable_tools=false -Denable_tests=false
    "$NINJA" -C _b && "$NINJA" -C _b install
}
b_svtav1() {
    cd "$SRC/SVT-AV1-4.2.0"
    rm -rf _b
    cmake -S . -B _b -DCMAKE_INSTALL_PREFIX="$(pfx svt-av1-4.2.0)" \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build _b -j"$JOBS"
    cmake --install _b
}
b_aom() {
    cd "$SRC/aom-3.14.1"
    rm -rf _b
    cmake -S . -B _b -DCMAKE_INSTALL_PREFIX="$(pfx aom-3.14.1)" \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_EXAMPLES=OFF \
        -DENABLE_TESTS=OFF -DENABLE_TOOLS=OFF -DENABLE_DOCS=OFF \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build _b -j"$JOBS"
    cmake --install _b
}
b_libwebp() {
    # Built with cmake, not autotools: libwebp 1.6.0's configure.ac still calls
    # AC_PROG_LIBTOOL, which libtool 2.5.4 removed (it is the deprecated
    # spelling of LT_INIT). The cmake path is upstream-supported and installs
    # the same .pc files ffmpeg detects against.
    cd "$SRC/libwebp-1.6.0"
    rm -rf _b
    cmake -S . -B _b -DCMAKE_INSTALL_PREFIX="$(pfx libwebp-1.6.0)" \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
        -DWEBP_BUILD_LIBWEBPMUX=ON \
        -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_WEBPMUX=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_EXTRAS=OFF
    cmake --build _b -j"$JOBS"
    cmake --install _b
}

# -------------------------------------------------------------- audio codecs
b_fdkaac() {
    cd "$SRC/fdk-aac-2.0.3"
    make distclean >/dev/null 2>&1 || true
    ./autogen.sh
    ./configure --prefix="$(pfx fdk-aac-2.0.3)" --disable-shared --enable-static
    make -j"$JOBS" && make install
}
b_opus() {
    cd "$SRC/opus-1.5.2"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx opus-1.5.2)" --disable-shared --enable-static \
        --disable-doc --disable-extra-programs
    make -j"$JOBS" && make install
}
b_lame() {
    cd "$SRC/lame-3.100"
    make distclean >/dev/null 2>&1 || true
    # lame 3.100 ships a symbol that no longer exists; removing it is the
    # upstream-known fix, not an error suppression.
    if grep -q '^ *lame_init_old' include/libmp3lame.sym; then
        sed -i.bak '/^ *lame_init_old/d' include/libmp3lame.sym
    fi
    ./configure --prefix="$(pfx lame-3.100)" --disable-shared --enable-static \
        --enable-nasm=no --disable-frontend
    make -j"$JOBS" && make install
}
b_libogg() {
    cd "$SRC/libogg-1.3.6"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$(pfx libogg-1.3.6)" --disable-shared --enable-static
    make -j"$JOBS" && make install
}
b_libvorbis() {
    cd "$SRC/libvorbis-1.3.7"
    make distclean >/dev/null 2>&1 || true
    # 1.3.7's configure injects -force_cpusubtype_ALL, a PowerPC-era flag that
    # modern ld rejects; it breaks the test binaries' link on arm64. Meaningless
    # on Apple Silicon, so strip it rather than skip the failing target.
    sed -i.bak 's/-force_cpusubtype_ALL//g' configure
    ./configure --prefix="$(pfx libvorbis-1.3.7)" --disable-shared --enable-static \
        --disable-docs --disable-examples \
        --with-ogg="$DEPS"
    make -j"$JOBS" && make install
}

# ------------------------------------------------------------------- scaling
b_zimg() {
    cd "$SRC/zimg-release-3.0.6"
    make distclean >/dev/null 2>&1 || true
    ./autogen.sh
    ./configure --prefix="$(pfx zimg-3.0.6)" --disable-shared --enable-static
    make -j"$JOBS" && make install
}

# ------------------------------------------------------------------ sequence
run libpng-1.6.58      b_libpng
run freetype-pass1     b_freetype_pass1
run fribidi-1.0.16     b_fribidi
run harfbuzz-14.3.0    b_harfbuzz
run freetype-2.14.3    b_freetype
run fontconfig-2.18.3  b_fontconfig
run libass-0.17.5      b_libass
run x264-stable        b_x264
run x265-4.2           b_x265
run libvpx-1.16.0      b_libvpx
run dav1d-1.5.4        b_dav1d
run svt-av1-4.2.0      b_svtav1
run aom-3.14.1         b_aom
run libwebp-1.6.0      b_libwebp
run fdk-aac-2.0.3      b_fdkaac
run opus-1.5.2         b_opus
run lame-3.100         b_lame
run libogg-1.3.6       b_libogg
run libvorbis-1.3.7    b_libvorbis
run zimg-3.0.6         b_zimg

echo
echo "=== ALL DEPENDENCIES BUILT ==="
find "$DEPS" -name '*.a' | sed "s|$DEPS/||" | sort
