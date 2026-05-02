# ydl

`ydl` is a small zsh wrapper around `yt-dlp` for downloading video with a
preference for Apple-friendly H.264/H.265 output. Videos outside that codec
family are converted to H.264 MP4.

`ydl` is macOS-only. It relies on macOS clipboard commands and media workflow
defaults.

## Development

The editable source lives in this repository:

```sh
./ydl -h
make test
```

The tests use temporary stub versions of `yt-dlp`, `ffprobe`, `ffmpeg`, and
installer dependencies, so they do not download anything, install packages, or
need network access.

Put reusable input fixtures in `testdata/`. Real downloaded files and other
manual scratch output belong in `manual-test/`, which is ignored by git except
for its `.gitkeep`.

Reusable pasted-note fixtures live in `testdata/`:

- `notes-single.txt`
- `notes-multiple.txt`
- `notes-messy.txt`
- `notes-x.txt`
- `notes-sm.txt`
- `urls.txt`

Use `manual-test/` as the ignored scratch directory for real downloads:

```sh
cd manual-test
../ydl "$(cat ../testdata/notes-x.txt)"
```

## Install Or Update

Install or update `ydl` and its Homebrew dependencies with one command:

```sh
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/angelday/ydl/main/install.zsh)"
```

Rerun the same command later to update `ydl`. The installer always downloads
the current script and replaces the installed command.

The installer checks for `yt-dlp`, `ffmpeg`, and `ffprobe`. Missing dependencies
are installed with Homebrew. If Homebrew is not installed, the installer will
ask you to install it from <https://brew.sh/> and run the command again. On
non-macOS systems, the installer refuses to run.

By default this installs `ydl` to Homebrew's `bin` directory, such as
`/opt/homebrew/bin/ydl` or `/usr/local/bin/ydl`.

To choose a different install directory:

```sh
YDL_BINDIR="$HOME/bin" /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/angelday/ydl/main/install.zsh)"
```

From a checked-out development copy, deploy the local script to the command
location:

```sh
make install
```

Compare the development copy with the installed copy:

```sh
make diff-installed
```

By default `make install` installs to `/usr/local/bin/ydl`. Override `PREFIX`,
`BINDIR`, or `BIN` if needed:

```sh
make install BINDIR="$HOME/bin"
```
