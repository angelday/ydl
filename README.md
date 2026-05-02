# ydl

`ydl` is a small zsh wrapper around `yt-dlp` for downloading video with a
preference for H.264/H.265 output, plus VP9-to-H.264 conversion when needed.

## Development

The editable source lives in this repository:

```sh
./ydl -h
make test
```

The tests use temporary stub versions of `yt-dlp`, `ffprobe`, and `ffmpeg`, so
they do not download anything and do not need network access.

Put larger local fixtures or manual-download samples in `testdata/`. The
directory is ignored by git except for its `.gitkeep`.

Reusable pasted-note fixtures live in `testdata/`:

- `notes-single.txt`
- `notes-multiple.txt`
- `notes-messy.txt`
- `notes-x.txt`
- `urls.txt`

Use `manual-test/` as the ignored scratch directory for real downloads:

```sh
cd manual-test
../ydl "$(cat ../testdata/notes-multiple.txt)"
```

## Install

Deploy the checked-out script to the command location:

```sh
make install
```

Compare the development copy with the installed copy:

```sh
make diff-installed
```

By default this installs to `/usr/local/bin/ydl`. Override `PREFIX`, `BINDIR`,
or `BIN` if needed:

```sh
make install BINDIR="$HOME/bin"
```
