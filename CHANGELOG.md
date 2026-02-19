# Changelog

## Unreleased

- Initial extraction of SpecGate core engine from `plan_pal`.
- Added bootstrap/install scripts for independent repository usage:
  - `install.sh`
- `sync.sh` was removed to keep the install flow single-file and install-only.
- `install.sh` now supports remote one-shot installation via:
  - `curl -fsSL .../install.sh | bash -s -- --prefix .`
  - `--version` option for branch/tag selection.
- Added agent-targeted install controls:
  - `--ai/--agent` to install only selected agent command surfaces (`claude`, `codex`, `opencode`).
  - Default remains `all`.
- Added changelog and deployment-oriented README.
