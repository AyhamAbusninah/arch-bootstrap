# Releasing

Releases are cut by pushing a `vX.Y.Z` tag. The [release workflow](.github/workflows/release.yml) checks the tag against the version in the files, runs the lint and installer tests, builds the assets and publishes the GitHub Release with notes from `CHANGELOG.md`.

## Versioning

The project uses [Semantic Versioning](https://semver.org/):

- **Major:** a change that breaks how people use the skill, such as renamed output files, a changed YAML schema or removed installer options.
- **Minor:** new behaviour that is backwards compatible, such as a new stack or a new installer option.
- **Patch:** fixes and wording changes.

A tag with a suffix, such as `v1.1.0-rc.1`, is published as a pre-release. Pre-releases are not picked up as "latest" by the installer.

## Steps

1. **Bump the version** in both places. They must match.
   - `skills/arch-bootstrap/SKILL.md`: the `version:` line in the frontmatter
   - `.claude-plugin/plugin.json`: `"version"`

   Don't add a `version` to the entry in `.claude-plugin/marketplace.json`. `plugin.json` takes precedence, and `scripts/version.sh` fails if the two disagree.

2. **Update `CHANGELOG.md`.** Move the items under `## [Unreleased]` into a new `## [X.Y.Z] - YYYY-MM-DD` section, and update the compare links at the bottom:

   ```markdown
   [Unreleased]: https://github.com/AyhamAbusninah/arch-bootstrap/compare/vX.Y.Z...HEAD
   [X.Y.Z]: https://github.com/AyhamAbusninah/arch-bootstrap/compare/vPREV...vX.Y.Z
   ```

   The release notes are taken from this section, so write it for users.

3. **Check locally.** You need `shellcheck`, `jq` and `python3`.

   ```bash
   scripts/lint.sh
   tests/test-install.sh
   scripts/build-release.sh          # optional: builds dist/
   scripts/release-notes.sh X.Y.Z    # preview the release notes
   claude plugin validate . --strict # if Claude Code is installed
   ```

4. **Commit, tag and push.**

   ```bash
   git commit -am "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

5. **Check the release.** Watch the Release workflow in the Actions tab. When it finishes, the release should have five assets: `arch-bootstrap-X.Y.Z.tar.gz`, `arch-bootstrap-X.Y.Z.zip`, `install.sh`, `SKILL.md` and `SHA256SUMS`. Then test the one-liner in a sandbox:

   ```bash
   sandbox="$(mktemp -d)"
   CLAUDE_SKILLS_DIR="$sandbox/skills" OPENCODE_DIR="$sandbox/opencode" \
     bash -c 'curl -fsSL https://github.com/AyhamAbusninah/arch-bootstrap/releases/latest/download/install.sh | bash'
   ```

## If the workflow fails

- **Tag does not match the version:** delete the tag (`git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z`), fix the version, commit, and tag again.
- **Lint or tests fail:** fix the problem on `main`, then move the tag to the fixed commit the same way.
- **The release already exists:** delete it on GitHub (or `gh release delete vX.Y.Z`) before re-running the workflow.

Don't change the assets of a release after it is published. The installer verifies them against `SHA256SUMS`, and people may have pinned that version. Publish a patch release instead.
