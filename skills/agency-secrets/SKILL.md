---
name: agency-secrets
description: Where API keys and tokens live on the agency machine, and how to store new ones. Use when a task needs a credential.
---

# Secrets

Secrets are stored encrypted in the repo (`/etc/nixos/secrets/`) with
sops-nix. Each one is available as `/run/secrets/NAME` and as `$NAME` in new
shells. `agency secret` lists them; `agency secret set NAME` stores one,
reading the value from stdin, and rebuilds.

Keep secret values out of plain files, commits, command arguments and your
replies. If a person has a key for you, they can run `agency secret set`
themselves over SSH.

The disk recovery key is not for agents. A person reads it with
`agency recovery-key`.
