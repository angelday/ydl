#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
INSTALLER="$ROOT/install.zsh"
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

make_installer_stubs() {
  local dir="$1"

  cat > "$dir/uname" <<'STUB'
#!/bin/zsh
print -- "${YDL_TEST_UNAME:-Darwin}"
STUB

  cat > "$dir/brew" <<'STUB'
#!/bin/zsh
set -e

if [[ "$1" == "--prefix" ]]; then
  print -- "$YDL_TEST_PREFIX"
elif [[ "$1" == "install" ]]; then
  print -r -- "$*" >> "$YDL_TEST_BREW_LOG"
  print -- "brew $*"
else
  print -- "brew $*"
fi
STUB

  cat > "$dir/curl" <<'STUB'
#!/bin/zsh
set -e

out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      shift
      out="$1"
      ;;
  esac
  shift
done

if [[ -z "$out" ]]; then
  print -u2 -- "missing curl -o target"
  exit 1
fi

cp "$YDL_TEST_SOURCE" "$out"
STUB

  cat > "$dir/install" <<'STUB'
#!/bin/zsh
set -e

src="${@: -2:1}"
dst="${@: -1}"
cp "$src" "$dst"
chmod 755 "$dst"
STUB

  cat > "$dir/sudo" <<'STUB'
#!/bin/zsh
set -e

"$@"
STUB

  chmod +x "$dir/uname" "$dir/brew" "$dir/curl" "$dir/install" "$dir/sudo"
}

with_tmp() {
  local name="$1"
  shift
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/bin" "$tmp/prefix/bin"
  print -r -- '#!/bin/zsh' > "$tmp/source-ydl"
  print -r -- 'print -- ydl test source' >> "$tmp/source-ydl"
  chmod +x "$tmp/source-ydl"
  : > "$tmp/brew.log"
  make_installer_stubs "$tmp/bin"

  (
    cd "$tmp"
    PATH="$tmp/bin:/usr/bin:/bin" \
      YDL_TEST_PREFIX="$tmp/prefix" \
      YDL_TEST_SOURCE="$tmp/source-ydl" \
      YDL_TEST_BREW_LOG="$tmp/brew.log" \
      YDL_LEGACY_TARGET="$tmp/usr-local-bin/ydl" \
      YDL_SOURCE_URL="https://example.com/ydl" \
      "$@"
  )

  rm -rf "$tmp"
  trap - EXIT
  pass "$name"
}

test_non_macos_refuses() {
  local output exit_code

  set +e
  output=$(YDL_TEST_UNAME=Linux "$INSTALLER" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "non-macOS installer exits with status 1"
  assert_contains "$output" "ydl only runs on macOS." "non-macOS installer explains platform requirement"
}

test_missing_homebrew_explains_install_url() {
  local output exit_code

  set +e
  output=$(PATH="/usr/bin:/bin" "$INSTALLER" 2>&1)
  exit_code=$?
  set -e

  [[ "$exit_code" -eq 1 ]] || fail "missing Homebrew exits with status 1"
  assert_contains "$output" "Homebrew is required" "missing Homebrew explains requirement"
  assert_contains "$output" "https://brew.sh/" "missing Homebrew points to brew.sh"
}

test_all_dependencies_missing_are_installed() {
  local output brew_log

  output=$("$INSTALLER")
  brew_log=$(cat "$YDL_TEST_BREW_LOG")

  assert_contains "$output" "Installing dependencies with Homebrew: yt-dlp ffmpeg" "all missing dependencies are reported"
  assert_contains "$brew_log" "install yt-dlp ffmpeg" "all missing dependencies are installed"
}

test_only_ffmpeg_dependency_missing_is_installed() {
  local output brew_log

  cat > "$PWD/bin/yt-dlp" <<'STUB'
#!/bin/zsh
STUB
  chmod +x "$PWD/bin/yt-dlp"

  output=$("$INSTALLER")
  brew_log=$(cat "$YDL_TEST_BREW_LOG")

  assert_contains "$output" "Installing dependencies with Homebrew: ffmpeg" "missing ffmpeg dependency is reported"
  assert_contains "$brew_log" "install ffmpeg" "missing ffmpeg dependency is installed"
  assert_not_contains "$brew_log" "yt-dlp" "installed yt-dlp is not reinstalled"
}

test_dependencies_present_skip_brew_install() {
  local output brew_log

  for cmd in yt-dlp ffmpeg ffprobe; do
    print -r -- '#!/bin/zsh' > "$PWD/bin/$cmd"
    chmod +x "$PWD/bin/$cmd"
  done

  output=$("$INSTALLER")
  brew_log=$(cat "$YDL_TEST_BREW_LOG")

  assert_not_contains "$output" "Installing dependencies with Homebrew" "present dependencies skip install message"
  [[ -z "$brew_log" ]] || fail "present dependencies skip brew install"
}

test_first_install_message_and_target() {
  local output target

  output=$("$INSTALLER")
  target="$YDL_TEST_PREFIX/bin/ydl"

  assert_contains "$output" "Installing ydl to $target" "first install message is shown"
  [[ -x "$target" ]] || fail "first install writes executable target"
}

test_update_message_when_target_exists() {
  local output target
  target="$YDL_TEST_PREFIX/bin/ydl"
  print -r -- "old ydl" > "$target"
  chmod +x "$target"

  output=$("$INSTALLER")

  assert_contains "$output" "Updating ydl at $target" "update message is shown"
  assert_contains "$(cat "$target")" "ydl test source" "update replaces target"
}

test_bindir_override_is_respected() {
  local output target bindir
  bindir="$PWD/custom-bin"
  target="$bindir/ydl"

  output=$(YDL_BINDIR="$bindir" "$INSTALLER")

  assert_contains "$output" "Installing ydl to $target" "custom bin install message is shown"
  [[ -x "$target" ]] || fail "custom bin target is written"
}

test_legacy_install_is_removed() {
  local output legacy
  legacy="$YDL_LEGACY_TARGET"
  mkdir -p "${legacy:h}"
  print -r -- "# ydl — video downloader wrapper for yt-dlp" > "$legacy"
  print -r -- "legacy ydl" >> "$legacy"
  chmod +x "$legacy"

  output=$("$INSTALLER")

  assert_contains "$output" "Removing legacy ydl at $legacy" "legacy install removal is reported"
  [[ ! -e "$legacy" ]] || fail "legacy install is removed"
}

test_unrecognized_legacy_path_is_preserved() {
  local output legacy
  legacy="$YDL_LEGACY_TARGET"
  mkdir -p "${legacy:h}"
  print -r -- "user script named ydl" > "$legacy"
  chmod +x "$legacy"

  output=$("$INSTALLER")

  assert_contains "$output" "does not look like this ydl script; leaving it in place" "unrecognized legacy path is reported"
  [[ -e "$legacy" ]] || fail "unrecognized legacy path is preserved"
  assert_contains "$(cat "$legacy")" "user script named ydl" "unrecognized legacy content is preserved"
}

test_legacy_path_matching_target_is_preserved() {
  local output target
  target="$YDL_TEST_PREFIX/bin/ydl"
  print -r -- "old target" > "$target"
  chmod +x "$target"

  output=$(YDL_LEGACY_TARGET="$target" "$INSTALLER")

  assert_not_contains "$output" "Removing legacy ydl" "target path is not removed as legacy"
  [[ -x "$target" ]] || fail "target still exists after update"
  assert_contains "$(cat "$target")" "ydl test source" "target is updated"
}

with_tmp "installer non-macOS refusal" test_non_macos_refuses
with_tmp "installer missing Homebrew message" test_missing_homebrew_explains_install_url
with_tmp "installer installs all missing dependencies" test_all_dependencies_missing_are_installed
with_tmp "installer installs missing ffmpeg package" test_only_ffmpeg_dependency_missing_is_installed
with_tmp "installer skips brew when deps present" test_dependencies_present_skip_brew_install
with_tmp "installer first install message" test_first_install_message_and_target
with_tmp "installer update message" test_update_message_when_target_exists
with_tmp "installer respects YDL_BINDIR" test_bindir_override_is_respected
with_tmp "installer removes legacy install" test_legacy_install_is_removed
with_tmp "installer preserves unrecognized legacy path" test_unrecognized_legacy_path_is_preserved
with_tmp "installer preserves matching legacy target" test_legacy_path_matching_target_is_preserved

print -- "$TEST_COUNT installer tests passed"
