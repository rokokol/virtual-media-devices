#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
COMPONENT="${COMPONENT:-all}"
VIDEO_NR="${VIDEO_NR:-10}"
LABEL="${LABEL:-Virtual Camera}"

usage() {
  cat <<EOF
install.sh — install virtual-cam and virtual-mic

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)
  COMPONENT=$COMPONENT (override with COMPONENT=... or --component cam|mic|all)

The scripts go to \$PREFIX/share/virtual-media-devices, and \$PREFIX/bin gets a symlink to
each. Everything they need — ffmpeg, v4l2-ctl, pactl, file, awk — comes from your PATH.
The camera also needs the v4l2loopback kernel module; the line to load it is printed at
the end (VIDEO_NR=$VIDEO_NR and LABEL="$LABEL" change what it says)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    --destdir)
      DESTDIR="${2:?directory required}"
      shift 2
      ;;
    --component)
      COMPONENT="${2:?component required}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$DESTDIR" && "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute when DESTDIR is set: $PREFIX" >&2
  exit 1
fi

case "$COMPONENT" in
  all | cam | mic) ;;
  *)
    echo "install.sh: component must be cam, mic, or all: $COMPONENT" >&2
    exit 1
    ;;
esac

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root="${DESTDIR%/}$PREFIX"
share="$root/share/virtual-media-devices"

install -d "$share" "$root/bin"

if [[ "$COMPONENT" == all || "$COMPONENT" == cam ]]; then
  install -Dm755 "$here/virtual-cam.sh" "$share/virtual-cam.sh"
  ln -sfn ../share/virtual-media-devices/virtual-cam.sh "$root/bin/virtual-cam"
fi

if [[ "$COMPONENT" == all || "$COMPONENT" == mic ]]; then
  install -Dm755 "$here/virtual-mic.sh" "$share/virtual-mic.sh"
  ln -sfn ../share/virtual-media-devices/virtual-mic.sh "$root/bin/virtual-mic"
fi

echo "installed $COMPONENT component(s) to $share, linked into $root/bin"

if [[ "$COMPONENT" == all || "$COMPONENT" == cam ]]; then
  cat <<EOF

virtual-cam needs the loopback device, which on most distros is:

  sudo modprobe v4l2loopback devices=1 video_nr=$VIDEO_NR card_label="$LABEL" exclusive_caps=1

To keep it across reboots put the same options in /etc/modprobe.d/v4l2loopback.conf and
v4l2loopback in /etc/modules-load.d. If you pick another number or label, tell the commands:

  export VIRTUAL_CAM_DEVICE=/dev/video$VIDEO_NR
  export VIRTUAL_CAM_LABEL="$LABEL"
EOF
fi
