<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <img src="docs/logo.svg" alt="agency" height="96">
  </picture>
</p>

<p align="center">
  <b>A computer for agents.</b><br>
  NixOS on a laptop nobody sits at. Agents get root, you get a link.
</p>

Your computer is built around you sitting at it. This one isn't. Agents run the whole thing, it lives lid-closed in a corner, and you drop in over the network when they need a login or you want to watch. The entire machine is this repo, so when an agent breaks it you roll back, and when you want another one you flash a stick.

| Part | Does |
|---|---|
| **`agent`** | the one account, with passwordless sudo |
| **Display `:1`** | a desktop that only exists in memory, for GUI apps and computer use |
| **noVNC** | that desktop in a browser tab, so you can watch or take over |
| **Tailscale** | the only way in from outside your network |
| **Generations** | every system change is a boot entry you can go back to |
| **The stick** | a USB installer that wipes the laptop and builds all of the above |

## Install

You need the laptop, a USB stick (8 GB+) and a network cable.

1. Put an SSH key on your GitHub account. The installer copies your public keys from there, and there is no password login.
2. Grab the ISO from **Actions → Build installer ISO** (the `agency-installer` artifact) and flash it with balenaEtcher.
3. In the BIOS: Secure Boot off, UEFI on, TPM on.
4. Boot the stick and walk away. It counts down 30 seconds, erases the internal disk, installs, and reboots. Hold the power button during the countdown if you change your mind.

```sh
ssh agent@agency.local
sudo tailscale up --ssh    # open the link it prints
```

Want it fully hands-off? Format a second stick as FAT, label it `AGENCY`, and drop a one-time Tailscale key on it in a file called `tailscale-authkey`. Plug in both and the machine joins your tailnet by itself.

The installer won't touch the disk if the machine isn't the brand it expects, if agency is already installed (so a forgotten stick can't reinstall in a loop), if there's no TPM, or if it can't find an SSH key. `sudo agency-install --force` on Alt+F2 overrides the first two.

## Use

Install an agent CLI, point it at [`AGENTS.md`](AGENTS.md), and let it finish the setup. That file is the manual for agents: how the machine works, how to change it, and what's left to do.

```sh
gui chromium                               # open an app on the virtual desktop
DISPLAY=:1 scrot /tmp/screen.png           # look at it
DISPLAY=:1 xdotool mousemove 640 400 click 1

cd /etc/nixos && sudo nixos-rebuild switch --flake .   # change the system
```

You watch at `http://agency:6081/vnc.html`. When a site wants a password or 2FA, do it there once; the browser stays signed in for the agents.

Downloaded binaries, AppImages and `npm install -g` all work like on any other Linux. Docker and distrobox are there for anything that still complains.

## Is it any good

Not proven yet. The config evaluates, the install script passes lint and CI builds the ISO, but it has never booted on a real laptop. The disk unlock and the virtual desktop are the two parts most likely to need a fix on the first run.

It's not perfect either. Secure Boot is off, so the encryption protects a stolen disk but not a stolen laptop that someone boots from their own stick. There's one desktop, not one per agent. And the Nvidia card just sits there. All of that is on the list in `AGENTS.md`.

One more thing: agents hold whatever you sign them in to. Make credentials for this machine (a fresh SSH key, scoped tokens) so you can revoke them without touching anything else. And never commit secrets here.

## Make it yours

It's set up for an MSI GF63 Thin 11UC. For anything else, change the host name, disk, `vendorMatch` and `githubUser` in [`settings.nix`](settings.nix), swap [`hosts/agency/hardware.nix`](hosts/agency/hardware.nix) (the file says how), and push. CI builds you a new ISO.

## Credits

Built on NixOS, disko, Tailscale, TigerVNC, noVNC and Openbox. The idea of giving agents their own Linux box comes from people like Theo, who have been doing it by hand.
