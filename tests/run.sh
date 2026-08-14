#!/usr/bin/env bash
# Drives both commands against stubbed ffmpeg/pactl/v4l2-ctl/file and checks the command
# lines they build — that is the whole product, everything else is argument parsing.
#
# Nothing here touches a kernel module or a sound server: the device is an ordinary file in
# a scratch dir, and TMPDIR points there too, so the fifo the mic creates cannot land in /tmp

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
CAM="${VIRTUAL_CAM:-$REPO/virtual-cam.sh}"
MIC="${VIRTUAL_MIC:-$REPO/virtual-mic.sh}"
GOLDEN="$HERE/golden"

update=0
[[ "${1:-}" == "--update" ]] && update=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The stubs shadow the real tools, and TMPDIR keeps the fifo inside the scratch dir
export PATH="$HERE/stub:$PATH"
export TMPDIR="$WORK"

# A stub that is not executable, or one the PATH does not reach first, silently hands the
# suite the real tool — and for pactl and v4l2-ctl that is the live server and a real device
for stub in "$HERE"/stub/*; do
  tool=$(basename "$stub")
  if [[ ! -x $stub ]]; then
    printf 'tests/stub/%s is not executable\n' "$tool" >&2
    exit 1
  fi
  if [[ "$(command -v "$tool")" != "$stub" ]]; then
    printf '%s resolves to %s, not to the stub\n' "$tool" "$(command -v "$tool")" >&2
    exit 1
  fi
done

fails=0
case_name=""

fail() {
  printf '  ✗ %s: %s\n' "$case_name" "$1"
  fails=$((fails + 1))
}

ok() {
  printf '  ✓ %s\n' "$case_name"
}

# A scratch world per case: a fake device node, a fake input file and empty logs. Every
# variable the stubs read is reset here, so a case can never inherit another's setup
world() {
  case_name="$1"
  rm -rf "${WORK:?}"/*
  dev="$WORK/video10"
  src="$WORK/input"
  touch "$dev" "$src"
  export FFMPEG_ARGV="$WORK/ffmpeg.argv"
  export PACTL_LOG="$WORK/pactl.log"
  export FILE_ARGV="$WORK/file.argv"
  : >"$FFMPEG_ARGV"
  : >"$PACTL_LOG"
  : >"$FILE_ARGV"
  export FILE_MIME=video/mp4
  unset VIRTUAL_CAM_LABEL VIRTUAL_CAM_DEVICE V4L2_CTL_LISTING PACTL_FAIL
}

# The listing v4l2-ctl serves, written in its real shape: a card line, then tab-indented nodes
listing() {
  export V4L2_CTL_LISTING="$1 (platform:v4l2loopback-000):
	$dev
"
}

# Paths carry the scratch dir, which changes every run — strip it so a golden file is a
# statement about the command line rather than about where the suite happened to run
argv() {
  sed "s|$WORK/||g" "$FFMPEG_ARGV"
}

# Compares against tests/golden/<name>.txt; --update rewrites them instead
golden() {
  local want="$GOLDEN/$1.txt"
  if [[ $update == 1 ]]; then
    mkdir -p "$GOLDEN"
    argv >"$want"
    printf '  … %s updated\n' "$case_name"
    return
  fi
  if diff -u "$want" <(argv) >"$WORK/diff" 2>&1; then
    ok
  else
    fail "ffmpeg was called differently$(printf '\n')$(cat "$WORK/diff")"
  fi
}

# The device is the last thing on an ffmpeg command line in both branches
device_used() {
  tail -1 "$FFMPEG_ARGV"
}

echo "camera — command line"

world cam-video
"$CAM" -d "$dev" "$src" >/dev/null
golden cam-video

world cam-image
FILE_MIME=image/png "$CAM" -d "$dev" "$src" >/dev/null
golden cam-image

world cam-mirror
"$CAM" --mirror -d "$dev" "$src" >/dev/null
golden cam-mirror

world cam-fps
"$CAM" --fps 24 -d "$dev" "$src" >/dev/null
golden cam-fps

echo "camera — device resolution"

world cam-finds-by-label
listing "Virtual Camera"
"$CAM" "$src" >/dev/null
if [[ "$(device_used)" == "$dev" ]]; then
  ok
else
  fail "the default label did not find the device"
fi

world cam-honours-label-variable
listing "My Cam"
VIRTUAL_CAM_LABEL="My Cam" "$CAM" "$src" >/dev/null
if [[ "$(device_used)" == "$dev" ]]; then
  ok
else
  fail "VIRTUAL_CAM_LABEL was not what got looked up"
fi

world cam-label-variable-must-match
listing "Some Other Camera"
if VIRTUAL_CAM_LABEL="My Cam" VIRTUAL_CAM_DEVICE=/dev/does-not-exist "$CAM" "$src" >/dev/null 2>&1; then
  fail "a listing without the label was matched anyway"
else
  ok
fi

world cam-falls-back-to-device-variable
export V4L2_CTL_LISTING=""
VIRTUAL_CAM_DEVICE="$dev" "$CAM" "$src" >/dev/null
if [[ "$(device_used)" == "$dev" ]]; then
  ok
else
  fail "VIRTUAL_CAM_DEVICE was not the fallback"
fi

world cam-flag-beats-both
listing "Virtual Camera"
other="$WORK/video11"
touch "$other"
VIRTUAL_CAM_DEVICE="$dev" "$CAM" -d "$other" "$src" >/dev/null
if [[ "$(device_used)" == "$other" ]]; then
  ok
else
  fail "--device lost to the label or the variable"
fi

world cam-missing-device
export V4L2_CTL_LISTING=""
if VIRTUAL_CAM_DEVICE="$WORK/nothing" "$CAM" "$src" >/dev/null 2>&1; then
  fail "a device that does not exist was accepted"
else
  ok
fi

echo "camera — input"

world cam-unsupported-mime
if FILE_MIME=application/pdf "$CAM" -d "$dev" "$src" >/dev/null 2>&1; then
  fail "a non-media file was accepted"
else
  ok
fi

# file(1) does not follow a symlink unless it is told to, and answers inode/symlink — which
# lands in the unsupported branch. A stub cannot show that, so what is checked here is the
# flag; that the real file(1) needs it is checked in tests/live.sh
world cam-asks-file-to-follow-symlinks
"$CAM" -d "$dev" "$src" >/dev/null
if grep -qx -- '-L' "$FILE_ARGV"; then
  ok
else
  fail "file was called without -L: $(tr '\n' ' ' <"$FILE_ARGV")"
fi

world cam-missing-file
if "$CAM" -d "$dev" "$WORK/absent" >/dev/null 2>&1; then
  fail "a missing file was accepted"
else
  ok
fi

world cam-no-file
if "$CAM" -d "$dev" >/dev/null 2>&1; then
  fail "no file at all was accepted"
else
  ok
fi

world cam-help-documents-variables
help=$("$CAM" --help)
if [[ "$help" == *VIRTUAL_CAM_LABEL* && "$help" == *VIRTUAL_CAM_DEVICE* ]]; then
  ok
else
  fail "--help does not name both variables"
fi

echo "microphone"

world mic-creates-source
"$MIC" "$src" >/dev/null
load=$(grep '^load-module|' "$PACTL_LOG" || true)
if [[ "$load" == *"|module-pipe-source|"* && "$load" == *"|source_name=virtual_mic|"* &&
  "$load" == *"|format=s16le|"* && "$load" == *"|rate=48000|"* && "$load" == *"|channels=2|"* ]]; then
  ok
else
  fail "the source was not created as a s16le 48000/2 pipe source: $load"
fi

world mic-name-reaches-description
"$MIC" --name FakeMic "$src" >/dev/null
if grep -qF 'device.description=\"FakeMic\"' "$PACTL_LOG"; then
  ok
else
  fail "--name never reached the description"
fi

# A space in the name used to be silently cut at the space by the module-argument parser:
# the description has to arrive quoted at both levels or "Fake Mic" shows up as "Fake".
# The pipes around the field are the assertion — inside one argument the two words are still
# one argument, and that is the thing the quoting is for. Whether the server then keeps them
# together is pactl's own parser, which no stub reproduces: tests/live.sh checks that half
world mic-name-survives-a-space
"$MIC" --name "Fake Mic" "$src" >/dev/null
if grep -qF '|source_properties="device.description=\"Fake Mic\""' "$PACTL_LOG"; then
  ok
else
  fail "a name with a space did not arrive as one argument: $(grep '^load-module|' "$PACTL_LOG")"
fi

world mic-name-rejects-a-quote
if "$MIC" --name 'Fa"ke' "$src" >/dev/null 2>&1; then
  fail "a name with a double quote was accepted"
else
  ok
fi

world mic-feeds-the-fifo
"$MIC" "$src" >/dev/null
fifo=$(tail -1 "$FFMPEG_ARGV")
if [[ "$fifo" == "$WORK/"* ]]; then
  ok
else
  fail "ffmpeg wrote somewhere other than the fifo in TMPDIR: $fifo"
fi

world mic-cleans-up
"$MIC" "$src" >/dev/null
fifo=$(tail -1 "$FFMPEG_ARGV")
if grep -qF 'unload-module|42' "$PACTL_LOG" && [[ ! -e "$fifo" ]]; then
  ok
else
  fail "the source or the fifo outlived the command"
fi

# The server can refuse: no such module, or none of the caller's business. Real pactl says so
# with an exit code, and everything after it in the script is written as if the source exists
world mic-survives-a-refused-module
if PACTL_FAIL=load-module "$MIC" "$src" >/dev/null 2>&1; then
  fail "a refused load-module was reported as success"
elif [[ -n "$(find "$WORK" -name 'virtual-mic.*.fifo' -print -quit)" ]]; then
  fail "the fifo outlived a refused load-module"
elif grep -q '^unload-module|' "$PACTL_LOG"; then
  fail "a module that was never created was unloaded anyway"
else
  ok
fi

world mic-missing-file
if "$MIC" "$WORK/absent" >/dev/null 2>&1; then
  fail "a missing file was accepted"
else
  ok
fi

world mic-no-file
if "$MIC" >/dev/null 2>&1; then
  fail "no file at all was accepted"
else
  ok
fi

if [[ $fails -gt 0 ]]; then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
