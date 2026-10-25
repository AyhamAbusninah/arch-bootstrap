#!/usr/bin/env bash
# arch-bootstrap installer
#
#   One-liner:   curl -fsSL https://github.com/AyhamAbusninah/arch-bootstrap/releases/latest/download/install.sh | bash
#   From clone:  ./install.sh [--link] [--copy-opencode] [--uninstall] [--version]
#
#   --link            symlink the Claude skill to this clone (edits apply instantly; clone only)
#   --copy-opencode   copy into OpenCode instead of symlinking to the Claude skill
#   --uninstall       remove the skill from Claude Code and OpenCode
#   --version         print the installed version and exit
#
# Without a clone, the latest GitHub Release is installed and checked against its SHA256SUMS.
#
# Env: CLAUDE_SKILLS_DIR (~/.claude/skills), OPENCODE_DIR (~/.config/opencode),
#      ARCH_BOOTSTRAP_VERSION (release tag to pin, e.g. v1.0.0; default: latest release),
#      ARCH_BOOTSTRAP_REF (git ref such as main; installs from source instead of a release),
#      ARCH_BOOTSTRAP_RELEASES (releases base URL override), ARCH_BOOTSTRAP_RAW (raw base URL override)
set -euo pipefail

NAME="arch-bootstrap"
REPO="AyhamAbusninah/arch-bootstrap"
VERSION="${ARCH_BOOTSTRAP_VERSION:-}"
REF="${ARCH_BOOTSTRAP_REF:-}"
RELEASES="${ARCH_BOOTSTRAP_RELEASES:-https://github.com/$REPO/releases}"
RAW="${ARCH_BOOTSTRAP_RAW:-https://raw.githubusercontent.com/$REPO/${REF:-main}}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
OPENCODE_DIR="${OPENCODE_DIR:-$HOME/.config/opencode}"
DEST="$CLAUDE_SKILLS_DIR/$NAME"
OC="$OPENCODE_DIR/skills/$NAME"

usage() {
  cat <<'EOF'
arch-bootstrap installer

Usage: install.sh [--link] [--copy-opencode] [--uninstall] [--version]

  --link            symlink the Claude skill to this clone (edits apply instantly; clone only)
  --copy-opencode   copy into OpenCode instead of symlinking to the Claude skill
  --uninstall       remove the skill from Claude Code and OpenCode
  --version         print the installed version and exit

Env:
  ARCH_BOOTSTRAP_VERSION   release tag to install, e.g. v1.0.0 (default: latest release)
  ARCH_BOOTSTRAP_REF       git ref to install from source, e.g. main (bleeding edge)
  CLAUDE_SKILLS_DIR        default ~/.claude/skills
  OPENCODE_DIR             default ~/.config/opencode
EOF
}

LINK=0
OC_COPY=0
UNINSTALL=0
SHOW_VERSION=0
for arg in "$@"; do
  case "$arg" in
    --link) LINK=1 ;;
    --copy-opencode) OC_COPY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --version) SHOW_VERSION=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

have_opencode() { [ -d "$OPENCODE_DIR" ] || command -v opencode >/dev/null 2>&1; }

# Print the `version:` field from a SKILL.md frontmatter block.
skill_version() {
  awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit}
       NR>1 && /^version:/ {sub(/^version:[[:space:]]*/, ""); gsub(/["'\'']/, ""); print; exit}' "$1"
}

if [ "$SHOW_VERSION" -eq 1 ]; then
  if [ -f "$DEST/SKILL.md" ]; then
    v="$(skill_version "$DEST/SKILL.md")"
    echo "$NAME ${v:-unknown} ($DEST)"
    exit 0
  fi
  echo "$NAME is not installed in $DEST" >&2
  exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
  for p in "$DEST" "$OC"; do
    if [ -e "$p" ] || [ -L "$p" ]; then rm -rf "$p"; echo "✓ removed $p"; fi
  done
  exit 0
fi

# Locate a local clone (unset when piped from curl).
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$here/skills/$NAME/SKILL.md" ] && SRC_DIR="$here/skills/$NAME"
fi

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Resolve "latest" through the releases/latest redirect, so no API token is needed.
resolve_latest() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$RELEASES/latest")" || return 1
  case "$url" in */tag/v*) echo "${url##*/}" ;; *) return 1 ;; esac
}

# Stage the new skill first so a failed download never removes a working install.
tmp=""
STAGED=""
FROM=""
if [ -z "$SRC_DIR" ]; then
  [ "$LINK" -eq 1 ] && echo "• --link needs a local clone; downloading instead" >&2
  LINK=0
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  if [ -n "$REF" ] && [ -z "$VERSION" ]; then
    # Bleeding edge: a single SKILL.md from a git ref (no checksums exist for refs).
    mkdir -p "$tmp/skill"
    curl -fsSL "$RAW/skills/$NAME/SKILL.md" -o "$tmp/skill/SKILL.md" \
      || { echo "download failed: $RAW/skills/$NAME/SKILL.md (existing install untouched)" >&2; exit 1; }
    STAGED="$tmp/skill"
    FROM="$RAW"
  else
    if [ -z "$VERSION" ]; then
      VERSION="$(resolve_latest)" \
        || { echo "could not resolve the latest release from $RELEASES/latest (existing install untouched)" >&2; exit 1; }
    fi
    TAG="v${VERSION#v}"
    base="$RELEASES/download/$TAG"
    if command -v tar >/dev/null 2>&1; then asset="$NAME-${TAG#v}.tar.gz"
    elif command -v unzip >/dev/null 2>&1; then asset="$NAME-${TAG#v}.zip"
    else echo "tar or unzip is required" >&2; exit 1
    fi

    curl -fsSL "$base/$asset" -o "$tmp/$asset" \
      || { echo "download failed: $base/$asset (existing install untouched)" >&2; exit 1; }

    if curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" 2>/dev/null; then
      want="$(awk -v f="$asset" '$2==f || $2=="*"f {print $1; exit}' "$tmp/SHA256SUMS")"
      [ -n "$want" ] || { echo "SHA256SUMS has no entry for $asset (existing install untouched)" >&2; exit 1; }
      got="$(sha256 "$tmp/$asset")"
      if [ -z "$got" ]; then
        echo "• no sha256sum or shasum found; checksum not verified" >&2
      elif [ "$got" != "$want" ]; then
        echo "checksum mismatch for $asset: expected $want, got $got (existing install untouched)" >&2
        exit 1
      else
        echo "• verified $asset (sha256 $got)"
      fi
    else
      echo "• SHA256SUMS not found for $TAG; checksum not verified" >&2
    fi

    mkdir -p "$tmp/x"
    case "$asset" in
      *.tar.gz) tar -xzf "$tmp/$asset" -C "$tmp/x" ;;
      *.zip) unzip -q "$tmp/$asset" -d "$tmp/x" ;;
    esac || { echo "could not extract $asset (existing install untouched)" >&2; exit 1; }
    STAGED="$tmp/x/$NAME-${TAG#v}/skills/$NAME"
    FROM="$TAG"
  fi

  if [ ! -f "$STAGED/SKILL.md" ] || ! head -1 "$STAGED/SKILL.md" | grep -qx -- '---'; then
    echo "downloaded files do not contain a valid SKILL.md (existing install untouched)" >&2
    exit 1
  fi
fi

mkdir -p "$CLAUDE_SKILLS_DIR"
if [ -L "$DEST" ]; then
  rm -f "$DEST"
elif [ -e "$DEST" ]; then
  backup="$DEST.bak.$(date +%Y%m%d%H%M%S).$$"
  mv "$DEST" "$backup"
  echo "• backed up existing install to $backup"
fi

if [ "$LINK" -eq 1 ]; then
  ln -s "$SRC_DIR" "$DEST"
  echo "✓ Claude Code: $DEST -> $SRC_DIR"
elif [ -n "$SRC_DIR" ]; then
  mkdir -p "$DEST" && cp -R "$SRC_DIR/." "$DEST/"
  echo "✓ Claude Code: $DEST/SKILL.md (from clone)"
else
  mkdir -p "$DEST" && cp -R "$STAGED/." "$DEST/" && chmod 644 "$DEST/SKILL.md"
  echo "✓ Claude Code: $DEST/SKILL.md (from $FROM)"
fi

if have_opencode; then
  mkdir -p "$OPENCODE_DIR/skills"
  rm -rf "$OC"
  if [ "$OC_COPY" -eq 1 ]; then
    mkdir -p "$OC" && cp -R "$DEST/." "$OC/"
    echo "✓ OpenCode:    $OC (copy)"
  else
    ln -s "$DEST" "$OC"
    echo "✓ OpenCode:    $OC -> $DEST"
  fi
else
  echo "• OpenCode not found, skipped"
fi

v="$(skill_version "$DEST/SKILL.md")"
echo "Done. Installed $NAME ${v:-(unversioned)}. Start a new session and run /$NAME in any repository."
