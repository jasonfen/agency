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
- A panel (tint2) takes the bottom 30 pixels, with launchers, the open
  windows and a clock; maximized windows stop above it. It is there for
  people who look in, so leave it alone. Use `wmctrl` to find windows
  rather than clicking the panel.
- Installed: xdotool, wmctrl, scrot, xclip, ImageMagick. Anything else is
  one `nix shell nixpkgs#...` away.
- Chromium keeps its profile in `~/.config/chromium`, so logins persist.

A person can watch or take over desktop `:N` at
`https://<tailnet name>:<6080+N>/` (Selkies; `agency desktop list` prints the
addresses). That is the way to
get them to handle a login, 2FA or a CAPTCHA.
