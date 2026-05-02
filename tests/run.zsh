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

if [[ -n "$YDL_STUB_ARGS_FILE" ]]; then
  printf '%s\n' "$@" > "$YDL_STUB_ARGS_FILE"
fi

outfile="$PWD/download.${YDL_STUB_EXT:-webm}"
counter_file="$PWD/.ydl-stub-count"
print_file=""
next_is_print_template=0
next_is_print_file=0
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
  elif [[ "$arg" == "--progress" ]]; then
    emit_progress=1
  fi
done

count=0
if [[ -f "$counter_file" ]]; then
  count=$(<"$counter_file")
fi
count=$((count + 1))
print -r -- "$count" > "$counter_file"

if [[ -n "$YDL_STUB_FAIL_FIRST" && "$count" -eq 1 ]]; then
  print -u2 -- "ERROR: [twitter] fake: No video could be found in this tweet"
  exit 1
fi

if [[ -n "$YDL_STUB_SUSPEND_FIRST" && "$count" -eq 1 ]]; then
  print -u2 -- "ERROR: [twitter] fake: Suspended"
  exit 1
fi

if [[ -n "$YDL_STUB_NO_VIDEO_THIRD" && "$count" -eq 3 ]]; then
  print -u2 -- "ERROR: [twitter] fake: No video could be found in this tweet"
  exit 1
fi

if [[ -n "$YDL_STUB_UNSUPPORTED" ]]; then
  print -u2 -- "WARNING: [generic] Falling back on generic information extractor"
  print -u2 -- "ERROR: Unsupported URL: https://example.com/"
  exit 1
fi

if [[ -n "$YDL_STUB_INSTAGRAM_RETRY" && "$count" -eq 1 ]]; then
  print -u2 -- "WARNING: [Instagram] Bm__BEMDvCw: No csrf token set by Instagram API"
  print -u2 -- "ERROR: [Instagram] Bm__BEMDvCw: Instagram sent an empty media response."
  exit 1
fi

if [[ "$emit_progress" -eq 0 ]]; then
  print -r -- "stub yt-dlp raw output"
fi

if [[ "$YDL_STUB_UNIQUE_OUTPUTS" -eq 1 ]]; then
  outfile="$PWD/download-$count.${YDL_STUB_EXT:-webm}"
fi

print -r -- "stub download $count" > "$outfile"

if [[ -n "$print_file" ]]; then
  print -r -- "$outfile" > "$print_file"
fi

if [[ "$emit_progress" -eq 1 && -z "$YDL_STUB_NO_PROGRESS" ]]; then
  if [[ -n "$YDL_STUB_UNKNOWN_SPEED" ]]; then
    print -r -- "[download] 100.0% of 14.96MiB at Unknown B/s ETA NA"
  else
    print -r -- "[download]  50.0% of 14.96MiB at 1.0MiB/s ETA Unknown"
    print -r -- "[download]  49.0% of 14.96MiB at 1.0MiB/s ETA Unknown"
    print -r -- "[download] 100.0% of 14.96MiB at 1.0MiB/s ETA 00:00"
  fi
elif [[ -n "$YDL_STUB_ALREADY_DOWNLOADED" ]]; then
  print -r -- "[download] $outfile has already been downloaded"
  print -r -- "[download] 100% of 14.96MiB"
fi
STUB

  cat > "$dir/ffprobe" <<'STUB'
#!/bin/zsh
set -e

if [[ " $* " == *" -select_streams v:0 "* ]]; then
  print -r -- "${YDL_STUB_VIDEO_CODEC:-h264}"
elif [[ " $* " == *" -select_streams a:0 "* ]]; then
  print -r -- "${YDL_STUB_AUDIO_CODEC:-aac}"
elif [[ " $* " == *" format=duration "* ]]; then
  print -r -- "${YDL_STUB_DURATION:-10.0}"
fi
STUB

  cat > "$dir/ffmpeg" <<'STUB'
#!/bin/zsh
set -e

emit_progress=0
for arg in "$@"; do
  if [[ "$arg" == "pipe:1" ]]; then
    emit_progress=1
  fi
done

out="${@[-1]}"
if [[ "$emit_progress" -eq 1 ]]; then
  print -r -- "out_time_us=5000000"
  print -r -- "progress=continue"
  print -r -- "out_time_us=10000000"
  print -r -- "progress=end"
fi
print -r -- "stub conversion" > "$out"
STUB

  cat > "$dir/pbpaste" <<'STUB'
#!/bin/zsh
set -e

cat "$YDL_STUB_CLIPBOARD_FILE"
STUB

  cat > "$dir/pbcopy" <<'STUB'
#!/bin/zsh
set -e

cat > "$YDL_STUB_CLIPBOARD_FILE"
STUB

  cat > "$dir/curl" <<'STUB'
#!/bin/zsh
set -e

if [[ -n "$YDL_STUB_TWEET_UNAVAILABLE" ]]; then
  print -r -- '"tweets":{"entities":{},"errors":{"12345":{}},"fetchStatus":{"12345":"failed"}}'
else
  print -r -- '"tweets":{"entities":{"12345":{"bookmark_count":0,"id_str":"12345","extended_entities":{"media":[{"type":"photo"}]}}},"errors":{},"fetchStatus":{"12345":"loaded"}}'
fi
STUB

  chmod +x "$dir/yt-dlp" "$dir/ffprobe" "$dir/ffmpeg" "$dir/pbpaste" "$dir/pbcopy" "$dir/curl"
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

test_non_macos_refuses_to_run() {
  local tmp output exit_code
  tmp=$(mktemp -d)

  cat > "$tmp/uname" <<'STUB'
#!/bin/zsh
print -- "Linux"
STUB
  chmod +x "$tmp/uname"

  set +e
  output=$(PATH="$tmp:$PATH" "$BIN" -h 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "non-macOS exits with status 1"
  assert_contains "$output" "ydl only runs on macOS" "non-macOS explains platform requirement"
  assert_not_contains "$output" "Usage: ydl" "non-macOS refuses before help"
  rm -rf "$tmp"
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

test_extra_yt_dlp_args_are_forwarded() {
  local args_file args
  args_file="$PWD/yt-dlp-args.txt"

  YDL_STUB_ARGS_FILE="$args_file" YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "https://example.com/video" --write-info-json --download-archive archive.txt >/dev/null
  args=$(cat "$args_file")

  assert_contains "$args" "--write-info-json" "extra yt-dlp flag is forwarded"
  assert_contains "$args" "--download-archive" "extra yt-dlp option is forwarded"
  assert_contains "$args" "archive.txt" "extra yt-dlp option value is forwarded"
}

test_cookies_from_named_browser_are_forwarded() {
  local args_file args
  args_file="$PWD/yt-dlp-args.txt"

  YDL_STUB_ARGS_FILE="$args_file" YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" -c chrome "https://example.com/video" >/dev/null
  args=$(cat "$args_file")

  assert_contains "$args" "--cookies-from-browser" "cookie option is forwarded"
  assert_contains "$args" "chrome" "named browser is forwarded"
}

test_cookies_default_to_safari() {
  local args_file args
  args_file="$PWD/yt-dlp-args.txt"

  YDL_STUB_ARGS_FILE="$args_file" YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" -c "https://example.com/video" >/dev/null
  args=$(cat "$args_file")

  assert_contains "$args" "--cookies-from-browser" "default cookie option is forwarded"
  assert_contains "$args" "safari" "cookie browser defaults to safari"
  assert_contains "$args" "https://example.com/video" "URL is preserved when -c has no browser argument"
}

test_existing_download_is_reported() {
  local output
  output=$(YDL_STUB_ALREADY_DOWNLOADED=1 YDL_STUB_NO_PROGRESS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "https://example.com/video")

  assert_contains "$output" "Already downloaded." "existing download is reported"
  assert_not_contains "$output" "Already downloaded:" "default existing download hides filename"
  assert_not_contains "$output" "Download [" "existing download ignores trailing yt-dlp 100 percent line"
  assert_not_contains "$output" "Download [########################] 100%" "existing download does not render fake progress"
}

test_vp9_download_converts_to_mp4() {
  local output
  output=$(YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "converted mp4 exists"
  [[ ! -f download.webm ]] || fail "source webm removed after conversion"
  assert_contains "$output" "Converting [############------------]  50%" "vp9 conversion progress starts"
  assert_contains "$output" "Converting [########################] 100%" "vp9 conversion progress completes"
  assert_not_contains "$output" "Converted." "default conversion does not print extra completion line"
  assert_not_contains "$output" "Re-encoding vp9 → H.264" "default conversion hides codec detail"
  assert_not_contains "$output" "Re-encoding audio → AAC" "default conversion hides audio detail"
  assert_not_contains "$output" "$PWD/download.mp4" "default conversion hides full path"
}

test_verbose_conversion_shows_codec_details() {
  local output
  output=$(YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" --verbose "https://example.com/video")

  assert_contains "$output" "Detected video codec: vp9" "verbose conversion shows video codec"
  assert_contains "$output" "Detected audio codec: opus" "verbose conversion shows audio codec"
  assert_contains "$output" "Re-encoding audio → AAC..." "verbose conversion shows audio conversion"
  assert_contains "$output" "Re-encoding vp9 → H.264 in MP4 container..." "verbose conversion shows video conversion"
  assert_contains "$output" "Conversion complete: $PWD/download.mp4" "verbose conversion shows full output path"
}

test_av1_download_converts_to_mp4() {
  local output
  output=$(YDL_STUB_EXT=mkv YDL_STUB_VIDEO_CODEC=av1 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video")

  [[ -f download.mp4 ]] || fail "converted av1 mp4 exists"
  [[ ! -f download.mkv ]] || fail "source mkv removed after conversion"
  assert_contains "$output" "Converting [############------------]  50%" "av1 conversion progress starts"
  assert_contains "$output" "Converting [########################] 100%" "av1 conversion progress completes"
  assert_not_contains "$output" "Converted." "default av1 conversion does not print extra completion line"
}

test_existing_converted_output_is_reused() {
  local output exit_code
  print -r -- "existing mp4" > download.mp4

  set +e
  output=$(YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 0 ]] || fail "existing converted output exits successfully"
  assert_contains "$output" "Already converted." "existing converted output is reported as already converted"
  assert_not_contains "$output" "Already downloaded." "existing converted output does not use download wording"
  assert_contains "$(cat download.mp4)" "existing mp4" "existing mp4 is preserved"
  [[ ! -f download.webm ]] || fail "downloaded source is removed when converted output already exists"
}

test_existing_converted_output_reports_once() {
  local output exit_code count
  print -r -- "existing mp4" > download.mp4

  set +e
  output=$(YDL_STUB_ALREADY_DOWNLOADED=1 YDL_STUB_NO_PROGRESS=1 YDL_STUB_EXT=webm YDL_STUB_VIDEO_CODEC=vp9 YDL_STUB_AUDIO_CODEC=opus "$BIN" "https://example.com/video" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 0 ]] || fail "existing converted already-downloaded output exits successfully"
  count=$(printf '%s\n' "$output" | grep -c '^Already downloaded\.$' || true)
  [[ "$count" -eq 1 ]] || fail "existing converted already-downloaded output reports once"
  assert_not_contains "$output" "Already converted." "existing source already-downloaded output does not add converted wording"
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

test_sm_note_fixture_extracts_urls() {
  local input output
  input=$(cat "$ROOT/testdata/notes-sm.txt")
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Found 4 URLs." "sm fixture count reported"
  assert_contains "$output" "Downloading: https://x.com/emtbrides/status/2034623934700679397?s=46&t=VOhZI1qhfsq28OaSCFJNFg" "sm navy seal URL extracted"
  assert_contains "$output" "Downloading: https://x.com/pbakaus/status/2034410464424382824?s=46&t=VOhZI1qhfsq28OaSCFJNFg" "sm radiant shaders URL extracted"
  assert_contains "$output" "Downloading: https://x.com/steveschoger/status/2035077141050622173?s=46&t=VOhZI1qhfsq28OaSCFJNFg" "sm claude design URL extracted"
  assert_contains "$output" "Downloading: https://www.instagram.com/reel/DWJwNGnjWi9/?igsh=MTFwMzVvZTUxb2Zvaw==" "sm instagram URL extracted"
}

test_real_url_fixture_extracts_urls() {
  local input output
  input=$(cat "$ROOT/testdata/urls.txt")
  output=$(YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_contains "$output" "Found 2 URLs." "real URL fixture count reported"
  assert_contains "$output" "Downloading: https://x.com/TristanBlumen/status/2049699223419985984/video/1?s=46" "real x URL extracted"
  assert_contains "$output" "Downloading: https://test-videos.co.uk/vids/bigbuckbunny/webm/vp9/1080/Big_Buck_Bunny_1080_10s_5MB.webm" "real webm URL extracted"
}

test_unknown_speed_is_hidden() {
  local output
  output=$(YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac YDL_STUB_UNKNOWN_SPEED=1 "$BIN" "https://example.com/video")

  assert_contains "$output" "Download [########################] 100%" "unknown-speed progress reaches 100"
  assert_not_contains "$output" "Unknown B/s" "unknown speed is hidden"
}

test_unsupported_url_is_reported_cleanly() {
  local output exit_code

  set +e
  output=$(YDL_STUB_UNSUPPORTED=1 "$BIN" "https://example.com/" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "unsupported URL exits with status 1"
  assert_contains "$output" "Unsupported URL." "unsupported URL is reported cleanly"
  assert_not_contains "$output" "Falling back on generic information extractor" "unsupported URL hides backend warning"
  assert_not_contains "$output" "Error: yt-dlp failed." "unsupported URL hides generic backend error header"
}

test_suspended_account_is_reported_cleanly() {
  local output exit_code

  set +e
  output=$(YDL_STUB_SUSPEND_FIRST=1 "$BIN" "https://example.com/suspended" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "suspended URL exits with status 1"
  assert_contains "$output" "Account suspended." "suspended account is reported cleanly"
  assert_not_contains "$output" "Error: yt-dlp failed." "suspended account hides backend error header"
}

test_verbose_unsupported_url_shows_backend_output() {
  local output exit_code

  set +e
  output=$(YDL_STUB_UNSUPPORTED=1 "$BIN" --verbose "https://example.com/" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "verbose unsupported URL exits with status 1"
  assert_contains "$output" "Unsupported URL: https://example.com/" "verbose unsupported URL shows backend output"
}

test_multi_url_continues_after_failure() {
  local input output exit_code
  input=$'https://x.com/example/status/12345\nhttps://example.com/good'

  set +e
  output=$(YDL_STUB_FAIL_FIRST=1 YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "multi-url failure exits with status 1"
  [[ -f download-2.mp4 ]] || fail "second URL still downloads after first failure"
  assert_contains "$output" "No video could be found in this tweet." "first failure is reported cleanly"
  assert_not_contains "$output" "Error: yt-dlp failed." "known no-video failure hides backend error header"
  assert_not_contains "$output" "Continuing with next URL." "failure continuation is implicit"
  assert_contains "$output" "Downloading: https://example.com/good" "second URL is attempted"
  assert_contains "$output" "Completed with 1 failure(s): 1 unavailable video." "failure summary is reported"
}

test_unavailable_tweet_is_reported_cleanly() {
  local output exit_code

  set +e
  output=$(YDL_STUB_FAIL_FIRST=1 YDL_STUB_TWEET_UNAVAILABLE=1 "$BIN" "https://x.com/example/status/12345" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "unavailable tweet exits with status 1"
  assert_contains "$output" "Tweet unavailable." "unavailable tweet is reported cleanly"
  assert_not_contains "$output" "No video could be found" "unavailable tweet is not mislabeled no-video"
}

test_instagram_retry_is_reported_cleanly() {
  local output exit_code

  set +e
  output=$(YDL_STUB_INSTAGRAM_RETRY=1 "$BIN" "https://www.instagram.com/p/BoFlubPFowe/" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "retryable Instagram post exits with status 1"
  assert_contains "$output" "Instagram could not be accessed. Try again, or use -c safari / -c chrome." "retryable Instagram post is reported cleanly"
  assert_not_contains "$output" "Instagram post unavailable." "retryable Instagram post is not reported unavailable"
  assert_not_contains "$output" "No csrf token" "retryable Instagram post hides csrf warning"
  assert_not_contains "$output" "Error: yt-dlp failed." "retryable Instagram post hides backend error header"
}

test_clipboard_no_video_marks_url() {
  local output exit_code clipboard
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Watch these:\nhttps://x.com/example/status/2049843950844834075?s=46&t=VOhZI1qhfsq28OaSCFJNFg\nhttps://example.com/good' > "$clipboard"

  set +e
  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_FAIL_FIRST=1 YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "clipboard no-video exits with status 1"
  assert_contains "$output" "Clipboard updated: removed 1 completed URL, marked 1 unavailable video URL with [no-video]." "clipboard update is reported"
  assert_contains "$(cat "$clipboard")" "[no-video]https://x.com/example/status/2049843950844834075?s=46&t=VOhZI1qhfsq28OaSCFJNFg" "failed query URL is marked in clipboard"
  assert_not_contains "$(cat "$clipboard")" "https://example.com/good" "successful URL is removed from clipboard"
  assert_not_contains "$(cat "$clipboard")" "[no-video]https://example.com/good" "successful URL is not marked"
  assert_not_contains "$output" "Completed with 1 failure(s)." "all-marked clipboard no-video failures do not print failure summary"
}

test_clipboard_suspended_is_removed_and_counted() {
  local output exit_code clipboard contents
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Watch these:\nhttps://example.com/suspended\nhttps://example.com/good\nhttps://example.com/no-video' > "$clipboard"

  set +e
  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_SUSPEND_FIRST=1 YDL_STUB_NO_VIDEO_THIRD=1 YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" 2>&1)
  exit_code=$?
  set -e
  contents=$(cat "$clipboard")

  [[ "$exit_code" -eq 1 ]] || fail "clipboard suspended/no-video exits with status 1"
  assert_contains "$output" "Account suspended." "suspended account is reported cleanly in clipboard batch"
  assert_contains "$output" "No video could be found in this tweet." "no-video is reported cleanly in clipboard batch"
  assert_contains "$output" "Clipboard updated: removed 1 completed URL, removed 1 suspended URL, marked 1 unavailable video URL with [no-video]." "clipboard update summarizes suspended and no-video"
  assert_contains "$output" "Completed with 2 failure(s): 1 suspended account, 1 unavailable video." "final stat includes suspended account"
  assert_not_contains "$contents" "https://example.com/suspended" "suspended URL is removed from clipboard"
  assert_not_contains "$contents" "https://example.com/good" "successful URL is removed from clipboard"
  assert_contains "$contents" "[no-video]https://example.com/no-video" "no-video URL is marked in clipboard"
}

test_clipboard_unavailable_tweet_is_removed() {
  local output exit_code clipboard contents
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Watch these:\nhttps://x.com/example/status/12345\nhttps://example.com/good' > "$clipboard"

  set +e
  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_FAIL_FIRST=1 YDL_STUB_TWEET_UNAVAILABLE=1 YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" 2>&1)
  exit_code=$?
  set -e
  contents=$(cat "$clipboard")

  [[ "$exit_code" -eq 1 ]] || fail "clipboard unavailable tweet exits with status 1"
  assert_contains "$output" "Tweet unavailable." "unavailable tweet is reported in clipboard batch"
  assert_contains "$output" "Clipboard updated: removed 1 completed URL, removed 1 unavailable URL." "clipboard update summarizes unavailable tweet"
  assert_contains "$output" "Completed with 1 failure(s): 1 unavailable post." "final stat includes unavailable tweet"
  assert_not_contains "$contents" "https://x.com/example/status/12345" "unavailable tweet is removed from clipboard"
  assert_not_contains "$contents" "[no-video]" "unavailable tweet is not marked no-video"
}

test_clipboard_instagram_retry_is_left_for_retry() {
  local output exit_code clipboard contents
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Watch these:\nhttps://www.instagram.com/p/BoFlubPFowe/?utm_source=ig_share_sheet\nhttps://example.com/good' > "$clipboard"

  set +e
  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_INSTAGRAM_RETRY=1 YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" 2>&1)
  exit_code=$?
  set -e
  contents=$(cat "$clipboard")

  [[ "$exit_code" -eq 1 ]] || fail "clipboard retryable Instagram post exits with status 1"
  assert_contains "$output" "Instagram could not be accessed. Try again, or use -c safari / -c chrome." "retryable Instagram post is reported in clipboard batch"
  assert_contains "$output" "Clipboard updated: removed 1 completed URL." "clipboard update only summarizes completed URL"
  assert_contains "$output" "Completed with 1 failure(s): 1 retryable Instagram post." "final stat includes retryable Instagram post"
  assert_contains "$contents" "https://www.instagram.com/p/BoFlubPFowe/" "retryable Instagram post is left in clipboard"
  assert_not_contains "$contents" "[no-video]" "retryable Instagram post is not marked no-video"
  assert_not_contains "$contents" "https://example.com/good" "successful URL is still removed from clipboard"
}

test_no_video_marker_is_not_retried() {
  local input output exit_code
  input=$'[no-video]https://example.com/no-video\nhttps://example.com/good'

  output=$(YDL_STUB_UNIQUE_OUTPUTS=1 YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN" "$input")

  assert_not_contains "$output" "Downloading: https://example.com/no-video" "marked no-video URL is skipped"
  assert_contains "$output" "Downloading: https://example.com/good" "unmarked URL is still processed"
}

test_clipboard_only_marked_urls_is_done() {
  local output exit_code clipboard
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Plastik\n\n[no-video]https://example.com/one\n\n[no-video]https://example.com/two' > "$clipboard"

  set +e
  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" "$BIN" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 0 ]] || fail "clipboard with only marked URLs exits successfully"
  assert_contains "$output" "No actionable URLs found." "only marked clipboard reports no actionable URLs"
  assert_not_contains "$output" "Clipboard does not contain any valid URLs" "only marked clipboard is not treated as invalid"
  assert_not_contains "$output" "Downloading:" "marked clipboard URLs are not downloaded"
}

test_clipboard_rewrite_preserves_spacing() {
  local output clipboard expected
  clipboard="$PWD/clipboard.txt"
  print -r -- $'Title\n\nhttps://example.com/done\n\nNotes after\nhttps://example.com/also-done\n' > "$clipboard"

  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN")
  expected=$'Title\n\n\nNotes after'

  assert_contains "$output" "Clipboard updated: removed 2 completed URLs." "completed clipboard update is reported"
  [[ "$(cat "$clipboard")" == "$expected" ]] || fail "clipboard rewrite preserves spacing"
}

test_single_clipboard_url_is_left_intact() {
  local output clipboard
  clipboard="$PWD/clipboard.txt"
  print -r -- "https://example.com/done" > "$clipboard"

  output=$(YDL_STUB_CLIPBOARD_FILE="$clipboard" YDL_STUB_EXT=mp4 YDL_STUB_VIDEO_CODEC=h264 YDL_STUB_AUDIO_CODEC=aac "$BIN")

  assert_not_contains "$output" "Clipboard updated:" "single clipboard URL does not report rewrite"
  [[ "$(cat "$clipboard")" == "https://example.com/done" ]] || fail "single clipboard URL is left intact"
}

test_help
pass "help output"

test_invalid_url
pass "invalid URL handling"

test_non_macos_refuses_to_run
pass "non-macOS refusal"

with_tmp "h264 path" test_h264_download_skips_conversion
with_tmp "verbose backend output" test_verbose_shows_backend_output
with_tmp "extra yt-dlp args forwarding" test_extra_yt_dlp_args_are_forwarded
with_tmp "cookies from named browser forwarding" test_cookies_from_named_browser_are_forwarded
with_tmp "cookies default browser forwarding" test_cookies_default_to_safari
with_tmp "existing download report" test_existing_download_is_reported
with_tmp "vp9 conversion path" test_vp9_download_converts_to_mp4
with_tmp "verbose conversion details" test_verbose_conversion_shows_codec_details
with_tmp "av1 conversion path" test_av1_download_converts_to_mp4
with_tmp "existing converted output reuse" test_existing_converted_output_is_reused
with_tmp "existing converted output single report" test_existing_converted_output_reports_once
with_tmp "prose with multiple URLs" test_prose_with_multiple_urls_downloads_each
with_tmp "messy note fixture" test_messy_note_fixture_extracts_urls
with_tmp "single note fixture" test_single_note_fixture_downloads_one
with_tmp "x note fixture" test_x_note_fixture_extracts_urls
with_tmp "sm note fixture" test_sm_note_fixture_extracts_urls
with_tmp "real URL fixture" test_real_url_fixture_extracts_urls
with_tmp "unknown speed hidden" test_unknown_speed_is_hidden
with_tmp "unsupported URL clean output" test_unsupported_url_is_reported_cleanly
with_tmp "verbose unsupported URL backend output" test_verbose_unsupported_url_shows_backend_output
with_tmp "suspended account clean output" test_suspended_account_is_reported_cleanly
with_tmp "multi URL continues after failure" test_multi_url_continues_after_failure
with_tmp "unavailable tweet clean output" test_unavailable_tweet_is_reported_cleanly
with_tmp "Instagram retry clean output" test_instagram_retry_is_reported_cleanly
with_tmp "clipboard no-video marker" test_clipboard_no_video_marks_url
with_tmp "clipboard suspended removal and stats" test_clipboard_suspended_is_removed_and_counted
with_tmp "clipboard unavailable tweet removal" test_clipboard_unavailable_tweet_is_removed
with_tmp "clipboard Instagram retry" test_clipboard_instagram_retry_is_left_for_retry
with_tmp "no-video marker is not retried" test_no_video_marker_is_not_retried
with_tmp "clipboard only marked URLs" test_clipboard_only_marked_urls_is_done
with_tmp "clipboard rewrite preserves spacing" test_clipboard_rewrite_preserves_spacing
with_tmp "single clipboard URL is left intact" test_single_clipboard_url_is_left_intact

print -- "$TEST_COUNT tests passed"
