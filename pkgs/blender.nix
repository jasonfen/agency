# `blender`: runs the newest stable release from blender.org.
#
# nixpkgs' Blender links LLVM 19 through OSL while Mesa's llvmpipe uses its
# own LLVM, and the two clash as soon as Blender opens a window. Fixing
# that means compiling OSL, OpenUSD and Blender locally (an hour, again on
# every bump). The official build bundles its libraries, so this launcher
# downloads it instead: the first run takes about a minute, and each run
# after that checks (at most every 12 hours) for a newer stable release.
# No rebuild or commit is needed when Blender ships one.
#
# Releases live in ~/.cache/agency-blender (not backed up; downloaded again
# if removed). BLENDER_NO_UPDATE=1 skips the check. The binary runs through
# nix-ld, with the X and GL libraries below added.
{
  lib,
  writeShellApplication,
  coreutils,
  curl,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  xz,
  util-linux,
  libx11,
  libxi,
  libxrender,
  libxfixes,
  libxext,
  libxrandr,
  libxcursor,
  libxinerama,
  libxxf86vm,
  libsm,
  libice,
  libxkbcommon,
  libGL,
  libdecor,
  wayland,
  vulkan-loader,
}:
let
  libs = lib.makeLibraryPath [
    libx11 libxi libxrender libxfixes libxext libxrandr libxcursor
    libxinerama libxxf86vm libsm libice libxkbcommon libGL libdecor
    wayland vulkan-loader
  ];
in
writeShellApplication {
  name = "blender";
  runtimeInputs = [ coreutils curl findutils gnugrep gnused gnutar xz util-linux ];
  text = ''
    base=https://download.blender.org/release
    dir="''${XDG_CACHE_HOME:-$HOME/.cache}/agency-blender"
    mkdir -p "$dir"
    [ -e "$dir/CACHEDIR.TAG" ] || echo "Signature: 8a477f597d28d172789f06886806bc55" > "$dir/CACHEDIR.TAG"

    say() { echo "blender: $*" >&2; }

    installed() { # newest release already unpacked
      find "$dir" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' -printf '%f\n' | sort -V | tail -1
    }

    latest() { # newest stable version on blender.org
      local series v
      for series in $(curl -fsS --max-time 20 "$base/" | grep -oE 'Blender[0-9]+\.[0-9]+/' | sort -uV -r | head -3); do
        v=$(curl -fsS --max-time 20 "$base/$series" | grep -oE 'blender-[0-9]+\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz' \
          | sed -E 's/^blender-(.*)-linux-x64\.tar\.xz$/\1/' | sort -uV | tail -1)
        if [ -n "$v" ]; then echo "$v"; return 0; fi
      done
      return 1
    }

    fetch() ( # download, verify and unpack version $1
      v=$1
      series="Blender''${v%.*}"
      file="blender-$v-linux-x64.tar.xz"
      tmp=$(mktemp -d "$dir/.tmp.XXXXXX")
      trap 'rm -rf "$tmp"' EXIT
      say "downloading Blender $v"
      curl -fL --progress-bar -o "$tmp/$file" "$base/$series/$file"
      sum=$(curl -fsS "$base/$series/blender-$v.sha256" | grep " $file\$" | cut -d' ' -f1)
      if [ -z "$sum" ] || ! echo "$sum  $tmp/$file" | sha256sum -c --status; then
        say "checksum mismatch for $file"; return 1
      fi
      tar -xJf "$tmp/$file" -C "$tmp" &&
        mv "$tmp/blender-$v-linux-x64" "$dir/$v" &&
        # Keep only the newest release.
        find "$dir" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' ! -name "$v" -exec rm -rf {} +
    )

    (
      flock 9
      have=$(installed)
      stamp="$dir/.checked"
      if [ "''${BLENDER_NO_UPDATE:-}" != 1 ] && { [ -z "$have" ] || [ -z "$(find "$stamp" -mmin -720 2>/dev/null)" ]; }; then
        if want=$(latest); then
          touch "$stamp"
          if [ "$want" != "$have" ]; then fetch "$want" || say "keeping ''${have:-nothing}"; fi
        else
          say "could not reach blender.org''${have:+, using $have}"
        fi
      fi
    ) 9>"$dir/.lock"

    v=$(installed)
    if [ -z "$v" ]; then say "no Blender installed and the download failed"; exit 1; fi
    export NIX_LD_LIBRARY_PATH="${libs}''${NIX_LD_LIBRARY_PATH:+:$NIX_LD_LIBRARY_PATH}"
    # Newer releases try Vulkan first, which fails on the desktops'
    # software renderer (lavapipe); OpenGL on llvmpipe works.
    case " $* " in
      *" --gpu-backend "*) exec "$dir/$v/blender" "$@" ;;
      *) exec "$dir/$v/blender" --gpu-backend opengl "$@" ;;
    esac
  '';
}
