# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Changed

- `install.sh` now exits 2, not 1, on a usage error — an unknown flag, a relative `--prefix`, or an invalid `--component` value — and `--help` ends with the `Exit` sentence naming every code it can produce; a missing dependency in the preflight still exits 1

## [1.1.0] - 2026-09-01

### Changed

- `install.sh` reworked onto the [huix-standard](https://github.com/rokokol/huix-standard) grammar: `-h`/`-v` short flags, and a preflight that installs nothing — the tools the commands shell out to (ffmpeg, v4l2-ctl, pactl, awk, file) are collected per component and refused with exact per-distro install commands; the v4l2loopback kernel module stays a warning, it comes from the kernel and not a package. Components stay additive, each converging its own files on a re-run

### Added

- `VERSION` at the repo root as the one source of version: both packages read it, `install.sh -v|--version` prints it, CI asserts the changelog heading matches
- `./install.sh --uninstall` removes an install by its manifest at `share/virtual-media-devices/install-manifest` — `--uninstall --component mic` takes one command out and keeps the other; installs made before the manifest existed fall back to the known layout for this one release
- tab completion for the installer, `source completions/install.sh.{bash,zsh}`, drift-checked against `install.sh` by `tests/check-completions.sh`
- `tests/installer.sh` — the installer's contract as a fast suite, also run by `nix flake check`: manifest, per-component sweep, selective uninstall, staging, the refusal path with its per-distro guidance
- `tests/distro.sh` — the full preflight→guidance→install→uninstall cycle inside real `debian`, `ubuntu`, `arch` and `fedora` containers, where the printed guidance really installs ffmpeg and friends; the smoke never opens `/dev/video*` (no container has the kernel module — that half stays `tests/live.sh`'s). Four per-distro CI badges (push, weekly cron, never pull requests)

## [1.0.2] - 2026-08-18

### Changed

- `install.sh` accepts `DESTDIR` independently of `PREFIX` and can install only the `cam` or `mic` component for split packages

### Documentation

- the README says why the microphone talks to the server through `pactl` and not through anything PipeWire-native, with the measurements behind the choice

## [1.0.1] - 2026-08-14

### Fixed

- `virtual-cam` plays a symlinked file: `file` is now asked to follow the link instead of calling it `inode/symlink` and refusing it as an unsupported type

### Changed

- the `pactl` stub separates its logged arguments with a pipe and can be told to refuse a call, so the suite sees where one argument ends and can drive the path where the server says no

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where the two scripts and the modprobe line lived in the services directory

### Added

- `virtual-cam` and `virtual-mic`: a media file as a camera or a microphone, for as long as the command runs
- the microphone as a pure `module-pipe-source`, so nothing reaches the headphones and no sink is created
- `nixosModules.default` for the camera (it needs `v4l2loopback`) and `homeModules.default` for the microphone, which needs no system layer, plus `overlays.default`
- `camera.label` and `camera.videoNr` declared once and delivered to both modprobe and the command
- checks: the suite against four stubs with golden command lines, the packaged wrappers, both modules against option stubs and the NixOS one inside a real nixpkgs module set
- `tests/live.sh`, which runs both commands against the real PipeWire and the real v4l2loopback
