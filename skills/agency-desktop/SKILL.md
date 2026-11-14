---
name: agency-desktop
description: Facts about the virtual desktops on this agency machine, for GUI apps, browsers and computer use.
---

# Desktops

GUI apps run on virtual X11 desktops (Openbox, 1280x800) that exist only in
memory. `:1` always runs; `agency desktop` lists the others and
`agency desktop add` makes one. Other agents may be using a desktop, so
check before you take one over.

- `gui [-d N] <app>` starts an app detached, on `$DISPLAY` or `:1`.
- Installed: xdotool, wmctrl, scrot, xclip, ImageMagick. Anything else is
  one `nix shell nixpkgs#...` away.
- Chromium keeps its profile in `~/.config/chromium`, so logins persist.

A person can watch or take over desktop `:N` at
`http://<hostname>:<6080+N>/vnc.html` over Tailscale. That is the way to
get them to handle a login, 2FA or a CAPTCHA.
