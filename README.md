<div align="center">

# virtual-media-devices

**A virtual camera and a virtual microphone fed from ordinary media files** (｡･ω･｡)

![v4l2loopback](https://img.shields.io/badge/v4l2loopback-kernel-FCC624?style=flat&logo=linux&logoColor=black)
![PipeWire](https://img.shields.io/badge/PipeWire-source-4A90D9?style=flat)
![FFmpeg](https://img.shields.io/badge/FFmpeg-007808?style=flat&logo=ffmpeg&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/virtual-media-devices/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/virtual-media-devices/actions/workflows/build.yml)

</div>

This started because I wanted to Shazam a track I had as a file, and the web version of Shazam only listens to a microphone — there is no way to hand it a file. So the file became a microphone

That is the whole idea, and it works the same way for video. A page or an app asks for a camera or a mic; you give it one that plays your file on a loop. The real devices are untouched, nothing comes out of the headphones, and both sources live exactly as long as the command runs

```sh
virtual-mic track.mp3       # a microphone that plays track.mp3
virtual-cam clip.mp4        # a camera that plays clip.mp4
```

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

## Contents

- [The two commands](#the-two-commands)
- [With Nix](#with-nix)
- [NixOS module](#nixos-module)
- [Home Manager module](#home-manager-module)
- [Without Nix](#without-nix)
- [Options](#options)
- [Picking the device in an app](#picking-the-device-in-an-app)
- [Tests](#tests)
- [Layout](#layout)
- [License](#license)

## The two commands

`virtual-mic <audio-or-video>` creates a source with `module-pipe-source` and feeds a FIFO from ffmpeg. It is a **pure source**: no output device is created, so nothing is played into your headphones and nothing is echoed back. On Ctrl+C the source is unloaded and the FIFO removed

```
-n, --name <name>   the name apps show (default "Virtual-Mic")
```

`virtual-cam <video-or-image>` writes frames into a v4l2loopback device, which apps see as a regular camera. It takes video or a still image, loops it, and recomputes timestamps from the frame number so the picture does not stutter at the loop point. v4l2 carries no sound — that is what the mic is for

```
-d, --device <path> output device (default: found by label, else /dev/video10)
-f, --fps <n>       frame rate (default 30)
-m, --mirror        mirror horizontally, for apps that don't mirror the preview
```

## With Nix

No install needed:

```sh
nix run github:rokokol/virtual-media-devices#virtual-mic -- track.mp3
nix run github:rokokol/virtual-media-devices#virtual-cam -- clip.mp4
```

The camera still needs the kernel module — see [Without Nix](#without-nix) for the `modprobe` line, or let the NixOS module handle it

## NixOS module

```nix
{
  inputs.virtual-media-devices = {
    url = "github:rokokol/virtual-media-devices";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
{
  imports = [ inputs.virtual-media-devices.nixosModules.default ];

  services.virtual-media-devices = {
    camera.enable = true;
    microphone.enable = true;
  };
}
```

The camera half loads `v4l2loopback`, writes the `modprobe` options for it and installs `virtual-cam` already pointed at the device it just declared — the label and the number are named once and travel to both. The microphone half installs a command and touches nothing else

## Home Manager module

```nix
{
  imports = [ inputs.virtual-media-devices.homeManagerModules.default ];

  programs.virtual-media-devices = {
    camera.enable = true;
    microphone.enable = true;
  };
}
```

This installs commands and nothing more. `camera.enable` here does **not** load the kernel module — a user session cannot. Either use the NixOS module for that half, or load it by hand and point `VIRTUAL_CAM_DEVICE` at the node

## Without Nix

Both are plain bash. They need `ffmpeg`, `awk` and `coreutils`; the camera also needs `v4l2-ctl` (`v4l-utils`) and `file`, the microphone needs `pactl` (`pulseaudio-utils` — it drives PipeWire just as well)

```sh
git clone https://github.com/rokokol/virtual-media-devices
cd virtual-media-devices
sudo ./install.sh                 # or PREFIX=~/.local ./install.sh
```

The microphone works from here. The camera needs the loopback device:

```sh
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Virtual Camera" exclusive_caps=1
```

`exclusive_caps=1` is what makes browsers and messengers treat the node as a camera rather than an output. To keep it across reboots, put those options in `/etc/modprobe.d/v4l2loopback.conf` and `v4l2loopback` in `/etc/modules-load.d/`

On a desktop you do not need to be in the `video` group: systemd's `uaccess` rule hands `/dev/video*` to whoever holds the active local session. You do need it for a user that never gets one — over ssh, or from a system service

## Options

Both modules also take a `package`, so you can override or replace what gets installed

| Option | Default | |
| --- | --- | --- |
| `camera.enable` | `false` | NixOS: loads the kernel module and installs the command. HM: installs the command only |
| `camera.label` | `"Virtual Camera"` | NixOS only. The name apps show, and what `virtual-cam` finds the device by |
| `camera.videoNr` | `10` | NixOS only. Which `/dev/videoN` the loopback takes. Pick a number above your real cameras |
| `camera.users` | `[ ]` | NixOS only. Users to join the `video` group, for sessions `uaccess` never covers. A name absent from `users.users` gets a warning, not an error — it is usually a typo, but it is also how a user managed outside NixOS looks |
| `microphone.enable` | `false` | Installs the command |

There is deliberately nothing here for frame rate, mic name, sample rate or the number of loopback devices. An option exists to keep two places from disagreeing — the label and the device number are declared for `modprobe` *and* for the command, and that is the whole reason they are options. Anything that only shapes one run is a flag, and anything that only matters once is a decision the module makes: one loopback, `exclusive_caps=1`, 48000 Hz stereo. If you want a different v4l2loopback layout, load the kernel module yourself and use the package alone

The two settings reach the command as `VIRTUAL_CAM_LABEL` and `VIRTUAL_CAM_DEVICE`. They are baked into the wrapper with `--set-default`, so exporting either still wins

## Picking the device in an app

- **Browsers** show them as ordinary devices. Firefox asks per site; Chromium picks them up from the OS list. If the camera is missing, the module was loaded without `exclusive_caps=1`
- **Zoom, Discord, Telegram** — the usual device dropdown in the call settings
- **Check it yourself**: `ffplay /dev/video10` for the camera, `pavucontrol` → Recording for the microphone
- A running app usually does not notice a device that appeared after it started — start the command first, then open the app

## Tests

```sh
tests/run.sh              # 20 checks, no kernel module and no sound server
```

ffmpeg, pactl, v4l2-ctl and file are all stubbed, so what the suite checks is the command line each script builds — that command line *is* the product. The four camera cases are compared against golden files byte for byte: the filter chain ends in `setpts=N/(fps*TB)`, which is the one thing keeping the picture from stuttering at the loop point, and it should not change by accident. The device is an ordinary file in a scratch dir and `TMPDIR` points there too, so the FIFO the microphone creates cannot land in `/tmp`

`nix flake check` runs that suite plus the packaged wrappers reaching their tools from a bare `PATH`, both settings arriving in the wrapper (and an unset one *not* being baked in), and both modules evaluated against option stubs — including that the microphone half never touches the kernel and that everything can be turned back off

## Layout

```
virtual-cam.sh       the camera
virtual-mic.sh       the microphone
nix/                 package-cam.nix, package-mic.nix, nixos-module.nix, home-module.nix, module-test.nix
tests/               run.sh, the four stubs and the golden command lines
install.sh           for systems without Nix
```

## License

MIT
