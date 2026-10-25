#!/usr/bin/env bash
# Print the CHANGELOG.md section for a version (without its heading).
#   scripts/release-notes.sh 1.2.3
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
v="${1:?usage: release-notes.sh <version>}"
v="${v#v}"

notes="$(awk -v v="$v" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  /^\[[^]]+\]: / { next }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

[ -n "$notes" ] || { echo "release-notes: no CHANGELOG.md section for $v" >&2; exit 1; }
printf '%s\n' "$notes"
