# Evaluates the NixOS module inside a real nixpkgs module set, not against stubs. The stub
# test in module-test.nix answers "does the option reach the config"; this one answers
# "would nixpkgs accept the config at all" — a stub for users.groups takes anything, while
# the real module set has assertions, and a module that writes to the wrong option there
# fails a whole system with an error that never names this module.
#
# What gets forced is config.assertions, not system.build.toplevel: the assertions are the
# thing under test, and forcing the toplevel drvPath instead walks the entire derivation
# graph of a NixOS system — minutes per config, for no extra coverage
{
  lib,
  nixpkgs,
  system,
  module,
}:

let
  # The smallest config nixpkgs will call a system: without a root filesystem and a
  # bootloader decision, evaluation stops before it reaches anything of ours
  base = {
    nixpkgs.hostPlatform = system;
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
    system.stateVersion = "25.11";
  };

  evalWith =
    user:
    (nixpkgs.lib.nixosSystem {
      modules = [
        module
        base
        user
      ];
    }).config;

  broken = config: map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);

  # A user named in camera.users and declared nowhere else — the case that used to fail
  undeclared = evalWith {
    services.virtual-media-devices.camera = {
      enable = true;
      users = [ "ghost" ];
    };
  };

  declared = evalWith {
    users.users.ghost.isNormalUser = true;
    services.virtual-media-devices.camera = {
      enable = true;
      users = [ "ghost" ];
    };
  };

  off = evalWith { };
in
{
  undeclaredBroken = broken undeclared;
  undeclaredWarnings = undeclared.warnings;
  undeclaredMembers = undeclared.users.groups.video.members;
  undeclaredModprobe = undeclared.boot.extraModprobeConfig;

  declaredBroken = broken declared;
  declaredWarnings = declared.warnings;
  declaredMembers = declared.users.groups.video.members;

  # The group exists in stock nixpkgs with a fixed gid; the module must join it rather than
  # shadow it with one of its own
  videoGid = undeclared.users.groups.video.gid;
  stockVideoGid = off.users.groups.video.gid;

  offWarnings = off.warnings;
  offMembers = off.users.groups.video.members;
  offKernelModules = lib.elem "v4l2loopback" off.boot.kernelModules;
}
