# Evaluates both modules against stubs for the option paths they write to, so the wiring is
# checked without pulling nixpkgs' module set or home-manager in. Produces the values they
# would emit; flake.nix turns them into assertions
{
  lib,
  pkgs,
  nixosModule,
  homeModule,
}:

let
  nixosStubs =
    { lib, ... }:
    {
      options = {
        boot.extraModulePackages = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        boot.kernelModules = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        boot.kernelPackages = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {
            v4l2loopback = "v4l2loopback-stub";
          };
        };
        boot.extraModprobeConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        environment.systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        users.users = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
        };
      };
    };

  homeStubs =
    { lib, ... }:
    {
      options.home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
    };

  eval =
    stubs: module: user:
    (lib.evalModules {
      modules = [
        stubs
        module
        user
      ];
      specialArgs = { inherit pkgs lib; };
    }).config;

  system = eval nixosStubs nixosModule;
  home = eval homeStubs homeModule;

  # Joined rather than indexed, so "installed nothing" fails the assertion instead of
  # blowing up during evaluation with an unhelpful list error
  names = packages: lib.concatMapStringsSep " " toString packages;

  wiredUp = system { services.virtual-media-devices.camera.enable = true; };

  tuned = system {
    services.virtual-media-devices.camera = {
      enable = true;
      label = "My Cam";
      videoNr = 42;
      users = [ "alice" ];
    };
  };

  micOnly = system { services.virtual-media-devices.microphone.enable = true; };
  off = system { services.virtual-media-devices = { }; };

  hmBoth = home {
    programs.virtual-media-devices = {
      camera.enable = true;
      microphone.enable = true;
    };
  };
  hmOff = home { programs.virtual-media-devices = { }; };
in
{
  package = names wiredUp.environment.systemPackages;
  kernelModules = wiredUp.boot.kernelModules;
  modprobe = wiredUp.boot.extraModprobeConfig;
  groups = wiredUp.users.users;

  tunedModprobe = tuned.boot.extraModprobeConfig;
  tunedPackage = toString tuned.services.virtual-media-devices.camera.package;
  tunedGroups = tuned.users.users.alice.extraGroups or [ ];

  # The microphone half has to stay clear of the kernel: enabling it alone must not load
  # a module or write a modprobe line
  micPackage = names micOnly.environment.systemPackages;
  micKernelModules = micOnly.boot.kernelModules;
  micModprobe = micOnly.boot.extraModprobeConfig;

  offPackages = off.environment.systemPackages;
  offKernelModules = off.boot.kernelModules;
  offModprobe = off.boot.extraModprobeConfig;
  offGroups = off.users.users;

  hmPackages = names hmBoth.home.packages;
  hmOffPackages = hmOff.home.packages;
}
