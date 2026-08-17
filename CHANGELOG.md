# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

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
