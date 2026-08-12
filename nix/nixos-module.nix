# NixOS module. The camera half is what needs a system: v4l2loopback is a kernel module, and
# the label and device number it is loaded with have to reach the command that writes into it.
# The microphone half needs none of that and is here only so both live behind one namespace
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.virtual-media-devices;
  cam = cfg.camera;
in
{
  options.services.virtual-media-devices = {
    camera = {
      enable = lib.mkEnableOption "the virtual camera (v4l2loopback)";

      label = lib.mkOption {
        type = lib.types.str;
        default = "Virtual Camera";
        description = ''
          The name applications show the device under. It is also what `virtual-cam` looks
          the device up by, so it is declared once here and travels to both
        '';
      };

      videoNr = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = ''
          The `/dev/videoN` the loopback takes. Pick a number well above the real cameras —
          v4l2loopback fails to load if the node is already taken
        '';
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "alice" ];
        description = ''
          Users to put in the `video` group. On a desktop this is not needed: systemd's
          `uaccess` tag hands `/dev/video*` to whoever holds the active local session. It is
          needed for a user that never gets one — over ssh, or from a system service
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.virtual-cam.override {
          inherit (cam) label;
          device = "/dev/video${toString cam.videoNr}";
        };
        defaultText = lib.literalExpression "virtual-cam pointed at the device below";
        description = "The package to install; it carries the label and the device";
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

  config = lib.mkMerge [
    (lib.mkIf cam.enable {
      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];

      # exclusive_caps=1 is needed so the device is detected as a camera by browsers/messengers
      boot.extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=${toString cam.videoNr} card_label="${cam.label}" exclusive_caps=1
      '';

      environment.systemPackages = [
        cam.package
        pkgs.v4l-utils
      ];

      # Declared here rather than left to the host config: the module has to carry what it
      # depends on, even where the host happens to grant it anyway
      users.users = lib.genAttrs cam.users (_: {
        extraGroups = [ "video" ];
      });
    })

    (lib.mkIf cfg.microphone.enable {
      environment.systemPackages = [ cfg.microphone.package ];
    })
  ];
}
