<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/agency-dark.svg">
    <img src="docs/agency.svg" alt="agency" height="96">
  </picture>
</p>

<p align="center">
  Turns a spare laptop into a computer for your agents.
</p>

Agents are bad at sharing a computer. They want the mouse, the screen and the browser at the same moment you do, and on your own machine you can't really let them run with full permissions. So give them a different one. Flash this onto a USB stick, boot a spare laptop from it, and a few minutes later it's a NixOS box where the agents have root and a desktop of their own. You SSH in when they need you, or open their desktop in a browser tab to type a password.

If an agent breaks the system, reboot and pick yesterday's version from the boot menu.

<p align="center">
  <img src="docs/setup-welcome.png" alt="The first screen of the agency installer" width="720">
</p>

## Install

1. Make sure your GitHub account has an SSH key on it, because that's how you'll log in.
2. Write the installer to a USB stick. On a Mac or Linux, plug the stick in and run:

   ```sh
   curl -fsSL https://agency.makors.xyz/flash | sh
   ```

   On Windows, download the ISO from [agency.makors.xyz](https://agency.makors.xyz) and write it with balenaEtcher, or Rufus in DD mode.
3. In the BIOS, turn Secure Boot off and TPM on.
4. Boot the stick. A setup screen walks you through the network, a name for the machine, your GitHub username, which disk to erase, Tailscale, and which apps you want. Tailscale sign-in is a QR code you scan with your phone.

It installs, restarts, and you're in, using the name you gave it:

```sh
ssh agent@agency
```

[docs/install.md](docs/install.md) has the details, including how to make a stick that asks nothing.

## Use

Start one of the agents you picked. [AGENTS.md](AGENTS.md) tells it how the machine works and what's left to set up.

```sh
agency                          # what the machine is doing
agency update                   # pull the newest agency and rebuild
agency secret set OPENAI_API_KEY   # an encrypted key the agents can read
agency recovery-key             # see the disk recovery key once, then delete it
gui chromium                    # open an app on the agents' desktop
```

Agents find out how the machine works on their own: Claude Code, Codex and OpenCode get a short note and skills for the desktop, system changes and secrets.

Their desktop lives at `http://agency:6081/vnc.html` once you're on Tailscale (swap in your machine's name).

## Does it work

Don't know yet. CI builds the installer, but nobody has booted it on a real machine, so expect the first install to trip on something. It should run on any x86-64 laptop or PC that has UEFI and a TPM 2.0 chip.
