---
name: agency-desktop
description: Use the virtual desktops on this agency machine for computer use. Read this before you open a GUI app or a browser, take a screenshot, click or type into a window, or need a person to log in to a site.
---

# Desktops and computer use

GUI apps run on virtual X11 desktops that exist only in memory. Desktop `:1`
always runs. There can be more (`:2`, `:3`, ...); `agency desktop` lists them.

## Pick a desktop

Two agents on one desktop take the mouse from each other. Before you start:

1. `agency desktop` lists the desktops.
2. Look at what is open on one: `DISPLAY=:1 wmctrl -l`.
3. If another agent is using it, run `agency desktop add` and use the new one.
   This needs a short rebuild.

Then set `export DISPLAY=:N` for the rest of your work.

## Do things

```sh
gui chromium                          # start an app on $DISPLAY (or :1), detached
gui -d 2 xterm                        # start an app on :2
scrot /tmp/screen.png                 # screenshot of the whole desktop
scrot -u /tmp/window.png              # only the active window
xdotool mousemove 640 400 click 1     # click at x=640, y=400
xdotool type --delay 50 'hello'       # type text
xdotool key ctrl+l Return             # press keys
xdotool search --name 'Chromium' windowactivate --sync
wmctrl -l                             # list windows
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
xclip -selection clipboard -o         # read the clipboard
convert /tmp/screen.png -crop 400x300+0+0 /tmp/part.png   # crop
```

Each desktop is 1280x800 (`desktopGeometry` in `/etc/nixos/settings.nix`).
Coordinates in screenshots are the same as for xdotool.

Work in a loop: screenshot, look, act, screenshot again. After a click or a
page load, wait a moment (`sleep 1`) before the next screenshot.

## Browsers

Prefer driving a browser through code when you can. Start Chromium with
remote debugging, then attach Playwright or Puppeteer to it:

```sh
gui chromium --remote-debugging-port=9222 --user-data-dir=$HOME/.config/chromium
# Playwright: chromium.connect_over_cdp("http://localhost:9222")
```

The profile in `~/.config/chromium` keeps logins between runs. Do not use a
fresh temporary profile when the task needs an account.

## When a person is needed

For a login, a 2FA code or a CAPTCHA, open the page, then ask the person to
finish it on the desktop in their browser:

    http://<this machine's name>:6081/vnc.html    (desktop :N is port 6080+N)

It works over Tailscale only. Get the machine's name with `hostname`. Wait
for them to say they are done; the login then stays in the profile.

Never type a password, a card number or a 2FA code yourself unless the
person gave it to you for that purpose.
