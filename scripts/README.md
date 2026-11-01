# scripts/

Helpers for re-encoding video with the FFmpeg this repo builds. Both are single-file
Python 3 programs using only the standard library, and need `ffmpeg` and `ffprobe` on
`PATH` (a build with `libx265`; 10-bit output needs x265's multilib build, otherwise
pass `--8bit`).

| File | What it does |
|---|---|
| `hevc-encode` | Re-encode SD/low-res video (MPG, WMV, ...) to HEVC/AAC in MKV or MP4, optionally merging several files into one. |
| `hevc-queue` | A filesystem job queue that runs many `hevc-encode` jobs in parallel. |
| `completions/hevc.bash` | Bash tab-completion for both. |

## hevc-encode

```bash
hevc-encode --scan *.mpg *.wmv                 # report interlacing only; encode nothing
hevc-encode *.mpg                              # one .mkv per input, next to the input
hevc-encode --outdir ~/out *.wmv
hevc-encode --merge -o ep.mkv part1.mpg part2.mpg
```

- **Interlacing detection.** Each file is sampled with ffmpeg's `idet` filter at several
  points and classified progressive / interlaced / mixed. Container flags are not trusted.
- **Deinterlacing.** Interlaced material gets `bwdif` at *double rate* (29.97i becomes
  59.94p) for smooth motion; `--rate single` disables that. *Mixed* material
  (telecined or mixed content, and sometimes noisy low-bitrate progressive WMV) stops
  with an error until you choose `--deint interlaced|progressive|telecine`.
- **Encoding.** x265 `slow`, CRF 23, 10-bit (`--8bit` for clients without Main10), AAC
  audio at 64 kbps per channel, `hvc1` tag. `--threads N` limits x265 to N threads.
- **Merging.** Inputs are joined in the order given (the order is printed), converted to
  square pixels, letterboxed to the first file's display size (or `--size WxH`),
  resampled to the first file's frame rate, with stereo 48 kHz audio. Every input needs audio.
- **Output name.** Must end in `.mkv`, `.mp4` or `.m4v`; anything else is refused.

Safety: it never deletes or overwrites anything. Output goes to a hidden `.part` file,
renamed only after a full decode with no errors and a duration match. It refuses inputs
with subtitle streams (it would drop them). Outputs larger than `--max-ratio` (default
70%) of the input are marked `LARGE`. Results append to `hevc-encode.log.tsv` in the
output directory; the exit status is 1 if any job failed.

## hevc-queue

```bash
cd /some/dir;  hevc-queue add *.mpg            # outputs land next to the inputs
cd /other/dir; hevc-queue add -x "--deint progressive" *.wmv
hevc-queue add --merge --natural -o "A vid.mkv" "A vid"*.mpg   # shows order, asks to confirm
hevc-queue run                                 # the worker; stays alive for new jobs
hevc-queue status [-a]
```

| Command | Effect |
|---|---|
| `add [--merge] [--natural] [-y] [-o OUT] [--outdir DIR] [-x "opts"] FILES` | Queue jobs. Paths are made absolute, so submit from anywhere. `-x` passes extra `hevc-encode` options (one quoted string). |
| `run [-j N] [-t N] [--once]` | Start the worker (one per queue). `--once` exits when the queue is empty. |
| `set -j N -t N` | Change parallel jobs / threads per job while the worker runs. |
| `pause` / `resume` | Stop / start launching new jobs. Running jobs finish. |
| `cancel ID... \| --all` | Remove pending jobs. |
| `retry [-x "opts"] [ID...]` | Requeue failed jobs; `-x` replaces their options. |
| `status [-a]` | Counts, progress / speed / ETA of running jobs, failures with their log path. |

Defaults are derived from the core count: parallel jobs = cores / 8 (max 4), threads per
job = cores / jobs. One x265 encode of SD video cannot use 32 cores, so several jobs at
once is what fills the machine; benchmark one clip at 2, 3, 4 and 6 jobs to find the knee.

- **Merge order is never assumed.** A shell glob sorts alphabetically (`vid 1`, `vid 10`,
  `vid 2`). `add --merge` prints the numbered order and asks for confirmation (`-y` skips
  it, but a non-interactive run without `-y` refuses). `--natural` sorts numerically.
- **Queue location:** `$HEVC_QUEUE`, default `~/hevc-queue`:
  `pending/ running/ done/ failed/` (one JSON file per job) and `logs/<id>.log` (full
  output per job). Jobs left in `running/` after a crash return to `pending/` on the next
  `run`. Ctrl-C interrupts the encodes cleanly and requeues them.
- Add refuses duplicate inputs, existing outputs, and two jobs writing the same output.
- The queue never deletes inputs, outputs or job records (only `cancel` removes pending jobs).

## Installing

```bash
ln -s "$PWD/hevc-encode" "$PWD/hevc-queue" ~/.local/bin/      # or add this directory to PATH
echo "source $PWD/completions/hevc.bash" >> ~/.bashrc          # tab completion
```

`hevc-queue` finds `hevc-encode` next to itself, so keep them in the same directory
(symlinks are fine).

## Status

Tested on synthetic clips (interlaced MPEG-2, WMV; merge; queue with parallel jobs,
failure and retry). Not yet exercised: telecine handling (`--deint telecine`) and
large real-world batches.
