#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
VIDEO_NR="${VIDEO_NR:-10}"
LABEL="${LABEL:-Virtual Camera}"

usage() {
  cat <<EOF
install.sh — install virtual-cam and virtual-mic

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

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

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
share="$PREFIX/share/virtual-media-devices"

install -Dm755 "$here/virtual-cam.sh" "$share/virtual-cam.sh"
install -Dm755 "$here/virtual-mic.sh" "$share/virtual-mic.sh"

install -d "$PREFIX/bin"
ln -sfn ../share/virtual-media-devices/virtual-cam.sh "$PREFIX/bin/virtual-cam"
ln -sfn ../share/virtual-media-devices/virtual-mic.sh "$PREFIX/bin/virtual-mic"

echo "installed to $share, linked into $PREFIX/bin"
cat <<EOF

virtual-mic works as it is. virtual-cam needs the loopback device, which on most distros is:

  sudo modprobe v4l2loopback devices=1 video_nr=$VIDEO_NR card_label="$LABEL" exclusive_caps=1

To keep it across reboots put the same options in /etc/modprobe.d/v4l2loopback.conf and
v4l2loopback in /etc/modules-load.d. If you pick another number or label, tell the commands:

  export VIRTUAL_CAM_DEVICE=/dev/video$VIDEO_NR
  export VIRTUAL_CAM_LABEL="$LABEL"
EOF
