#!/usr/bin/env bash
# Print the project version, after checking that SKILL.md and the plugin manifests agree.
#
#   scripts/version.sh            print the version (fails if the sources disagree)
#   scripts/version.sh v1.2.3     also fail unless the tag matches that version
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SKILL="skills/arch-bootstrap/SKILL.md"
PLUGIN=".claude-plugin/plugin.json"
MARKET=".claude-plugin/marketplace.json"

fail() { echo "version: $*" >&2; exit 1; }

skill_v="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit}
  NR>1 && /^version:/ {sub(/^version:[[:space:]]*/, ""); gsub(/["'\'']/, ""); print; exit}' "$SKILL")"
[ -n "$skill_v" ] || fail "$SKILL frontmatter has no version"
echo "$skill_v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' \
  || fail "$SKILL version '$skill_v' is not semver"

plugin_v="$(jq -r '.version // empty' "$PLUGIN")"
[ "$plugin_v" = "$skill_v" ] || fail "$PLUGIN version '$plugin_v' != $SKILL version '$skill_v'"

# A marketplace entry version is optional (plugin.json wins), but must agree if present.
while IFS= read -r v; do
  [ "$v" = "$skill_v" ] || fail "$MARKET entry version '$v' != $SKILL version '$skill_v'"
done < <(jq -r '.plugins[] | select(.name=="arch-bootstrap") | .version // empty' "$MARKET")

if [ $# -gt 0 ]; then
  [ "$1" = "v$skill_v" ] || fail "tag '$1' does not match version v$skill_v"
fi

echo "$skill_v"
