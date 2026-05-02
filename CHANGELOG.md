# Changelog

## 1.3.0 - Unreleased

- Extract URLs from pasted text, so notes or prose containing multiple links can
  be downloaded sequentially.
- Continue processing later URLs when one URL fails, then exit nonzero with a
  failure summary.
- When running from clipboard input, mark URLs that fail because no video is
  available by rewriting the clipboard text with `[no-video]` before the URL,
  remove successfully completed URLs from the rewritten clipboard text, and
  skip previously marked `[no-video]` URLs on later runs. Clipboard input with
  only marked URLs now exits cleanly with no work to do. Clipboard rewriting is
  only applied to multi-URL clipboard queues; single-URL clipboards are left
  intact.
- Show a concise ASCII download progress bar by default, with `-v`/`--verbose`
  available for raw `yt-dlp` and `ffmpeg` output.
- Preserve `yt-dlp`'s already-downloaded signal in default output, including
  cases where `yt-dlp` also emits a trailing `100%` line.
- Report known unsupported URLs with a concise default message while preserving
  raw backend details in verbose mode.
- Report suspended accounts with a concise default message, remove suspended
  URLs from multi-URL clipboard queues, and include suspended accounts in the
  final failure summary.
- Distinguish missing/deleted X tweets from tweets that simply have no video;
  unavailable tweets are removed from multi-URL clipboard queues instead of
  being marked `[no-video]`.
- Capture the downloaded filepath from the original `yt-dlp` run instead of
  invoking `yt-dlp` a second time after download.
- Refuse to overwrite an existing `.mp4` when converting a non-MP4 download.
- Convert videos outside Apple-friendly H.264/H.265 to H.264 MP4 instead of
  only handling VP9.
- Clarify supported URL schemes in help output.
- Add a one-command installer/updater that installs missing Homebrew
  dependencies and places `ydl` in Homebrew's `bin` directory.
- Refuse to run or install on non-macOS systems, since `ydl` relies on macOS
  clipboard and media workflow behavior.
- Add stubbed installer tests for Homebrew/dependency checks, first install,
  update, and custom install directories.
- Treat reruns of already-converted non-MP4 downloads as already downloaded
  instead of failing on the existing MP4.
