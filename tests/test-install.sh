#!/usr/bin/env bash
# Sandbox tests for install.sh. Nothing outside a temp dir is touched.
# Release downloads come from a local mirror of the release asset layout (file:// and a
# local HTTP server that imitates GitHub's releases/latest redirect). Needs python3.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
VERSION="$(scripts/version.sh)"
T="$(mktemp -d)"
SERVER_PID=""
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

export HOME="$T/home" CLAUDE_SKILLS_DIR="$T/home/.claude/skills" OPENCODE_DIR="$T/home/.config/opencode"
unset ARCH_BOOTSTRAP_VERSION ARCH_BOOTSTRAP_REF ARCH_BOOTSTRAP_RAW ARCH_BOOTSTRAP_RELEASES
DEST="$CLAUDE_SKILLS_DIR/arch-bootstrap"
OC="$OPENCODE_DIR/skills/arch-bootstrap"
mkdir -p "$HOME"

pass=0
fail=0
ok() { echo "  ✓ $*"; pass=$((pass + 1)); }
no() { echo "  ✗ $*" >&2; fail=$((fail + 1)); }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else no "$d"; fi; }
reset() { rm -rf "$HOME/.claude" "$HOME/.config"; }
# Run the installer the way `curl ... | bash` does: from stdin, with no clone next to it.
piped() { bash -s -- "$@" < "$ROOT/install.sh"; }
snapshot() { (cd "$CLAUDE_SKILLS_DIR" && find . -print0 | LC_ALL=C sort -z | xargs -0 ls -ld --time-style=+%s; cat arch-bootstrap/SKILL.md) | sha256sum; }

# Mirror of https://github.com/<repo>/releases: download/<tag>/<asset>
MIRROR="$T/releases"
scripts/build-release.sh "$MIRROR/download/v$VERSION" >/dev/null
mkdir -p "$MIRROR/tag/v$VERSION"

echo "clone mode"
reset
out="$(./install.sh)"
check "copies SKILL.md" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "installed copy is not a symlink" test ! -L "$DEST"
check "--version prints $VERSION" test "$(./install.sh --version | awk '{print $2}')" = "$VERSION"
./install.sh >/dev/null
check "re-install backs up the old install" test "$(find "$CLAUDE_SKILLS_DIR" -maxdepth 1 -name 'arch-bootstrap.bak.*' | wc -l)" -eq 1
./install.sh --link >/dev/null
check "--link symlinks to the clone" test "$(readlink "$DEST")" = "$ROOT/skills/arch-bootstrap"
check "reports clone source" grep -q 'from clone' <<<"$out"

echo "OpenCode"
reset
mkdir -p "$OPENCODE_DIR"
./install.sh >/dev/null
check "links OpenCode to the Claude skill" test "$(readlink "$OC")" = "$DEST"
./install.sh --copy-opencode >/dev/null
check "--copy-opencode copies" test -f "$OC/SKILL.md" -a ! -L "$OC"

echo "release mode, pinned version (file:// mirror)"
reset
out="$(ARCH_BOOTSTRAP_RELEASES="file://$MIRROR" ARCH_BOOTSTRAP_VERSION="v$VERSION" piped)"
check "installs SKILL.md from the release tarball" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "verifies the checksum" grep -q "verified arch-bootstrap-$VERSION.tar.gz" <<<"$out"
ARCH_BOOTSTRAP_RELEASES="file://$MIRROR" ARCH_BOOTSTRAP_VERSION="$VERSION" piped >/dev/null
check "accepts a version without the leading v" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "--version works when piped" test "$(piped --version | awk '{print $2}')" = "$VERSION"

echo "release mode, zip fallback when tar is missing"
reset
nobin="$T/notar-bin"
mkdir -p "$nobin"
for tool in bash curl awk grep head mkdir mktemp rm cp chmod mv date ln cat sha256sum unzip dirname; do
  ln -s "$(command -v "$tool")" "$nobin/$tool"
done
out="$(PATH="$nobin" ARCH_BOOTSTRAP_RELEASES="file://$MIRROR" ARCH_BOOTSTRAP_VERSION="v$VERSION" "$nobin/bash" -s < install.sh)"
check "installs from the zip" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "verifies the zip checksum" grep -q "verified arch-bootstrap-$VERSION.zip" <<<"$out"

echo "release mode, latest release via redirect (local HTTP server)"
reset
port_file="$T/port"
python3 -I - "$T" "$port_file" "v$VERSION" <<'PY' &
import http.server, os, sys, functools
root, port_file, tag = sys.argv[1], sys.argv[2], sys.argv[3]
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_HEAD(self): self.route() or super().do_HEAD()
    def do_GET(self): self.route() or super().do_GET()
    def route(self):
        if self.path == "/releases/latest":
            self.send_response(302); self.send_header("Location", "/releases/tag/" + tag)
            self.send_header("Content-Length", "0"); self.end_headers(); return True
        if self.path.startswith("/releases/tag/"):
            self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers(); return True
        return False
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(H, directory=root))
open(port_file, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
SERVER_PID=$!
for _ in $(seq 50); do [ -s "$port_file" ] && break; sleep 0.1; done
URL="http://127.0.0.1:$(cat "$port_file")/releases"
out="$(ARCH_BOOTSTRAP_RELEASES="$URL" piped)"
check "resolves latest and installs it" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "reports the resolved tag v$VERSION" grep -q "from v$VERSION" <<<"$out"

echo "failures leave the existing install untouched"
before="$(snapshot)"
bad="$T/bad-releases"
cp -R "$MIRROR" "$bad"
sed -i -E '/tar\.gz$/ s/^[0-9a-f]{8}/00000000/' "$bad/download/v$VERSION/SHA256SUMS"
if err="$(ARCH_BOOTSTRAP_RELEASES="file://$bad" ARCH_BOOTSTRAP_VERSION="v$VERSION" piped 2>&1)"; then
  no "checksum mismatch must fail"
else
  ok "checksum mismatch fails"
fi
check "reports the mismatch" grep -q "checksum mismatch" <<<"$err"
check "install unchanged after mismatch" test "$(snapshot)" = "$before"

if ARCH_BOOTSTRAP_RELEASES="file://$MIRROR" ARCH_BOOTSTRAP_VERSION="v9.9.9" piped >/dev/null 2>&1; then
  no "missing release must fail"
else
  ok "missing release fails"
fi
check "install unchanged after failed download" test "$(snapshot)" = "$before"

rm -rf "$bad"
cp -R "$MIRROR" "$bad"
grep -v 'tar\.gz$' "$MIRROR/download/v$VERSION/SHA256SUMS" > "$bad/download/v$VERSION/SHA256SUMS"
if ARCH_BOOTSTRAP_RELEASES="file://$bad" ARCH_BOOTSTRAP_VERSION="v$VERSION" piped >/dev/null 2>&1; then
  no "SHA256SUMS without an entry must fail"
else
  ok "SHA256SUMS without an entry for the asset fails"
fi
check "install unchanged after missing entry" test "$(snapshot)" = "$before"

echo "release without SHA256SUMS"
rm "$bad/download/v$VERSION/SHA256SUMS"
err="$(ARCH_BOOTSTRAP_RELEASES="file://$bad" ARCH_BOOTSTRAP_VERSION="v$VERSION" piped 2>&1 >/dev/null)"
check "installs with a warning" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "warns that the checksum was not verified" grep -q "checksum not verified" <<<"$err"

echo "bleeding edge (ARCH_BOOTSTRAP_REF)"
reset
out="$(ARCH_BOOTSTRAP_REF=main ARCH_BOOTSTRAP_RAW="file://$ROOT" piped)"
check "installs SKILL.md from the ref" cmp -s "$DEST/SKILL.md" skills/arch-bootstrap/SKILL.md
check "reports the raw source" grep -q "from file://$ROOT" <<<"$out"

echo "uninstall"
mkdir -p "$OPENCODE_DIR"
./install.sh >/dev/null
piped --uninstall >/dev/null
check "removes the Claude skill" test ! -e "$DEST" -a ! -L "$DEST"
check "removes the OpenCode skill" test ! -e "$OC" -a ! -L "$OC"
if ./install.sh --version >/dev/null 2>&1; then no "--version must fail when not installed"; else ok "--version fails when not installed"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
