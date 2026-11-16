# Contributing

Issues and pull requests are welcome.

- **Try a change** in the VM: `nix run .#vm` (see [docs/existing-nixos.md](docs/existing-nixos.md)), or on an agency machine with `agency rebuild --test`.
- **Commits** say what changed for the person using it, after the part it touches: `Installer: …`, `Dashboard: …`, `Site: …`.
- **Checks** run on every pull request: shellcheck on the installer, and an evaluation of the system and the ISO.
- **A new app** in `apps.nix` needs its logo in `dashboard/ui/logos/` (see [AGENTS.md](AGENTS.md)).
- **Never commit secrets.** Public SSH keys are fine.

By contributing you agree to license your work under the [MIT license](LICENSE).
