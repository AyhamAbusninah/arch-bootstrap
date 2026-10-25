#!/usr/bin/env bash
# Build the release assets into dist/ (or $1):
#   arch-bootstrap-<version>.tar.gz and .zip (skills/, install.sh, README.md, LICENSE),
#   install.sh, SKILL.md and SHA256SUMS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
root="$PWD"
out="${1:-dist}"
case "$out" in /*) ;; *) out="$root/$out" ;; esac

version="$(scripts/version.sh)"
pkg="arch-bootstrap-$version"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

rm -rf "$out"
mkdir -p "$out" "$stage/$pkg"
cp -R skills install.sh README.md LICENSE "$stage/$pkg/"
chmod 755 "$stage/$pkg/install.sh"

# Fixed timestamps and ownership so the same commit gives the same archives.
epoch="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}"
find "$stage/$pkg" -exec touch -h -d "@$epoch" {} +

(cd "$stage" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$epoch" \
  -cf - "$pkg" | gzip -n > "$out/$pkg.tar.gz")
(cd "$stage" && find "$pkg" | LC_ALL=C sort | TZ=UTC zip -qX "$out/$pkg.zip" -@)

cp install.sh "$out/install.sh"
cp skills/arch-bootstrap/SKILL.md "$out/SKILL.md"
(cd "$out" && sha256sum "$pkg.tar.gz" "$pkg.zip" install.sh SKILL.md > SHA256SUMS)

echo "Built $version in $out:"
(cd "$out" && ls -l && cat SHA256SUMS)
