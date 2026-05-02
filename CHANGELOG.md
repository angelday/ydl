# Changelog

## 1.3.0 - Unreleased

- Extract URLs from pasted text, so notes or prose containing multiple links can
  be downloaded sequentially.
- Show a concise ASCII download progress bar by default, with `-v`/`--verbose`
  available for raw `yt-dlp` and `ffmpeg` output.
- Capture the downloaded filepath from the original `yt-dlp` run instead of
  invoking `yt-dlp` a second time after download.
- Refuse to overwrite an existing `.mp4` when converting a non-MP4 download.
- Re-encode any non-H.264/H.265 video codec to H.264 instead of only handling
  VP9.
- Clarify supported URL schemes in help output.
