#!/usr/bin/env bash
# Lint checks shared by CI and the release workflow. Needs bash, shellcheck and jq.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SKILL="skills/arch-bootstrap/SKILL.md"
status=0
ok() { echo "✓ $*"; }
bad() { echo "✗ $*" >&2; status=1; }

mapfile -t shells < <(git ls-files '*.sh' 2>/dev/null || true)
[ "${#shells[@]}" -gt 0 ] || mapfile -t shells < <(find . -name '*.sh' -not -path './.git/*' | sort)

for f in "${shells[@]}"; do
  if bash -n "$f"; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "${shells[@]}"; then ok "shellcheck (${#shells[@]} files)"; else bad "shellcheck"; fi
else
  bad "shellcheck is not installed"
fi

frontmatter="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$SKILL")"
for key in name description version; do
  if echo "$frontmatter" | grep -Eq "^$key:[[:space:]]*[^[:space:]]"; then
    ok "$SKILL frontmatter has $key"
  else
    bad "$SKILL frontmatter is missing $key"
  fi
done

while IFS= read -r f; do
  if jq empty "$f" >/dev/null; then ok "valid JSON $f"; else bad "invalid JSON $f"; fi
done < <(find . -name '*.json' -not -path './.git/*' -not -path './dist/*' | sort)

if v="$(scripts/version.sh)"; then ok "versions in sync ($v)"; else bad "versions out of sync"; fi

if grep -Eq "^## \[$(scripts/version.sh 2>/dev/null || echo x)\]" CHANGELOG.md; then
  ok "CHANGELOG.md has a section for the current version"
else
  bad "CHANGELOG.md has no '## [<version>]' section for the current version"
fi

exit "$status"
