#!/usr/bin/env bash
# Installer for virtual-media-devices on systems without Nix. Projects what the two
# packages install onto a plain prefix: the scripts under share/virtual-media-devices,
# a relative symlink for each in bin, and an install-manifest that --uninstall consumes.
# Components are additive: installing one never touches the other, and
# --uninstall --component takes one back out on its own
set -euo pipefail

here="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VERSION=$(cat "$here/VERSION")

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
COMPONENT="${COMPONENT:-all}"
VIDEO_NR="${VIDEO_NR:-10}"
LABEL="${LABEL:-Virtual Camera}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"

usage() {
  cat <<EOF
install virtual-media-devices $VERSION (virtual-cam and virtual-mic) into a prefix

Re-running a component converges it: a file a previous install of that component wrote
and this run does not is removed. The other component is never touched — install them
one at a time, take them out one at a time.

usage: ./install.sh [options]
  -h, --help        show this help and exit
  -v, --version     print the version and exit
      --prefix DIR  install prefix (default: $PREFIX; env PREFIX)
      --destdir DIR staging root: files land under DESTDIR/PREFIX and the closing
                    modprobe hint is not printed (env DESTDIR)
      --component C install cam, mic, or all (default: $COMPONENT)
      --uninstall   remove what a previous install wrote, by its manifest;
                    with --component C, only that component

The camera also needs the v4l2loopback kernel module; the line to load it is printed at
the end (env VIDEO_NR=$VIDEO_NR and LABEL="$LABEL" change what it says).

Runtime environment (read by the installed commands, not this script):
  VIRTUAL_CAM_LABEL   card label virtual-cam looks the device up by (default "Virtual Camera")
  VIRTUAL_CAM_DEVICE  device virtual-cam falls back to when the label is not found

Exit 0 done, 1 when the install could not be made — a dependency missing, a manifest
that cannot be written — and 2 on a usage error.
EOF
}

die() { # the request itself is wrong
  printf 'install.sh: %s\n' "$1" >&2
  exit 2
}

UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -v | --version)
      echo "virtual-media-devices $VERSION"
      exit 0
      ;;
    --prefix)
      # Not ${2:?}: that exits 1 with bash's own message, and a usage error is 2
      (($# >= 2)) || die "$1 needs a directory"
      PREFIX="$2"
      shift 2
      ;;
    --destdir)
      (($# >= 2)) || die "$1 needs a directory"
      DESTDIR="$2"
      shift 2
      ;;
    --component)
      (($# >= 2)) || die "$1 needs a component"
      COMPONENT="$2"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$PREFIX" == /* ]] || die "PREFIX must be absolute: $PREFIX"

case "$COMPONENT" in
  all | cam | mic) ;;
  *) die "component must be cam, mic, or all: $COMPONENT" ;;
esac

root="${DESTDIR%/}$PREFIX"
share_runtime="$PREFIX/share/virtual-media-devices"
share="${DESTDIR%/}$share_runtime"
manifest="$share/install-manifest"

in_scope() { # is component $1 covered by this run's selection?
  # `meta` owns the shared bookkeeping (the installed VERSION copy): every install
  # rewrites it, and only a full uninstall — or removing the last real component —
  # takes it out
  if ((UNINSTALL == 0)) && [[ "$1" == meta ]]; then return 0; fi
  [[ "$COMPONENT" == all || "$COMPONENT" == "$1" ]]
}

# --- manifest helpers ------------------------------------------------------------------
# Each line is `component path`: the component name first (it cannot contain a space),
# then the path it owns as its final runtime path (no DESTDIR) — the manifest ships
# inside a staged tree and stays correct wherever the tree ends up

old_entries=()
if [[ -f "$manifest" ]]; then
  mapfile -t old_entries < <(grep -v '^#' "$manifest")
fi

installed=()

put() { # put COMPONENT MODE SRC RUNTIME_DST — install one file and record its owner
  install -D -m "$2" "$3" "${DESTDIR%/}$4"
  installed+=("$1 $4")
}

lnk() { # lnk COMPONENT TARGET RUNTIME_DST — relative symlink into share, recorded
  install -d "$(dirname "${DESTDIR%/}$3")"
  ln -sfn "$2" "${DESTDIR%/}$3"
  installed+=("$1 $3")
}

prune() { # remove now-empty parents of RUNTIME_PATH, stopping at the prefix root
  local dir stop
  dir="$(dirname "${DESTDIR%/}$1")"
  stop="$root"
  while [[ "$dir" == "$stop"/* ]]; do
    rmdir "$dir" 2>/dev/null || break
    dir="$(dirname "$dir")"
  done
}

legacy_entries() {
  # Installs made before the manifest existed (<= 1.0.2) left no record; this is their
  # layout, kept for exactly one release after the manifest arrived — delete this
  # function in the release after that
  echo "cam $share_runtime/virtual-cam.sh"
  echo "cam $PREFIX/bin/virtual-cam"
  echo "mic $share_runtime/virtual-mic.sh"
  echo "mic $PREFIX/bin/virtual-mic"
}

# --- uninstall -------------------------------------------------------------------------

if ((UNINSTALL)); then
  entries=("${old_entries[@]}")
  had_manifest=1
  if [[ ! -f "$manifest" ]]; then
    had_manifest=0
    mapfile -t entries < <(legacy_entries)
  fi
  kept=()
  removed=0
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    comp="${entry%% *}"
    path="${entry#* }"
    if in_scope "$comp"; then
      if [[ -e "${DESTDIR%/}$path" || -L "${DESTDIR%/}$path" ]]; then
        rm -f "${DESTDIR%/}$path"
        removed=$((removed + 1))
      fi
      prune "$path"
    else
      kept+=("$entry")
    fi
  done
  # bookkeeping alone is not an install: when no real component remains, take the
  # meta entries (the VERSION copy) out with the last one
  real_left=0
  for entry in "${kept[@]}"; do
    [[ "${entry%% *}" == meta ]] || real_left=1
  done
  if ((real_left == 0)) && ((${#kept[@]})); then
    for entry in "${kept[@]}"; do
      rm -f "${DESTDIR%/}${entry#* }"
    done
    kept=()
  fi
  if ((had_manifest)) && ((${#kept[@]})); then
    {
      echo "# virtual-media-devices $VERSION install manifest"
      printf '%s\n' "${kept[@]}"
    } >"$manifest"
    echo "uninstalled the $COMPONENT component ($removed files); the rest stays"
  elif ((had_manifest)); then
    rm -f "$manifest"
    rmdir "$share" 2>/dev/null || true
    echo "uninstalled virtual-media-devices from $root"
  elif ((removed)); then
    echo "uninstalled the $COMPONENT component ($removed files, pre-manifest install)"
  else
    echo "virtual-media-devices: nothing to uninstall under $root"
  fi
  exit 0
fi

# --- preflight: refuse loudly, install nothing ----------------------------------------
# install deps: everything the installed commands shell out to — a command that cannot
# run is not an install, so any missing means collect them all, print the report, exit 1
# having written nothing. The v4l2loopback kernel module is the one platform dependency:
# it comes from the running kernel, not a package on PATH, so it warns and never refuses

missing=()

need() { # idempotent: ffmpeg is needed by both components and reported once
  command -v "$1" >/dev/null 2>&1 && return
  local m
  for m in "${missing[@]}"; do
    [[ "$m" == "$1" ]] && return
  done
  missing+=("$1")
}

need install
if in_scope cam; then
  need ffmpeg
  need v4l2-ctl
  need awk
  need file
fi
if in_scope mic; then
  need ffmpeg
  need pactl
fi

distro_id() {
  sed -n 's/^ID\(_LIKE\)\?=//p' "$OS_RELEASE" 2>/dev/null | tr -d '"' | tr '\n' ' '
}

pkg_for() { # pkg_for DISTRO BINARY — the official package carrying that binary
  case "$1:$2" in
    debian:ffmpeg | arch:ffmpeg) echo ffmpeg ;;
    fedora:ffmpeg) echo ffmpeg-free ;;
    *:v4l2-ctl) echo v4l-utils ;;
    debian:pactl | fedora:pactl) echo pulseaudio-utils ;;
    arch:pactl) echo libpulse ;;
    *:awk) echo gawk ;;
    *:file) echo file ;;
    *:install) echo coreutils ;;
    # An unknown distro gets the binary's own name — still a useful search term
    *) echo "$2" ;;
  esac
}

guidance() {
  # One recommended method per distro. Runnable lines are printed as `  $ command` —
  # two spaces, dollar, space — and the distro tests run exactly those lines, so this
  # text cannot rot silently. No -y/--noconfirm: a human is reading; the tests arrange
  # non-interactivity around the command, never inside it
  local family="$1" pkgs=()
  local seen=" " pkg
  for bin in "${missing[@]}"; do
    pkg=$(pkg_for "$family" "$bin")
    [[ "$seen" == *" $pkg "* ]] && continue
    seen+="$pkg "
    pkgs+=("$pkg")
  done
  case "$family" in
    arch)
      echo "Install them on Arch:"
      echo "  \$ sudo pacman -S --needed ${pkgs[*]}"
      ;;
    debian)
      echo "Install them on Debian/Ubuntu:"
      echo "  \$ sudo apt install ${pkgs[*]}"
      ;;
    fedora)
      echo "Install them on Fedora:"
      echo "  \$ sudo dnf install ${pkgs[*]}"
      ;;
    *)
      echo "Install with your package manager: ${pkgs[*]}"
      ;;
  esac
}

if ((${#missing[@]})); then
  family=""
  case " $(distro_id) " in
    *" arch "*) family=arch ;;
    *" debian "* | *" ubuntu "*) family=debian ;;
    *" fedora "*) family=fedora ;;
  esac
  {
    echo "install.sh: missing dependencies:"
    printf '  - %s\n' "${missing[@]}"
    echo
    guidance "$family"
  } >&2
  exit 1
fi

if in_scope cam && [[ ! -e /sys/module/v4l2loopback && -z "$DESTDIR" ]]; then
  echo "install.sh: v4l2loopback is not loaded (comes from your kernel, install proceeds)" >&2
fi

# --- install ---------------------------------------------------------------------------

if in_scope cam; then
  put cam 755 "$here/virtual-cam.sh" "$share_runtime/virtual-cam.sh"
  lnk cam ../share/virtual-media-devices/virtual-cam.sh "$PREFIX/bin/virtual-cam"
fi

if in_scope mic; then
  put mic 755 "$here/virtual-mic.sh" "$share_runtime/virtual-mic.sh"
  lnk mic ../share/virtual-media-devices/virtual-mic.sh "$PREFIX/bin/virtual-mic"
fi

# The per-component sweep: whatever a previous install of these components wrote and
# this run did not. Entries of the component outside this run's scope carry over
kept=()
for entry in "${old_entries[@]}"; do
  [[ -z "$entry" ]] && continue
  comp="${entry%% *}"
  path="${entry#* }"
  if in_scope "$comp"; then
    fresh=0
    for now in "${installed[@]}"; do
      [[ "$entry" == "$now" ]] && fresh=1
    done
    if ((fresh == 0)); then
      rm -f "${DESTDIR%/}$path"
      prune "$path"
    fi
  else
    kept+=("$entry")
  fi
done

install -d "$share"
install -m644 "$here/VERSION" "$share/VERSION"
installed+=("meta $share_runtime/VERSION")
{
  echo "# virtual-media-devices $VERSION install manifest"
  printf '%s\n' "${kept[@]}" "${installed[@]}"
} >"$manifest"

echo "installed virtual-media-devices $VERSION ($COMPONENT) — manifest: $manifest"

if in_scope cam && [[ -z "$DESTDIR" ]]; then
  cat <<EOF

virtual-cam needs the loopback device, which on most distros is:

  sudo modprobe v4l2loopback devices=1 video_nr=$VIDEO_NR card_label="$LABEL" exclusive_caps=1

To keep it across reboots put the same options in /etc/modprobe.d/v4l2loopback.conf and
v4l2loopback in /etc/modules-load.d. If you pick another number or label, tell the commands:

  export VIRTUAL_CAM_DEVICE=/dev/video$VIDEO_NR
  export VIRTUAL_CAM_LABEL="$LABEL"
EOF
fi
