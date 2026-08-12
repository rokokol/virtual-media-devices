# The virtual-cam script plus the tools it shells out to. The two settings are baked into
# the wrapper rather than exported as session variables, so a change lands on the next
# rebuild instead of the next login
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  ffmpeg,
  file,
  gawk,
  v4l-utils,
  # Must match how v4l2loopback was loaded; the NixOS module passes what it gave modprobe
  label ? null,
  device ? null,
}:

let
  # Isolated, so editing the README doesn't rebuild the package
  script = builtins.path {
    name = "virtual-cam.sh";
    path = ../virtual-cam.sh;
  };

  # Left out when unset, so the script's own default stays the single source of it
  setDefault = var: value: lib.optionalString (value != null) ''--set-default ${var} "${value}"'';

  runtimeInputs = [
    coreutils
    ffmpeg
    file
    gawk
    v4l-utils
  ];
in

stdenvNoCC.mkDerivation {
  pname = "virtual-cam";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 ${script} $out/bin/virtual-cam
    patchShebangs $out/bin

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/virtual-cam \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      ${setDefault "VIRTUAL_CAM_LABEL" label} \
      ${setDefault "VIRTUAL_CAM_DEVICE" device}

    runHook postInstall
  '';

  meta = {
    description = "Loop a video or an image into a v4l2loopback camera";
    homepage = "https://github.com/rokokol/virtual-media-devices";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "virtual-cam";
  };
}
