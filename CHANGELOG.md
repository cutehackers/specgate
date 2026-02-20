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
- Added uninstall mode:
  - `--uninstall` now removes installed SpecGate assets.
  - When `--ai/--agent` is provided with uninstall, only requested agent surfaces are removed; using default scope removes full shared + selected assets.
- Added update mode:
  - `--update` now performs in-place updates of changed files.
  - Backup files (`*.backup-*`) are not generated for install/clean/uninstall/update workflows.
- `statusline.js` management now preserves user-owned statusline hooks and updates/removes only files created by SpecGate.
- Added changelog and deployment-oriented README.
