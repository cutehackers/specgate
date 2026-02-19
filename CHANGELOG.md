# Changelog

## Unreleased

- Initial extraction of SpecGate core engine from `plan_pal`.
- Added bootstrap/install scripts for independent repository usage:
  - `install.sh`
- `sync.sh` was removed to keep the install flow single-file and install-only.
- `install.sh` now supports remote one-shot installation via:
  - `curl -fsSL .../install.sh | bash -s -- --prefix .`
  - `--version` option for branch/tag selection.
- Added changelog and deployment-oriented README.
