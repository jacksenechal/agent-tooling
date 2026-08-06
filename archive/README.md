# Archive

Skills that are no longer active but kept for reference.

## pi-swarm

Retired 2026-08-06: Jack stopped using the pi agentic tooling.

It depends on external artifacts that are also retired, so it will not
work as-is if restored:

- the `agent-sandbox:latest` Docker image
- the `pi` binary
- `~/.config/keys/opencode.key`

Restoring it requires re-provisioning the `pi` ansible role, which is
archived in the dotfiles repo at `archive/roles/pi`.
