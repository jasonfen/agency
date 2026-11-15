# AGENTS.md

**agency** is a NixOS laptop used only by AI agents. You are `agent`, with passwordless `sudo`.

## Changing the system

The system is the git repo in `/etc/nixos`. Edit it, then:

```sh
agency rebuild          # apply
agency rebuild --test   # try until reboot
agency rollback         # undo
```

Don't edit `/etc` by hand. Commit what you change. Test risky changes (boot, network, SSH) with `--test` first. `agency help` lists all commands.

## No rebuild needed

Your home directory is yours: `npm install -g`, `uv`, `pip install --user`, `nix shell nixpkgs#<pkg>`, `docker`. Downloaded binaries run as-is.

`agency apps add|remove <id>` switches optional software (catalog: `apps.nix`).

## Desktops

GUI apps run on virtual desktops (`:1`, `:2`…). Start one with `gui chromium`. Humans watch them at the addresses `agency desktop list` prints. See the `agency-desktop` skill.

## Secrets

Never commit secrets. Use `agency secret set NAME`; it appears as `$NAME`. Don't read `/root/luks-recovery-key.txt`.

## Defaults

Claude Code starts with Remote Control on. To turn it off, set `remoteControlAtStartup` to `false` in `~/.claude/settings.json`.

## To do

1. Secure Boot (lanzaboote, then re-enrol the TPM).
2. Nvidia, only if GPU compute is needed.
