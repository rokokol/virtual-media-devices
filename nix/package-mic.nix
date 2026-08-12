# The virtual-mic script plus the tools it shells out to. It takes no settings: nothing about
# it has to agree with anything outside the run, so what would be an option here is a flag
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  ffmpeg,
  pulseaudio,
}:

let
  # Isolated, so editing the README doesn't rebuild the package
  script = builtins.path {
    name = "virtual-mic.sh";
    path = ../virtual-mic.sh;
  };

  # pactl from pulseaudio drives pipewire-pulse just as well — it is the same protocol
  runtimeInputs = [
    coreutils
    ffmpeg
    pulseaudio
  ];
in

stdenvNoCC.mkDerivation {
  pname = "virtual-mic";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 ${script} $out/bin/virtual-mic
    patchShebangs $out/bin

    wrapProgram $out/bin/virtual-mic \
      --prefix PATH : ${lib.makeBinPath runtimeInputs}

    runHook postInstall
  '';

  meta = {
    description = "Loop an audio file into a virtual microphone (PipeWire/PulseAudio)";
    homepage = "https://github.com/rokokol/virtual-media-devices";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "virtual-mic";
  };
}
