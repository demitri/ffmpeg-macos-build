# Building FFmpeg from source on macOS / Apple Silicon

Builds FFmpeg with a full codec set on macOS arm64, without Homebrew, without
touching anaconda, and without polluting `/usr/local` with dependency packages.

Built and verified: FFmpeg 9.0, macOS 26.6, Apple M1, Apple clang 21.

## Design

Every codec library is built **static** into one self-contained prefix
(`prefix/`). Because they are static, they get linked *into* the `ffmpeg`
binary, so that prefix never appears at runtime and never needs installing.
Only `ffmpeg` itself goes to `/usr/local/ffmpeg-<version>`.

This is why there are no `/usr/local/<lib>-<version>` packages: they would add
~20 entries to `PKG_CONFIG_PATH` and ~20 privileged installs, and buy nothing,
since nothing links against them dynamically.

`/usr/local` is root-owned and sudo is password-gated, so `build-ffmpeg.sh`
installs into a `DESTDIR` stage and leaves you one `sudo rsync` to run.

## Scripts

Run in order. All are resumable and fail loudly — no step silently skips.

| Script | What it does |
|---|---|
| `fetch.sh` | Downloads + extracts all sources. Skips what is already extracted. |
| `build-deps.sh` | Builds every codec lib. Records `logs/<pkg>.done`; rerunning skips completed packages. |
| `build-ffmpeg.sh` | Configures/builds/stages ffmpeg. **Asserts every required codec was enabled** and fails if any is missing. |
| `smoke-test.sh` | Encodes a real sample with each codec. Proves function, not just presence in `-encoders`. |

```bash
# FFmpeg source is expected at /usr/local/src/ffmpeg-$FFMPEG_VERSION
# (override with FFMPEG_SRC=/path/to/ffmpeg-src)
./fetch.sh
./build-deps.sh          # ~45-75 min on an 8-core M1
./build-ffmpeg.sh
./smoke-test.sh
sudo rsync -a work/ffmpeg-stage/usr/local/ffmpeg-9.0 /usr/local/
```

All build output goes to `work/` beside the scripts (override with
`FFBUILD_WORKDIR`). Nothing is written outside the repo except the final
`sudo rsync`.

Knobs, all optional:

| Variable | Default |
|---|---|
| `FFMPEG_VERSION` | `9.0` |
| `FFMPEG_SRC` | `/usr/local/src/ffmpeg-$FFMPEG_VERSION` |
| `FFMPEG_PREFIX` | `/usr/local/ffmpeg-$FFMPEG_VERSION` |
| `FFBUILD_WORKDIR` | `<repo>/work` |

To force a package to rebuild, delete its marker: `rm work/logs/<pkg>.done`.

## Environment rules

These are enforced by the scripts; breaking them is what causes most failures.

- **anaconda must not be on `PATH`**, in `PKG_CONFIG_PATH`, or in any `-I`/`-L`.
  `build-deps.sh` asserts this and aborts. `meson` is invoked by absolute path
  (`/usr/local/anaconda/bin/meson`) purely as a build *tool* — it emits ninja
  files and links nothing, so no anaconda code enters any artifact.
- Do **not** use `bash -lc` to get a clean environment: the login profile
  re-adds anaconda to `PATH`. Set `PATH` explicitly in a non-login shell.
- `ACLOCAL_PATH` must include `/usr/local/libtool-2.5.4/share/aclocal`, or any
  package running `autoreconf` fails with `LT_INIT: command not found`.

## Upgrading to a new FFmpeg version

1. Extract the new source to `/usr/local/src/ffmpeg-<new>`.
2. Run with `FFMPEG_VERSION=<new> ./build-ffmpeg.sh` — no edit needed.
3. **Re-verify every configure flag exists** — they do get removed:
   ```bash
   cd /usr/local/src/ffmpeg-<new>
   ./configure --help | grep -E "enable-lib|videotoolbox|audiotoolbox"
   ```
4. Bump dependency versions in `fetch.sh` + `versions.txt`, `rm -rf prefix logs/*.done`,
   rerun. Resolve versions from upstream rather than guessing:
   ```bash
   curl -s https://api.github.com/repos/<owner>/<repo>/tags?per_page=10 | grep '"name"'
   curl -s "https://code.videolan.org/api/v4/projects/videolan%2Fdav1d/repository/tags"
   curl -s "https://bitbucket.org/api/2.0/repositories/multicoreware/x265_git/refs/tags?sort=-name"
   ```
5. Run `smoke-test.sh`. A codec that configures but cannot encode is the failure
   mode this catches.

## Gotchas discovered building this (each cost a failed run)

- **`--enable-postproc` no longer exists in FFmpeg 9.0.** `libpostproc` was
  removed from the tree. Passing it is a hard configure error.
- **x265 multilib needs Apple's `/usr/bin/libtool`, by full path.** It merges
  static archives (`-static -o`). GNU libtool from `/usr/local/libtool-2.5.4/bin`
  comes first on `PATH` and rejects `-static`. The 8/10/12-bit builds all
  succeed, then the merge fails — verify with:
  ```bash
  nm -g prefix/lib/libx265.a | grep -c 10bit   # expect thousands, not 0
  ```
  (`x265_config.h` does *not* record `LINKED_10BIT`/`LINKED_12BIT`; check the
  symbols or `CMakeCache.txt`, not that header.)
- **libwebp must be built with CMake.** Its `configure.ac` calls
  `AC_PROG_LIBTOOL`, removed in libtool 2.5 (it was the deprecated spelling of
  `LT_INIT`). The CMake path installs the same `.pc` files. Note
  `WEBP_BUILD_LIBWEBPMUX` (library) is a *different* option from
  `WEBP_BUILD_WEBPMUX` (CLI tool) — FFmpeg needs the library for animated WebP.
- **fontconfig 2.18+ requires meson >= 1.11.0.** Older meson fails at configure.
  Either upgrade meson or drop to fontconfig 2.17.1 (needs only >= 1.6.1).
- **lame 3.100 exports a symbol that no longer exists.** Remove `lame_init_old`
  from `include/libmp3lame.sym` or the link fails.
- **libvorbis 1.3.7 injects `-force_cpusubtype_ALL`**, a PowerPC-era flag modern
  `ld` rejects. Strip it from `configure`. The library builds fine; only the
  test binaries fail to link, which still aborts `make`.
- **Stale libtool `.la` files poison reconfigures.** They record absolute
  prefixes; if a prefix changes, libtool chases the dead path. `build-deps.sh`
  deletes `.la` files after each install — they are useless in a static build.
- **libass silently degrades.** Its configure will happily build without
  fontconfig/harfbuzz/fribidi, yielding a libass that cannot match fonts.
  Always confirm:
  ```bash
  grep "checking for \(FONTCONFIG\|HARFBUZZ\|FRIBIDI\)" logs/libass-*.log
  ```

## Licensing

Configured with `--enable-gpl --enable-nonfree` (the latter for `libfdk-aac`).
**The resulting binary cannot be redistributed** — personal use only. Drop
`--enable-nonfree` and `--enable-libfdk-aac` to get a redistributable GPLv3
build; FFmpeg's native `aac` encoder and Apple's `aac_at` remain available.

OpenSSL >= 3.0 is GPL-compatible in FFmpeg 9.0 (only `< 3.0.0` requires
`nonfree`), so `--enable-openssl` does not by itself taint the build.

## Apple Silicon notes

- `videotoolbox` gives hardware H.264/HEVC/ProRes encode+decode. Far faster than
  x264/x265, lower quality-per-bit. Both paths are built; pick per job.
- `aac_at` (AudioToolbox) is Apple's AAC encoder and is generally considered at
  least the equal of `libfdk_aac` on this hardware. Worth A/B testing.
- **The M1 has no hardware AV1 decoder** (that arrived with M3), so AV1 playback
  is software via `libdav1d`.
