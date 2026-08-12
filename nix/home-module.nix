# Home Manager module. It installs commands and nothing else — loading v4l2loopback and
# handing out group membership are system-level jobs, and the NixOS module does them
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.virtual-media-devices;
in
{
  options.programs.virtual-media-devices = {
    camera = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install `virtual-cam`. It writes into a v4l2loopback device that has to exist
          already — this module cannot create one. Use the NixOS module, or load the kernel
          module by hand and point `VIRTUAL_CAM_DEVICE` at the node
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.virtual-cam;
        defaultText = lib.literalExpression "pkgs.virtual-cam";
        description = "The package to install";
      };
    };

    microphone = {
      enable = lib.mkEnableOption "the virtual microphone (PipeWire/PulseAudio)";

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.virtual-mic;
        defaultText = lib.literalExpression "pkgs.virtual-mic";
        description = "The package to install";
      };
    };
  };

  config.home.packages =
    lib.optional cfg.camera.enable cfg.camera.package
    ++ lib.optional cfg.microphone.enable cfg.microphone.package;
}
