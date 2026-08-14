#!/usr/bin/env bash
# Runs both commands against the real PipeWire and the real v4l2loopback, and checks what
# the server and the kernel ended up with. tests/run.sh cannot: a stub pactl is a shell
# script echoing its arguments, while the real one re-parses source_properties inside
# itself — which is exactly where "Fake Mic" once arrived as "Fake"
#
# Nothing here runs in CI. It needs a session with sound and the loopback module loaded,
# so it is the check to run by hand before a tag
#
#   tests/live.sh                run both halves
#   VIRTUAL_MIC=... tests/live.sh   run the packaged commands instead of the scripts

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
CAM="${VIRTUAL_CAM:-$REPO/virtual-cam.sh}"
MIC="${VIRTUAL_MIC:-$REPO/virtual-mic.sh}"
DEVICE="${VIRTUAL_CAM_DEVICE:-/dev/video10}"

WORK=$(mktemp -d)
fails=0
pids=()

cleanup() {
  set +e
  for pid in "${pids[@]:-}"; do
    [[ -n $pid ]] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

ok() { printf '  ✓ %s\n' "$1"; }

fail() {
  printf '  ✗ %s\n' "$1"
  fails=$((fails + 1))
}

# The whole point is the real tools, so a missing one is a failure to run rather than a
# reason to skip quietly
for tool in ffmpeg pactl v4l2-ctl; do
  command -v "$tool" >/dev/null || {
    printf 'live: %s is not on PATH — this suite needs the real tools\n' "$tool" >&2
    # The usual absentee: pipewire-pulse speaks the protocol but ships no client, and the
    # copy virtual-mic uses comes from its package — which this suite bypasses
    [[ $tool == pactl ]] &&
      printf 'live: on PipeWire, run: nix shell nixpkgs#pulseaudio -c tests/live.sh\n' >&2
    exit 1
  }
done
pactl info >/dev/null 2>&1 || {
  echo "live: no sound server answering — start a session first" >&2
  exit 1
}

# Waits for a shell condition to come true, since neither the server nor the kernel is
# instantaneous — and returns as soon as it does, so a pass costs no time. The condition is
# a string re-evaluated each round: a pipeline built once would read a consumed fd on the
# second try and report the state of the first
until_true() {
  local tries=50
  while ((tries--)); do
    eval "$1" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

echo "live PipeWire and v4l2loopback"

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=440:duration=2" \
  "$WORK/tone.wav" || {
  echo "live: could not render the test tone" >&2
  exit 1
}
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=320x240:rate=10:duration=2" \
  -pix_fmt yuv420p "$WORK/clip.mp4" || {
  echo "live: could not render the test clip" >&2
  exit 1
}

# A two-word name is the case a stub cannot reproduce: pactl parses the proplist itself,
# so a name that survives the module-argument parser can still be cut at the space
"$MIC" --name "Fake Mic" "$WORK/tone.wav" >"$WORK/mic.log" 2>&1 &
pids+=($!)

if until_true 'pactl list sources | grep -q '"'"'device.description = "Fake Mic"'"'"; then
  ok 'the microphone description arrived whole ("Fake Mic", not "Fake")'
else
  fail 'no source described "Fake Mic" — the name was cut or none was created'
  sed 's/^/      /' "$WORK/mic.log"
fi

if pactl list sources short | grep -q virtual_mic; then
  ok "the source is named virtual_mic"
else
  fail "no source called virtual_mic"
fi

# Nothing may come out of the headphones: the module is a source, and a sink would be a
# different module with the same file
if pactl list sinks short | grep -q virtual_mic; then
  fail "a sink was created — the audio is audible"
else
  ok "no sink was created"
fi

kill "${pids[-1]}" 2>/dev/null
wait "${pids[-1]}" 2>/dev/null
pids=()

if until_true '! pactl list sources short | grep -q virtual_mic'; then
  ok "the source is gone once the command exits"
else
  fail "the source outlived the command"
fi

if [[ ! -e $DEVICE ]]; then
  printf '  — skipped the camera: %s does not exist, load v4l2loopback first\n' "$DEVICE"
else
  "$CAM" "$WORK/clip.mp4" >"$WORK/cam.log" 2>&1 &
  pids+=($!)

  if until_true "v4l2-ctl --list-devices | grep -q $DEVICE"; then
    ok "the loopback device is listed while the command runs"
  else
    fail "$DEVICE is not listed"
    sed 's/^/      /' "$WORK/cam.log"
  fi

  # The format the kernel reports is what a browser negotiates against, so an empty or
  # zero-sized one means the feed never started even though the device exists
  if until_true "v4l2-ctl -d $DEVICE --all | grep -qE 'Width/Height *: *[1-9]'"; then
    ok "the device reports a frame size, so ffmpeg is feeding it"
  else
    fail "the device reports no frame size"
    v4l2-ctl -d "$DEVICE" --get-fmt-video 2>&1 | sed 's/^/      /'
  fi

  kill "${pids[-1]}" 2>/dev/null
  wait "${pids[-1]}" 2>/dev/null
  pids=()

  # A media library is mostly symlinks, and the real file(1) calls one inode/symlink unless
  # it is told to follow it — which put a perfectly good video in the unsupported branch.
  # tests/run.sh can only check that -L is passed; whether it is needed is this half
  ln -s "$WORK/clip.mp4" "$WORK/link.mp4"
  "$CAM" "$WORK/link.mp4" >"$WORK/link.log" 2>&1 &
  pids+=($!)
  if until_true "grep -q 'video/' '$WORK/link.log'"; then
    ok "a symlinked video is read through the link"
  else
    fail "a symlinked video was not recognised"
    sed 's/^/      /' "$WORK/link.log"
  fi
  kill "${pids[-1]}" 2>/dev/null
  wait "${pids[-1]}" 2>/dev/null
  pids=()
fi

if ((fails)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
