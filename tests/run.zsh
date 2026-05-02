#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
BIN="$ROOT/ydl"
TEST_COUNT=0

fail() {
  print -u2 -- "not ok - $1"
  exit 1
}

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  print -- "ok $TEST_COUNT - $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$label"
}

make_stubs() {
  local dir="$1"

  cat > "$dir/yt-dlp" <<'STUB'
#!/bin/zsh
set -e

outfile="$PWD/download.${YDL_STUB_EXT:-webm}"
print_file=""
next_is_print_template=0
next_is_print_file=0

for arg in "$@"; do
  if [[ "$next_is_print_file" -eq 1 ]]; then
    print_file="$arg"
    next_is_print_file=0
  elif [[ "$next_is_print_template" -eq 1 ]]; then
    next_is_print_template=0
    next_is_print_file=1
  elif [[ "$arg" == "--print-to-file" ]]; then
    next_is_print_template=1
  fi
done

print -r -- "stub download" > "$outfile"

if [[ -n "$print_file" ]]; then
  print -r -- "$outfile" > "$print_file"
fi
STUB

  cat > "$dir/ffprobe" <<'STUB'
#!/bin/zsh
set -e

if [[ " $* " == *" -select_streams v:0 "* ]]; then
  print -r -- "${YDL_STUB_VIDEO_CODEC:-h264}"
elif [[ " $* " == *" -select_streams a:0 "* ]]; then
  print -r -- "${YDL_STUB_AUDIO_CODEC:-aac}"
fi
STUB

  cat > "$dir/ffmpeg" <<'STUB'
#!/bin/zsh
set -e

out="${@[-1]}"
print -r -- "stub conversion" > "$out"
STUB

  chmod +x "$dir/yt-dlp" "$dir/ffprobe" "$dir/ffmpeg"
}

with_tmp() {
  local name="$1"
  shift
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/bin" "$tmp/work"
  make_stubs "$tmp/bin"

  (
    cd "$tmp/work"
    PATH="$tmp/bin:$PATH" "$@"
  )

  rm -rf "$tmp"
  trap - EXIT
  pass "$name"
}

test_help() {
  local output
  output=$("$BIN" -h)
  assert_contains "$output" "ydl 1.3.0-dev" "help shows version"
  assert_contains "$output" "Usage: ydl" "help shows usage"
}

test_invalid_url() {
  local output exit_code
  set +e
  output=$("$BIN" "not-a-url" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "invalid URL exits with status 1"
  assert_contains "$output" "Input does not look like a valid URL" "invalid URL explains failure"
}

test_h264_download_skips_conversion() {
  local output
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "downloaded file exists"
  assert_contains "$output" "Detected video codec: h264" "h264 codec reported"
  assert_contains "$output" "No conversion needed." "h264 skips conversion"
}

test_vp9_download_converts_to_mp4() {
  local output
  output=$(YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "converted mp4 exists"
  [[ ! -f download.webm ]] || fail "source webm removed after conversion"
  assert_contains "$output" "Re-encoding vp9 → H.264" "vp9 conversion starts"
  assert_contains "$output" "Conversion complete:" "vp9 conversion completes"
}

test_av1_download_converts_to_mp4() {
  local output
  output=$(YDL_STUB_EXT=mkv YDL_STUB_VIDEO_CODEC=av1 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "converted av1 mp4 exists"
  [[ ! -f download.mkv ]] || fail "source mkv removed after conversion"
  assert_contains "$output" "Re-encoding av1 → H.264" "av1 conversion starts"
}

test_conversion_refuses_existing_output() {
  local output exit_code
  print -r -- "existing mp4" > download.mp4

  set +e
  output=$(YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "existing output exits with status 1"
  assert_contains "$output" "Refusing to overwrite existing file" "existing output explains failure"
  assert_contains "$(cat download.mp4)" "existing mp4" "existing mp4 is preserved"
}

test_help
pass "help output"

test_invalid_url
pass "invalid URL handling"

with_tmp "h264 path" test_h264_download_skips_conversion
with_tmp "vp9 conversion path" test_vp9_download_converts_to_mp4
with_tmp "av1 conversion path" test_av1_download_converts_to_mp4
with_tmp "existing output protection" test_conversion_refuses_existing_output

print -- "$TEST_COUNT tests passed"
