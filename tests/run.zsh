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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "$label"
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
next_is_progress_template=0
emit_progress=0

for arg in "$@"; do
  if [[ "$next_is_print_file" -eq 1 ]]; then
    print_file="$arg"
    next_is_print_file=0
  elif [[ "$next_is_print_template" -eq 1 ]]; then
    next_is_print_template=0
    next_is_print_file=1
  elif [[ "$arg" == "--print-to-file" ]]; then
    next_is_print_template=1
  elif [[ "$next_is_progress_template" -eq 1 ]]; then
    emit_progress=1
    next_is_progress_template=0
  elif [[ "$arg" == "--progress-template" ]]; then
    next_is_progress_template=1
  fi
done

if [[ "$emit_progress" -eq 0 ]]; then
  print -r -- "stub yt-dlp raw output"
fi

print -r -- "stub download" > "$outfile"

if [[ -n "$print_file" ]]; then
  print -r -- "$outfile" > "$print_file"
fi

if [[ "$emit_progress" -eq 1 && -z "$YDL_STUB_NO_PROGRESS" ]]; then
  print -r -- " 50.0%|1.0MiB/s|Unknown"
  print -r -- " 49.0%|1.0MiB/s|Unknown"
  print -r -- "100.0%|1.0MiB/s|00:00"
elif [[ -n "$YDL_STUB_ALREADY_DOWNLOADED" ]]; then
  print -r -- "[download] $outfile has already been downloaded"
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
  assert_contains "$output" "--verbose" "help shows verbose option"
}

test_invalid_url() {
  local output exit_code
  set +e
  output=$("$BIN" "not-a-url" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "invalid URL exits with status 1"
  assert_contains "$output" "Input does not contain any valid URLs" "invalid URL explains failure"
}

test_h264_download_skips_conversion() {
  local output
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "downloaded file exists"
  assert_contains "$output" "Download [############------------]  50%" "download progress is rendered"
  assert_contains "$output" "Download [########################] 100%" "download progress reaches 100"
  assert_not_contains "$output" "Detected video codec" "default output hides codec details"
  assert_not_contains "$output" "No conversion needed." "default output hides no-op conversion"
}

test_verbose_shows_backend_output() {
  local output
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" --verbose "https://example.com/video")

  assert_contains "$output" "stub yt-dlp raw output" "verbose shows raw yt-dlp output"
  assert_contains "$output" "Detected video codec: h264" "verbose shows codec details"
  assert_contains "$output" "No conversion needed." "verbose shows no-op conversion"
}

test_existing_download_is_reported() {
  local output
  output=$(YDL_STUB_ALREADY_DOWNLOADED=1 YDL_STUB_NO_PROGRESS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "https://example.com/video")

  assert_contains "$output" "Already downloaded." "existing download is reported"
  assert_not_contains "$output" "Already downloaded:" "default existing download hides filename"
  assert_not_contains "$output" "Download [########################] 100%" "existing download does not render fake progress"
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

test_prose_with_multiple_urls_downloads_each() {
  local input output
  input=$(cat "$ROOT/testdata/notes-multiple.txt")
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Found 3 URLs." "multi-url count reported"
  assert_contains "$output" "Downloading: https://example.com/video/one" "first fixture URL extracted"
  assert_contains "$output" "Downloading: https://example.com/video/two?s=46" "second fixture URL strips trailing period"
  assert_contains "$output" "Downloading: https://example.com/video/three" "third fixture URL strips closing parenthesis"
}

test_messy_note_fixture_extracts_urls() {
  local input output
  input=$(cat "$ROOT/testdata/notes-messy.txt")
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Found 4 URLs." "messy fixture count reported"
  assert_contains "$output" "Downloading: https://example.com/video/markdown" "markdown fixture URL extracted"
  assert_contains "$output" "Downloading: https://example.com/video/quoted" "quoted fixture URL extracted"
  assert_contains "$output" "Downloading: https://example.com/video/punctuation" "trailing punctuation stripped"
  assert_contains "$output" "Downloading: https://example.com/video/curly" "curly wrapper stripped"
}

test_single_note_fixture_downloads_one() {
  local input output
  input=$(cat "$ROOT/testdata/notes-single.txt")
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Downloading: https://example.com/video/single?s=46" "single fixture URL extracted"
}

test_x_note_fixture_extracts_urls() {
  local input output
  input=$(cat "$ROOT/testdata/notes-x.txt")
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Found 2 URLs." "x fixture count reported"
  assert_contains "$output" "Downloading: https://x.com/antoinellorca/status/2049796325160423678/video/1?s=46" "first x URL extracted"
  assert_contains "$output" "Downloading: https://x.com/TristanBlumen/status/2049699223419985984/video/1?s=46" "second x URL extracted"
}

test_help
pass "help output"

test_invalid_url
pass "invalid URL handling"

with_tmp "h264 path" test_h264_download_skips_conversion
with_tmp "verbose backend output" test_verbose_shows_backend_output
with_tmp "existing download report" test_existing_download_is_reported
with_tmp "vp9 conversion path" test_vp9_download_converts_to_mp4
with_tmp "av1 conversion path" test_av1_download_converts_to_mp4
with_tmp "existing output protection" test_conversion_refuses_existing_output
with_tmp "prose with multiple URLs" test_prose_with_multiple_urls_downloads_each
with_tmp "messy note fixture" test_messy_note_fixture_extracts_urls
with_tmp "single note fixture" test_single_note_fixture_downloads_one
with_tmp "x note fixture" test_x_note_fixture_extracts_urls

print -- "$TEST_COUNT tests passed"
