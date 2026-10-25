# arch-bootstrap

[![Latest release](https://img.shields.io/github/v/release/AyhamAbusninah/arch-bootstrap?sort=semver)](https://github.com/AyhamAbusninah/arch-bootstrap/releases/latest)
[![CI](https://github.com/AyhamAbusninah/arch-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/AyhamAbusninah/arch-bootstrap/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/AyhamAbusninah/arch-bootstrap)](LICENSE)

A skill for Claude Code and OpenCode that makes any repository AI-ready. Run `/arch-bootstrap` in a Frappe, Next.js, Python, Go, Rust, C/C++ or JVM project. The skill scans it without reading every file and generates:

| File | Purpose |
|---|---|
| `docs/architecture/ai_architecture_map.yaml` | An index for AI agents: entry points, hidden hooks, invariants (fail-closed paths, locks, idempotency, permissions), blast radius and known gaps, with `path:line` references |
| `docs/architecture/MAP.html` | A full-screen interactive Mermaid diagram with scroll-to-zoom, drag-to-pan and zoom buttons |
| `docs/architecture/CHANGELOG.md` | An append-only log of AI changes, 3 lines per entry |
| `docs/AI_WORKFLOW.md` | A guide for the developers on the repo |
| `CLAUDE.md` + `AGENTS.md` | Agent rules, in either Direct Mode or Triage Router mode (`@feature`, `@bug`, `@qa`, `@audit`) |

## Install

### 1. Claude Code plugin marketplace (recommended for Claude Code)

In a Claude Code session:

```
/plugin marketplace add AyhamAbusninah/arch-bootstrap
/plugin install arch-bootstrap@arch-bootstrap
```

On Claude Code 2.1.275 or later you can do both in one step: `/plugin install arch-bootstrap --marketplace AyhamAbusninah/arch-bootstrap`.

Plugin skills are namespaced, so the skill is available as `/arch-bootstrap:arch-bootstrap`. Claude also picks it up when you ask it to make a repo AI-ready.

### 2. One-line installer (Claude Code and OpenCode)

```bash
curl -fsSL https://github.com/AyhamAbusninah/arch-bootstrap/releases/latest/download/install.sh | bash
```

This installs the latest release into `~/.claude/skills/arch-bootstrap/`, where it runs as `/arch-bootstrap`. If OpenCode is installed, the skill is also linked into `~/.config/opencode/skills/`. The installer checks the download against the release's `SHA256SUMS` and stops, leaving any existing install untouched, if they don't match. It needs only `bash`, `curl`, and `tar` or `unzip`.

### 3. A pinned version

```bash
curl -fsSL https://github.com/AyhamAbusninah/arch-bootstrap/releases/download/v1.0.0/install.sh | ARCH_BOOTSTRAP_VERSION=v1.0.0 bash
```

To track the `main` branch instead of releases (not checksum-verified):

```bash
curl -fsSL https://raw.githubusercontent.com/AyhamAbusninah/arch-bootstrap/main/install.sh | ARCH_BOOTSTRAP_REF=main bash
```

### 4. Manual download

Download `arch-bootstrap-<version>.tar.gz` (or `.zip`) and `SHA256SUMS` from the [Releases page](https://github.com/AyhamAbusninah/arch-bootstrap/releases), then:

```bash
sha256sum -c --ignore-missing SHA256SUMS     # macOS: shasum -a 256 -c --ignore-missing SHA256SUMS
tar -xzf arch-bootstrap-1.0.0.tar.gz
cd arch-bootstrap-1.0.0 && ./install.sh
```

Or copy `skills/arch-bootstrap/` into `~/.claude/skills/` (or `~/.config/opencode/skills/`) yourself. Each release also has `SKILL.md` as a single file.

### 5. From a clone

```bash
git clone https://github.com/AyhamAbusninah/arch-bootstrap.git
cd arch-bootstrap
./install.sh            # copy into ~/.claude/skills
./install.sh --link     # symlink instead, so edits to the clone take effect immediately
```

### Installer options

| Option | Use |
|---|---|
| `--link` | Symlink the Claude skill to the clone (clone only) |
| `--copy-opencode` | Copy into OpenCode instead of symlinking to the Claude skill |
| `--uninstall` | Remove the skill from Claude Code and OpenCode |
| `--version` | Print the installed version |

| Variable | Default | Use |
|---|---|---|
| `ARCH_BOOTSTRAP_VERSION` | latest release | Install a specific release, for example `v1.0.0` |
| `ARCH_BOOTSTRAP_REF` | unset | Install from a git branch or ref, for example `main`. `ARCH_BOOTSTRAP_VERSION` wins if both are set |
| `CLAUDE_SKILLS_DIR` | `~/.claude/skills` | Change where the Claude skill is installed |
| `OPENCODE_DIR` | `~/.config/opencode` | Change where OpenCode is looked for |

Pass options to the one-liner with `bash -s --`, for example `curl -fsSL .../install.sh | bash -s -- --version`.

## Update

- **Plugin:** run `/plugin marketplace update arch-bootstrap`, then reinstall or update the plugin from `/plugin`.
- **Installer:** run the one-liner again. The previous install is backed up to `~/.claude/skills/arch-bootstrap.bak.<timestamp>` before it is replaced.
- **Clone with `--link`:** `git pull`.

Check the installed version with `./install.sh --version`, or `/plugin` for the plugin.

## Uninstall

- **Plugin:** `/plugin uninstall arch-bootstrap@arch-bootstrap`, and optionally `/plugin marketplace remove arch-bootstrap`.
- **Installer:** `curl -fsSL https://github.com/AyhamAbusninah/arch-bootstrap/releases/latest/download/install.sh | bash -s -- --uninstall`, or `./install.sh --uninstall` from a clone.

## How it works

The skill is a single file, [`skills/arch-bootstrap/SKILL.md`](skills/arch-bootstrap/SKILL.md). It runs four stages in order:

1. **Map check.** If the map files already exist, the skill asks whether to skip scanning (to save tokens) or run a delta scan from the commit the map records. If they don't exist, it detects the stack, scans the code and generates them.
2. **Docs.** It creates or updates `CHANGELOG.md` and `AI_WORKFLOW.md`. It never overwrites existing changelog history.
3. **Mode choice.** It asks whether to use the Triage Router or Direct Mode, and waits for your answer.
4. **Agent rules.** It writes `CLAUDE.md` and `AGENTS.md`. If either file already exists, your own content is kept: the generated rules go between `<!-- arch-bootstrap:start/end -->` markers, and a re-run replaces that block.

The repository is both the plugin and its marketplace: `.claude-plugin/marketplace.json` lists one plugin whose source is the repo root, and `.claude-plugin/plugin.json` holds its version. Claude Code finds the skill in `skills/` automatically.

## Contributing

`scripts/lint.sh` runs the checks CI runs, and `tests/test-install.sh` tests the installer in a temporary sandbox. See [RELEASING.md](RELEASING.md) for how releases are cut, and [CHANGELOG.md](CHANGELOG.md) for what changed.

## License

[MIT](LICENSE)
