#!/usr/local/bash/bin/bash
# Smoke-test the staged ffmpeg 9.0 build: prove each enabled codec actually
# encodes, rather than merely appearing in `-encoders` output.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${FFBUILD_WORKDIR:-$SELF/work}"
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0}"
FFMPEG="${1:-$WORKDIR/ffmpeg-stage/usr/local/ffmpeg-$FFMPEG_VERSION/bin/ffmpeg}"
[ -x "$FFMPEG" ] || { echo "FATAL: no ffmpeg at $FFMPEG" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC_V="-f lavfi -i testsrc2=size=320x240:rate=30:duration=1"
SRC_A="-f lavfi -i sine=frequency=440:duration=1"

pass=0; fail=0; failed=()
try() {  # try <label> <output-file> <ffmpeg args...>
    local label="$1" out="$2"; shift 2
    if "$FFMPEG" -nostdin -v error -y "$@" "$WORK/$out" >"$WORK/$label.log" 2>&1 \
       && [ -s "$WORK/$out" ]; then
        printf "  PASS  %s\n" "$label"; pass=$((pass+1))
    else
        printf "  FAIL  %s\n" "$label"; fail=$((fail+1)); failed+=("$label")
        sed 's/^/          /' "$WORK/$label.log" | head -5
    fi
}

echo "=== video encoders ==="
try libx264       v264.mp4   $SRC_V -c:v libx264 -preset ultrafast
try libx265       v265.mp4   $SRC_V -c:v libx265 -preset ultrafast -x265-params log-level=none
try libvpx-vp9    vvp9.webm  $SRC_V -c:v libvpx-vp9 -cpu-used 8 -deadline realtime
try libsvtav1     vsvt.mp4   $SRC_V -c:v libsvtav1 -preset 12
try libaom-av1    vaom.mkv   $SRC_V -c:v libaom-av1 -cpu-used 8 -usage realtime
try h264_vtenc    vvth.mp4   $SRC_V -c:v h264_videotoolbox
try hevc_vtenc    vvtx.mp4   $SRC_V -c:v hevc_videotoolbox -tag:v hvc1
try prores_vt     vvtp.mov   $SRC_V -c:v prores_videotoolbox
try libwebp       vweb.webp  $SRC_V -c:v libwebp -frames:v 1

echo "=== audio encoders ==="
try libopus       aopus.opus $SRC_A -c:a libopus
try libmp3lame    amp3.mp3   $SRC_A -c:a libmp3lame
try libvorbis     aogg.ogg   $SRC_A -c:a libvorbis
try aac_at        aac_at.m4a $SRC_A -c:a aac_at
try aac_native    aacn.m4a   $SRC_A -c:a aac

echo "=== filters / libs ==="
try zscale        fz.mp4     $SRC_V -vf "zscale=w=160:h=120" -c:v libx264 -preset ultrafast
try drawtext      fd.mp4     $SRC_V -vf "drawtext=text='hi':fontsize=24:fontcolor=white" -c:v libx264 -preset ultrafast
# libass via the subtitles filter needs a real .ass file
cat > "$WORK/s.ass" <<'ASS'
[Script Info]
ScriptType: v4.00+
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, Bold, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,24,&H00FFFFFF,0,2,10,10,10,1
[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,subtitle test
ASS
try libass        fa.mp4     $SRC_V -vf "subtitles=$WORK/s.ass" -c:v libx264 -preset ultrafast

echo "=== decoders ==="
try dav1d_decode  d_av1.mp4  -i "$WORK/vsvt.mp4" -c:v libx264 -preset ultrafast

echo
echo "passed: $pass   failed: $fail"
if [ "$fail" -ne 0 ]; then
    echo "FAILED: ${failed[*]}" >&2
    exit 1
fi
echo "ALL CODECS FUNCTIONAL"
