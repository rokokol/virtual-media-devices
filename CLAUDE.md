# CLAUDE.md

## What this repo is

A virtual camera and a virtual microphone fed from ordinary media files. A page asks for a camera or a mic; it gets one playing your file on a loop. The camera writes into a `v4l2loopback` device, the microphone is a `module-pipe-source` fed from a FIFO — a pure source, so nothing comes out of the headphones and no sink is created. Both live exactly as long as the command runs

Two modules, because the halves need different layers. The camera needs a kernel module, so it is NixOS (`services.virtual-media-devices.camera`, enabled straight in `nixos/configuration-pc.nix` — no `rokokol.*` alias around someone else's `enable`); the microphone needs nothing system-wide and is the Home Manager seam `home-manager/programs/virtual-mic.nix`, on both hosts

## Build / check

```sh
nix build .#virtual-cam .#virtual-mic
nix flake check          # tests, the packaged wrappers, both modules, a real-nixpkgs eval, shell lint
./tests/run.sh           # stubbed tools in, the command lines the scripts build out
./tests/live.sh          # the real PipeWire and the real v4l2loopback
PREFIX=$PWD/out ./install.sh
nix fmt -- --ci
```

## Layout

```
virtual-cam.sh       the camera
virtual-mic.sh       the microphone
nix/                 package-cam.nix, package-mic.nix, nixos-module.nix, home-module.nix,
                     module-test.nix, nixos-eval.nix
tests/               run.sh, live.sh, the four stubs and the golden command lines
install.sh           for systems without Nix
```

## Things that will bite

- **`pactl` re-parses `source_properties` inside itself.** A name with a space needs two levels of quoting — the outer pair survives the module-argument parser, the inner one the proplist parser. With either missing, `--name "Fake Mic"` reaches the server as `Fake`, and no stub reproduces that. `tests/live.sh` is what catches it
- **`users.users.<name>.extraGroups` does not add to a group, it declares a user.** A name the host never declared fails the whole system on `Exactly one of isSystemUser and isNormalUser must be set`, an assertion that never mentions this module. Write to `users.groups.<group>.members` instead — and warn rather than assert about an unknown name, because a user created outside NixOS looks exactly the same
- **`camera.label` and `camera.videoNr` are declared once and used twice**, by modprobe and by the command that looks the device up (`VIRTUAL_CAM_LABEL`, `VIRTUAL_CAM_DEVICE`). That is why they are options and not two literals
- **`camera.users` duplicating the group membership in `huix` is deliberate** — a module declares its own dependencies rather than leaning on a line in someone else's configuration
- **the module is checked twice.** `nix/module-test.nix` against option stubs, `nix/nixos-eval.nix` inside a real `nixpkgs.lib.nixosSystem`, forcing `config.assertions` rather than `system.build.toplevel` — the assertions and warnings are values, and the check has to demand that a warning *names* the user. Keep `want 'keys == [ … ]'` first in each set: the field names are written twice, in Nix and in jq, and `jq` answers `true` for "missing == empty"

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date, tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
