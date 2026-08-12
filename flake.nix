{
  description = "A virtual camera and a virtual microphone fed from ordinary media files";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      # v4l2loopback is a Linux kernel module and module-pipe-source is a Linux sound server
      # module — there is nothing here that could work anywhere else
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Each piece isolated, so a README edit doesn't rebuild anything
      camScript = builtins.path {
        name = "virtual-cam.sh";
        path = ./virtual-cam.sh;
      };
      micScript = builtins.path {
        name = "virtual-mic.sh";
        path = ./virtual-mic.sh;
      };
      testsDir = builtins.path {
        name = "virtual-media-devices-tests";
        path = ./tests;
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = virtual-cam;
        virtual-cam = pkgs.callPackage ./nix/package-cam.nix { };
        virtual-mic = pkgs.callPackage ./nix/package-mic.nix { };
      });

      nixosModules.default = import ./nix/nixos-module.nix { inherit self; };
      homeManagerModules.default = import ./nix/home-module.nix { inherit self; };

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) virtual-cam virtual-mic;
        in
        {
          # The behaviour suite: stubbed tools in, the command lines the scripts build out
          tests =
            pkgs.runCommand "tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  diffutils
                  gnugrep
                  gnused
                ];
              }
              ''
                mkdir -p repo
                cp ${camScript} repo/virtual-cam.sh
                cp ${micScript} repo/virtual-mic.sh
                cp -r ${testsDir} repo/tests
                chmod -R +w repo
                patchShebangs repo
                bash repo/tests/run.sh
                touch $out
              '';

          # The wrapper is the whole difference between the repo and the package: it is what
          # makes ffmpeg, v4l2-ctl and pactl reachable from a session that has none of them
          package-smoke = pkgs.runCommand "package-smoke" { } ''
            # A deliberately bare PATH: gnugrep is the check's own tool, everything the
            # scripts need has to come from the wrappers or not at all
            export PATH=${
              lib.makeBinPath [
                virtual-cam
                virtual-mic
                pkgs.coreutils
                pkgs.gnugrep
              ]
            }

            virtual-cam --help | grep -F VIRTUAL_CAM_LABEL >/dev/null
            virtual-mic --help | grep -F Virtual-Mic >/dev/null

            # A device that cannot exist, so the run stops at a check rather than opening
            # anything. Captured rather than piped: the command exits non-zero on purpose,
            # and the builder runs under pipefail
            said=$(VIRTUAL_CAM_DEVICE=/dev/definitely-not-here virtual-cam "$PWD/nope" 2>&1 || true)
            echo "$said" | grep -F 'file not found' >/dev/null

            # …and with a readable file it gets as far as looking the device up, which
            # means v4l2-ctl and file both resolved from the wrapper
            touch here.mp4
            said=$(VIRTUAL_CAM_DEVICE=/dev/definitely-not-here virtual-cam here.mp4 2>&1 || true)
            echo "$said" | grep -F 'v4l2loopback' >/dev/null
            touch $out
          '';

          # Every setting the module exposes has to reach the script, or it is decoration
          package-settings =
            let
              tuned = virtual-cam.override {
                label = "My Cam";
                device = "/dev/video42";
              };
            in
            pkgs.runCommand "package-settings" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
              grep -q 'VIRTUAL_CAM_LABEL' ${tuned}/bin/virtual-cam \
                || { echo "the label never reached the wrapper"; exit 1; }
              grep -q '/dev/video42' ${tuned}/bin/virtual-cam \
                || { echo "the device never reached the wrapper"; exit 1; }
              # …and an unset setting leaves the script's own default as the single source of it
              if grep -q VIRTUAL_CAM ${virtual-cam}/bin/virtual-cam; then
                echo "an unset setting still got baked in"
                exit 1
              fi
              touch $out
            '';

          # Enabling a module has to be enough to get the command, and — for the camera —
          # the kernel module and a modprobe line that agrees with it
          module-wiring =
            let
              wiring = import ./nix/module-test.nix {
                inherit lib pkgs;
                nixosModule = self.nixosModules.default;
                homeModule = self.homeManagerModules.default;
              };
            in
            pkgs.runCommand "module-wiring"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON wiring;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "module wiring: $2"; exit 1; }; }

                want '.package | test("virtual-cam")' "no command installed"
                want '.kernelModules == ["v4l2loopback"]' "v4l2loopback is never loaded"
                want '.modprobe | test("video_nr=10")' "the device number never reached modprobe"
                want '.modprobe | test("card_label=\"Virtual Camera\"")' "the label never reached modprobe"
                want '.modprobe | test("exclusive_caps=1")' "browsers would not see it as a camera"

                # The label and the number are declared once and have to travel to both the
                # kernel module and the command that looks the device up — that duplication
                # going stale is the whole reason they are options
                want '.tunedModprobe | test("video_nr=42")' "a custom number did not reach modprobe"
                want '.tunedModprobe | test("card_label=\"My Cam\"")' "a custom label did not reach modprobe"
                want '.tunedPackage != .package' "the settings never reached the package"

                # The group is the module's own declaration, not something borrowed from the host
                want '.groups == []' "a group was handed out to nobody"
                want '.tunedGroups == ["alice"]' "a named user did not reach the video group"

                # The microphone half must not drag the kernel in
                want '.micPackage | test("virtual-mic")' "no microphone installed"
                want '.micKernelModules == []' "the microphone loaded a kernel module"
                want '.micModprobe == ""' "the microphone wrote a modprobe line"

                # …and everything can be turned off
                want '.offPackages == []' "a command is installed while disabled"
                want '.offKernelModules == []' "v4l2loopback loads while disabled"
                want '.offModprobe == ""' "a modprobe line survives disabling"
                want '.offGroups == {}' "a group survives disabling"

                want '.hmPackages | test("virtual-cam")' "the HM module installs no camera"
                want '.hmPackages | test("virtual-mic")' "the HM module installs no microphone"
                want '.hmOffPackages == []' "the HM module installs while disabled"
                touch $out
              '';

          # The stub test above cannot see this: a stubbed option accepts anything, so a
          # module that writes to the wrong one still passes it. Here the real module set
          # gets to refuse
          nixos-eval =
            let
              real = import ./nix/nixos-eval.nix {
                inherit lib nixpkgs;
                system = pkgs.stdenv.hostPlatform.system;
                module = self.nixosModules.default;
              };
            in
            pkgs.runCommand "nixos-eval"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON real;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "nixos eval: $2"; exit 1; }; }

                # Naming a user the host never declared used to fail the whole system on
                # "Exactly one of isSystemUser and isNormalUser must be set" — an assertion
                # that never mentions this module
                want '.undeclaredBroken == []' "a user declared nowhere breaks the system"
                want '.undeclaredMembers == ["ghost"]' "the named user did not reach the group"

                # …and since that membership grants nobody anything, it has to say so: a typo
                # in the name is otherwise completely silent
                want '.undeclaredWarnings | length == 1' "an undeclared user passed without a warning"
                want '.undeclaredWarnings[0] | test("ghost")' "the warning does not name the user"
                want '.undeclaredModprobe | test("v4l2loopback")' "the camera did not configure the module"

                want '.declaredBroken == []' "a declared user breaks the system"
                want '.declaredMembers == ["ghost"]' "a declared user did not reach the group"
                want '.declaredWarnings == []' "a declared user was warned about anyway"

                # video is a stock group with a fixed gid — join it, do not shadow it
                want '.videoGid == .stockVideoGid' "the module shadowed the stock video group"

                want '.offWarnings == []' "a warning survives disabling"
                want '.offMembers == []' "a group member survives disabling"
                want '.offKernelModules == false' "v4l2loopback loads while disabled"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                ];
              }
              ''
                files="${camScript} ${micScript} ${testsDir}/run.sh ${testsDir}/stub/*"
                # shellcheck disable=SC2086
                shellcheck $files
                # shellcheck disable=SC2086
                shfmt -d -i 2 -ci $files
                touch $out
              '';
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            ffmpeg
            pulseaudio
            shellcheck
            shfmt
            v4l-utils
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
