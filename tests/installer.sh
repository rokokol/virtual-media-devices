#!/usr/bin/env bash
# The fast suite for install.sh: flag surface, the manifest contract, the per-component
# sweep, selective uninstall, staging, and the refusal path — everything that needs no
# container. tests/run.sh drives the two commands against stubs; tests/distro.sh covers
# what a real distribution provides; this covers what the installer promises
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO="${1:-$(dirname "$HERE")}"

fails=0
say() { printf -- '-- %s\n' "$1"; }
die() {
  printf '!! %s\n' "$1" >&2
  fails=$((fails + 1))
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

prefix="$tmp/prefix"
manifest="$prefix/share/virtual-media-devices/install-manifest"
run() { "$REPO/install.sh" --prefix "$prefix" "$@"; }

say "--help names every flag the case parses, and -v matches VERSION"
mapfile -t flags < <(
  sed -n 's/^ *\(-[-a-zA-Z0-9 |]*\))$/\1/p' "$REPO/install.sh" |
    tr '|' '\n' | tr -d ' ' | sort -u
)
((${#flags[@]})) || die "found no flags in install.sh — the extractor is broken"
help_out=$("$REPO/install.sh" --help)
for flag in "${flags[@]}"; do
  grep -qF -- "$flag" <<<"$help_out" || die "--help does not mention $flag"
done
[[ "$("$REPO/install.sh" -v)" == "virtual-media-devices $(cat "$REPO/VERSION")" ]] ||
  die "-v does not print 'virtual-media-devices \$(cat VERSION)'"

say "bad arguments are refused"
if run --prefix relative/path >/dev/null 2>&1; then die "a relative PREFIX was accepted"; fi
if run --component speaker >/dev/null 2>&1; then die "an unknown component was accepted"; fi
if run --no-such-flag >/dev/null 2>&1; then die "an unknown flag was accepted"; fi

# The dev/sandbox machine may lack the runtime deps the preflight demands; a stub PATH
# with everything present keeps the install tests about installing. The refusal test
# below then removes tools from this same PATH
full="$tmp/full-bin"
mkdir -p "$full"
for tool in bash cat dirname readlink sed tr grep rm rmdir install ln mkdir sort find; do
  ln -s "$(command -v "$tool")" "$full/$tool"
done
for fake in ffmpeg v4l2-ctl pactl awk file; do
  printf '#!/bin/sh\nexit 0\n' >"$full/$fake"
  chmod +x "$full/$fake"
done
irun() { PATH="$full" bash "$REPO/install.sh" --prefix "$prefix" "$@"; }

say "a full install lands both commands and the manifest"
irun >/dev/null
[[ -f "$prefix/share/virtual-media-devices/virtual-cam.sh" ]] || die "cam script missing"
[[ -f "$prefix/share/virtual-media-devices/virtual-mic.sh" ]] || die "mic script missing"
[[ -L "$prefix/bin/virtual-cam" ]] || die "virtual-cam symlink missing"
[[ -L "$prefix/bin/virtual-mic" ]] || die "virtual-mic symlink missing"
[[ "$(readlink "$prefix/bin/virtual-cam")" == ../share/virtual-media-devices/virtual-cam.sh ]] ||
  die "the bin symlink is not relative"
[[ -f "$manifest" ]] || die "no manifest after install"
for comp in cam mic meta; do
  grep -q "^$comp " "$manifest" || die "manifest has no $comp entries"
done

say "--uninstall --component mic removes one command and keeps the other"
irun --uninstall --component mic >/dev/null
[[ ! -e "$prefix/bin/virtual-mic" && ! -e "$prefix/share/virtual-media-devices/virtual-mic.sh" ]] ||
  die "selective uninstall left the mic"
[[ -L "$prefix/bin/virtual-cam" ]] || die "selective uninstall took the cam"
if grep -q '^mic ' "$manifest"; then die "manifest still claims mic"; fi
grep -q '^meta ' "$manifest" || die "meta entries lost on selective uninstall"

say "removing the last real component takes the bookkeeping with it"
irun --uninstall --component cam >/dev/null
[[ ! -e "$prefix/share/virtual-media-devices" ]] ||
  die "the manifest dir outlived the last component"
[[ ! -e "$prefix/bin/virtual-cam" ]] || die "cam left behind"

say "re-running a component sweeps its stale files and touches no other component"
irun >/dev/null
stale="$prefix/share/virtual-media-devices/virtual-cam-old.sh"
touch "$stale"
echo "cam $stale" >>"$manifest"
irun --component cam >/dev/null
[[ ! -e "$stale" ]] || die "the sweep left a stale file behind"
if grep -qF "virtual-cam-old" "$manifest"; then die "manifest still lists the stale file"; fi
[[ -L "$prefix/bin/virtual-mic" ]] || die "installing cam disturbed mic"

say "--uninstall takes everything out and is idempotent"
irun --uninstall >/dev/null
[[ ! -e "$prefix/share/virtual-media-devices" ]] || die "uninstall left the share dir"
[[ ! -e "$prefix/bin/virtual-cam" && ! -e "$prefix/bin/virtual-mic" ]] ||
  die "uninstall left the symlinks"
out=$(irun --uninstall)
[[ "$out" == *"nothing to uninstall"* ]] || die "a second uninstall was not quiet: $out"

say "a pre-manifest install is still uninstallable (fallback layout)"
install -D -m755 "$REPO/virtual-cam.sh" "$prefix/share/virtual-media-devices/virtual-cam.sh"
install -d "$prefix/bin"
ln -sfn ../share/virtual-media-devices/virtual-cam.sh "$prefix/bin/virtual-cam"
irun --uninstall >/dev/null
[[ ! -e "$prefix/bin/virtual-cam" && ! -e "$prefix/share/virtual-media-devices" ]] ||
  die "legacy uninstall missed the pre-manifest layout"

say "DESTDIR stages the tree, mutes the modprobe hint, and records runtime paths"
stage="$tmp/stage"
out=$(irun --destdir "$stage")
[[ -f "$stage$prefix/share/virtual-media-devices/virtual-cam.sh" ]] ||
  die "staged file not under DESTDIR"
[[ "$out" != *"modprobe"* ]] || die "a staged install printed the live modprobe hint"
staged_manifest="$stage$prefix/share/virtual-media-devices/install-manifest"
[[ -f "$staged_manifest" ]] || die "no staged manifest"
if grep -v '^#' "$staged_manifest" | grep -qF "$stage"; then
  die "the staged manifest leaks DESTDIR into a recorded path"
fi

say "the preflight refuses completely when runtime deps are missing"
rm "$full/ffmpeg" "$full/pactl" "$full/v4l2-ctl"
echo "ID=debian" >"$tmp/os-release" # the flake-check sandbox has no /etc/os-release
rc=0
out=$(OS_RELEASE="$tmp/os-release" PATH="$full" bash "$REPO/install.sh" \
  --prefix "$tmp/refused" 2>&1) || rc=$?
((rc != 0)) || die "the preflight accepted a system without ffmpeg"
grep -q 'missing dependencies' <<<"$out" || die "the refusal did not say what is missing"
grep -q ' - ffmpeg$' <<<"$out" || die "the refusal did not name ffmpeg"
grep -q ' - pactl$' <<<"$out" || die "the refusal did not name pactl"
grep -q ' - v4l2-ctl$' <<<"$out" || die "the refusal did not name v4l2-ctl"
[[ ! -e "$tmp/refused" ]] || die "a refused install wrote files"

say "the guidance is per-distro, deduplicated, and printed as runnable lines"
for pair in "debian:  \$ sudo apt install ffmpeg v4l-utils pulseaudio-utils" \
  "ubuntu:  \$ sudo apt install ffmpeg v4l-utils pulseaudio-utils" \
  "arch:  \$ sudo pacman -S --needed ffmpeg v4l-utils libpulse" \
  "fedora:  \$ sudo dnf install ffmpeg-free v4l-utils pulseaudio-utils"; do
  id="${pair%%:*}"
  line="${pair#*:}"
  echo "ID=$id" >"$tmp/os-release"
  out=$(OS_RELEASE="$tmp/os-release" PATH="$full" bash "$REPO/install.sh" \
    --prefix "$tmp/refused" 2>&1) || true
  grep -qxF "$line" <<<"$out" || die "no '$line' in the $id refusal (got: $out)"
done
# ffmpeg is missing for both components, and must be asked for once, not twice
echo "ID=debian" >"$tmp/os-release"
out=$(OS_RELEASE="$tmp/os-release" PATH="$full" bash "$REPO/install.sh" \
  --prefix "$tmp/refused" 2>&1) || true
(($(grep -c 'ffmpeg' <<<"$out") <= 2)) || die "ffmpeg appears more than listed+guided once"

say "a mic-only install does not demand the camera's tools"
rm -f "$full/pactl"
printf '#!/bin/sh\nexit 0\n' >"$full/pactl" && chmod +x "$full/pactl"
printf '#!/bin/sh\nexit 0\n' >"$full/ffmpeg" && chmod +x "$full/ffmpeg"
# v4l2-ctl stays missing: cam would refuse, mic must not
irun --component mic >/dev/null || die "mic-only install refused over a cam-only dep"
irun --uninstall >/dev/null

say "install.sh and its completions agree"
bash "$HERE/check-completions.sh" "$REPO" >/dev/null || die "completions drift"

echo
if ((fails)); then
  echo "$fails failure(s)"
  exit 1
fi
echo "all install.sh checks passed"
