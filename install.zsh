#!/bin/zsh
set -euo pipefail

RAW_BASE="${YDL_RAW_BASE:-https://raw.githubusercontent.com/angelday/ydl/main}"
SOURCE_URL="${YDL_SOURCE_URL:-$RAW_BASE/ydl}"

need_command() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 -- "ydl only runs on macOS."
  print -u2 -- "This installer relies on macOS and Homebrew."
  exit 1
fi

if ! need_command brew; then
  print -u2 -- "Homebrew is required to install ydl dependencies."
  print -u2 -- "Please install the Homebrew package manager from https://brew.sh/ and run this installer again."
  exit 1
fi

missing=()
need_command yt-dlp || missing+=(yt-dlp)
need_command ffmpeg || missing+=(ffmpeg)
need_command ffprobe || missing+=(ffmpeg)

if (( ${#missing[@]} > 0 )); then
  packages=("${(@u)missing}")
  print -- "Installing dependencies with Homebrew: ${(j: :)packages}"
  brew install "${packages[@]}"
fi

BINDIR="${YDL_BINDIR:-$(brew --prefix)/bin}"
TARGET="$BINDIR/ydl"
tmp=$(mktemp -t ydl-install.XXXXXX)
trap 'rm -f "$tmp"' EXIT

print -- "Downloading ydl..."
curl -fsSL "$SOURCE_URL" -o "$tmp"
chmod 755 "$tmp"

if [[ ! -d "$BINDIR" ]]; then
  mkdir -p "$BINDIR"
fi

if [[ -w "$BINDIR" ]]; then
  install -m 755 "$tmp" "$TARGET"
else
  sudo install -m 755 "$tmp" "$TARGET"
fi

print -- "Installed ydl to $TARGET"
print -- "Run: ydl -h"
