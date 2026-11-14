---
name: agency-secrets
description: Read or store API keys, tokens and passwords on the agency machine. Read this when a task needs a credential, or when you are about to write one to a file.
---

# Secrets

Secrets are stored encrypted in `/etc/nixos/secrets/agency.sops.json`. At boot
each one is decrypted to `/run/secrets/NAME`, and new shells have it as `$NAME`.

```sh
agency secret                         # list names
echo "$OPENAI_API_KEY"                # use one (new shells only)
cat /run/secrets/OPENAI_API_KEY       # or read the file
agency secret set OPENAI_API_KEY      # store one: asks for the value, or reads stdin
agency secret remove OPENAI_API_KEY
```

`set` and `remove` commit the encrypted file and rebuild. Add `--no-rebuild`
to store several, then run `agency rebuild` once.

Rules:

- Never put a secret in a plain file in a repo, in a commit message, in a
  command line argument, or in your reply. Pipe it: `printf %s "$VALUE" | agency secret set NAME`.
- If the person gives you a key in chat, store it with `agency secret set` and
  then refer to it by name only.
- A secret you need but do not have: ask the person to run
  `agency secret set NAME` over SSH. Do not ask them to paste it to you.
- The disk recovery key is not a secret for agents. Do not read
  `/root/luks-recovery-key.txt`; a person runs `agency recovery-key`.
