#!/usr/bin/env bash
# Offline tests for install.sh: fake HOME, fake PATH (claude/codex stubs and,
# for one test, a fake mv), no network access and no real harness calls.
set -euo pipefail
INSTALL=$(realpath "$(dirname "$0")/../install.sh")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

REAL_MV=$(command -v mv)

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { local contents; contents=$(cat "$1"); grep -Fq -- "$2" <<< "$contents" || fail "missing $2 in $1"; }
not_has() { local contents; contents=$(cat "$1"); if grep -Fq -- "$2" <<< "$contents"; then fail "unexpected $2 in $1"; fi; }

BIN="$T/bin"
mkdir -p "$BIN"
for tool in claude codex; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$tool"
  chmod +x "$BIN/$tool"
done
export PATH="$BIN:$PATH"
export SWARM_CODEX_MODELS="gpt-test"

HOME_DIR="$T/home"
mkdir -p "$HOME_DIR/.claude"
export HOME="$HOME_DIR"
PREFIX="$HOME_DIR/.agents/skills/swarm"

no_leftovers() {
  shopt -s nullglob
  local leftovers=("$(dirname "$PREFIX")"/.swarm-install.* "$PREFIX".old.*)
  shopt -u nullglob
  [ ${#leftovers[@]} -eq 0 ] || fail "leftover temp/backup dirs: ${leftovers[*]}"
}

# --- fresh install ---
OUT=$("$INSTALL" --default 2>&1) || fail "install failed: $OUT"
[ -f "$PREFIX/SKILL.md" ] || fail "SKILL.md missing after install"
[ -x "$PREFIX/swarm.sh" ] || fail "swarm.sh missing or not executable after install"
[ -L "$HOME_DIR/.claude/skills/swarm" ] || fail "missing ~/.claude/skills/swarm symlink"
[ -L "$HOME_DIR/.local/bin/swarm" ] || fail "missing ~/.local/bin/swarm symlink"
has <(printf '%s' "$OUT") 'claude-sonnet-5'
not_has <(printf '%s' "$OUT") 'roster check failed'
has "$HOME_DIR/.claude/CLAUDE.md" '<!-- swarm:begin -->'
has "$HOME_DIR/.codex/AGENTS.md" '<!-- swarm:begin -->'
no_leftovers

# --- reinstall: atomic replace keeps the install working ---
OUT=$("$INSTALL" 2>&1) || fail "reinstall failed: $OUT"
[ -f "$PREFIX/SKILL.md" ] || fail "SKILL.md missing after reinstall"
[ -x "$PREFIX/swarm.sh" ] || fail "swarm.sh missing or not executable after reinstall"
"$PREFIX/swarm.sh" version >/dev/null || fail "swarm.sh broken after reinstall"
no_leftovers

# --- atomic install: a failure moving the staged dir into place restores the old one ---
MARKER="$PREFIX/marker-before-failed-reinstall"
touch "$MARKER"
MV_LOG="$T/mv-calls"
: > "$MV_LOG"
cat > "$BIN/mv" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$MV_LOG"
n=\$(wc -l < "$MV_LOG")
if [ "\$n" -eq 2 ]; then
  echo "fake mv: forced failure on call \$n" >&2
  exit 1
fi
exec "$REAL_MV" "\$@"
EOF
chmod +x "$BIN/mv"
if "$INSTALL" >"$T/fail-install.log" 2>&1; then
  fail "install unexpectedly succeeded despite a forced mv failure"
fi
has "$T/fail-install.log" "failed to move staged install into place"
[ -f "$MARKER" ] || fail "old install was not restored after a failed atomic swap"
no_leftovers
rm -f "$BIN/mv"
rm -f "$MARKER"

# --- --uninstall with a refused prefix leaves everything else intact ---
DECOY="$HOME_DIR/not-a-swarm-install"
mkdir -p "$DECOY"
touch "$DECOY/unrelated-file"
OUT=$("$INSTALL" --uninstall --prefix "$DECOY" 2>&1) || fail "refused uninstall should still exit 0: $OUT"
has <(printf '%s' "$OUT") "leaving it in place"
[ -f "$DECOY/unrelated-file" ] || fail "decoy prefix was touched"
[ -L "$HOME_DIR/.claude/skills/swarm" ] || fail "symlink removed despite refused prefix"
[ -L "$HOME_DIR/.local/bin/swarm" ] || fail "symlink removed despite refused prefix"
[ -d "$PREFIX" ] || fail "real prefix removed despite refused prefix"
has "$HOME_DIR/.claude/CLAUDE.md" '<!-- swarm:begin -->'
has "$HOME_DIR/.codex/AGENTS.md" '<!-- swarm:begin -->'

# --- --uninstall on the real prefix removes everything ---
OUT=$("$INSTALL" --uninstall 2>&1) || fail "uninstall failed: $OUT"
[ ! -e "$PREFIX" ] || fail "prefix still present after uninstall"
[ ! -L "$HOME_DIR/.claude/skills/swarm" ] || fail "symlink still present after uninstall"
[ ! -L "$HOME_DIR/.local/bin/swarm" ] || fail "symlink still present after uninstall"
not_has "$HOME_DIR/.claude/CLAUDE.md" '<!-- swarm:begin -->'
not_has "$HOME_DIR/.codex/AGENTS.md" '<!-- swarm:begin -->'

# --- --help works when piped via curl|bash (no $0 file to read) ---
OUT=$(bash -s -- --help < "$INSTALL")
has <(printf '%s' "$OUT") '--uninstall'
has <(printf '%s' "$OUT") '--prefix DIR'

echo OK
