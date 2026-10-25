# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-25

### Added

- The `arch-bootstrap` skill for Claude Code and OpenCode: a 4-stage interactive state machine that generates or verifies `docs/architecture/ai_architecture_map.yaml`, the interactive `MAP.html`, `docs/architecture/CHANGELOG.md`, `docs/AI_WORKFLOW.md`, `CLAUDE.md` and `AGENTS.md` for any tech stack.
- A Claude Code plugin marketplace, so the skill installs with `/plugin marketplace add AyhamAbusninah/arch-bootstrap` and `/plugin install arch-bootstrap@arch-bootstrap`.
- `install.sh`, which installs the latest GitHub Release by default and verifies it against `SHA256SUMS`. It supports pinning with `ARCH_BOOTSTRAP_VERSION`, installing from a branch with `ARCH_BOOTSTRAP_REF`, `--link`, `--copy-opencode`, `--uninstall` and `--version`.
- Versioned GitHub Releases with tarball, zip, `install.sh`, `SKILL.md` and `SHA256SUMS` assets, built by a tag-triggered workflow.

[Unreleased]: https://github.com/AyhamAbusninah/arch-bootstrap/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/AyhamAbusninah/arch-bootstrap/releases/tag/v1.0.0
