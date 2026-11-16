# Selkies: streams an X11 display to a browser (H.264 over WebSockets) and
# sends the browser's mouse and keyboard back. It replaces noVNC as the way
# a person watches or takes over a virtual desktop (see desktop.nix).
#
# Not in nixpkgs, so it is built here from the PyPI wheels. selkies itself
# is pure Python and carries its own web page. pixelflux (capture and video
# encoding) and pcmflux (audio) are prebuilt Rust/C wheels: autoPatchelf
# points them at Nix's libraries, and the libraries they only dlopen go on
# LD_LIBRARY_PATH in the wrapper.
#
# To update: bump the versions, set each hash to "", rebuild, and paste the
# hashes Nix prints. pixelflux and pcmflux are pinned exactly by selkies'
# own metadata, so take the versions it asks for.
{
  lib,
  pkgs,
}:
let
  python = pkgs.python313;
  py = python.pkgs;
  pyTag = "cp313";

  wheel =
    {
      pname,
      version,
      hash,
      native ? true,
      buildInputs ? [ ],
      propagatedBuildInputs ? [ ],
    }:
    py.buildPythonPackage {
      inherit pname version;
      format = "wheel";
      src = py.fetchPypi {
        inherit pname version hash;
        format = "wheel";
        dist = if native then pyTag else "py3";
        python = if native then pyTag else "py3";
        abi = if native then pyTag else "none";
        platform = if native then "manylinux_2_28_x86_64" else "any";
      };
      nativeBuildInputs = lib.optional native pkgs.autoPatchelfHook;
      inherit buildInputs propagatedBuildInputs;
      # selkies pins exact or very new versions; nixpkgs' are close enough.
      dontCheckRuntimeDeps = true;
      pythonImportsCheck = lib.optional native pname;
    };

  pixelflux = wheel {
    pname = "pixelflux";
    version = "2.2.3";
    hash = "sha256-tP9+bzjLQp3yBS0b4u0ec/JmZZ8iMVOq7pLMm69UrgM=";
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      libgbm
      pixman
      libxkbcommon
    ];
  };

  pcmflux = wheel {
    pname = "pcmflux";
    version = "2.2.1";
    hash = "sha256-ukk2BbQNOBy6Y+3hXEiWrhlmQKnmZMxcEs4kxVZ9KUY=";
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      libx11
      libxext
      libice
      libsm
      libxcb
    ];
  };

  # Libraries pixelflux and pcmflux open at run time. /run/opengl-driver
  # holds the GPU drivers (VA-API, and NVENC if Nvidia is ever set up);
  # without them it encodes on the CPU.
  runtimeLibs = with pkgs; [
    libx11
    libxcb
    libva
    libglvnd
    vulkan-loader
    pipewire
    wayland
  ];

  # Programs selkies runs: display resizing, DPI, clipboard.
  runtimePrograms = with pkgs; [
    xrandr
    xset
    xrdb
    xclip
    procps
    pulseaudio # pactl
  ];
in
py.buildPythonApplication {
  pname = "selkies";
  version = "2.2.1";
  format = "wheel";
  src = py.fetchPypi {
    pname = "selkies";
    version = "2.2.1";
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-GFA7XBSRoEGU8KRfoQxUf/5bSiTzNJbOXVbpc3Cmo80=";
  };

  dependencies =
    [
      pixelflux
      pcmflux
    ]
    ++ (with py; [
      prometheus-client
      msgpack
      psutil
      watchdog
      pillow
      pulsectl-asyncio
      dnspython
      cffi
      cryptography
      google-crc32c
      pyee
      pylibsrtp
      pyopenssl
      aiohttp
      aiofiles
      uvloop
      nvidia-ml-py
    ]);

  dontCheckRuntimeDeps = true;

  # One list element per argument: nixos-unstable passes each element to
  # makeWrapper as a single word, so "--prefix VAR : value" in one string
  # fails there.
  makeWrapperArgs = [
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib"
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath runtimePrograms)
  ];

  pythonImportsCheck = [ "selkies" ];

  meta = {
    description = "Low-latency remote desktop in the browser";
    homepage = "https://github.com/selkies-project/selkies";
    license = lib.licenses.mpl20;
    mainProgram = "selkies";
  };
}
