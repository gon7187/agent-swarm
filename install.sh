#!/usr/bin/env bash
# install.sh — install the swarm skill. Run with -h/--help for usage.
set -euo pipefail

REPO_URL="https://github.com/gon7187/agent-swarm.git"
BEGIN_MARK="<!-- swarm:begin -->"
END_MARK="<!-- swarm:end -->"
PREFIX="${HOME}/.agents/skills/swarm"
DO_DEFAULT=0
DO_UNINSTALL=0
DO_LINK=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi
info()  { printf '%s\n' "${BOLD}==>${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}warning:${RESET} $*" >&2; }
die()   { printf '%s\n' "${RED}error:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
install.sh — install the swarm skill.

  curl -fsSL https://raw.githubusercontent.com/gon7187/agent-swarm/main/install.sh | bash
  or: git clone https://github.com/gon7187/agent-swarm && ./install.sh

  --default        make swarm the default for multi-part tasks (edits ~/.claude/CLAUDE.md
                    and ~/.codex/AGENTS.md, idempotent marked block, backs up on first edit)
  --uninstall       remove the installed skill, symlinks, and marked blocks
  --prefix DIR      install location (default: ~/.agents/skills/swarm)
  --no-link         skip the ~/.local/bin/swarm convenience symlink
  -h, --help        show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --default) DO_DEFAULT=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --prefix)
      [ $# -ge 2 ] || die "--prefix requires a value (see --help)"
      PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --no-link) DO_LINK=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# --- resolve and sanity-check the install prefix ---
[ -n "$PREFIX" ] || die "--prefix requires a non-empty value"
PREFIX="$(realpath -m -- "$PREFIX")" || die "cannot resolve --prefix path"
if [ -z "$PREFIX" ] || [ "$PREFIX" = "/" ]; then
  die "refusing to use --prefix / (too dangerous)"
fi
[ "$PREFIX" != "$HOME" ] || die "refusing to use --prefix \$HOME ($PREFIX)"
case "$HOME" in
  "$PREFIX"/*) die "refusing to use --prefix $PREFIX (an ancestor of \$HOME)" ;;
esac

# Only true if $dir doesn't exist, or looks like a previous swarm install.
looks_like_swarm_install() {
  local dir="$1"
  [ -e "$dir" ] || return 0
  [ -d "$dir" ] && [ -f "$dir/SKILL.md" ] && [ -f "$dir/swarm.sh" ]
}

# Fails with a clear message and leaves $1 untouched if its swarm marker
# block isn't exactly one well-formed begin/end pair (or absent entirely).
check_markers() {
  local file="$1" bc ec bl el
  [ -f "$file" ] || return 0
  bc="$(grep -Fc "$BEGIN_MARK" "$file" || true)"
  ec="$(grep -Fc "$END_MARK" "$file" || true)"
  if [ "$bc" -eq 0 ] && [ "$ec" -eq 0 ]; then
    return 0
  fi
  if [ "$bc" -ne 1 ] || [ "$ec" -ne 1 ]; then
    die "malformed swarm marker block in $file (expected exactly one begin/end pair, found $bc begin, $ec end); leaving it unchanged"
  fi
  bl="$(grep -Fn "$BEGIN_MARK" "$file" | cut -d: -f1)"
  el="$(grep -Fn "$END_MARK" "$file" | cut -d: -f1)"
  if [ "$bl" -ge "$el" ]; then
    die "malformed swarm marker block in $file (end marker appears before begin marker); leaving it unchanged"
  fi
}

# Replace or append an idempotent marked block in $1, backing up on first edit.
upsert_block() {
  local file="$1" content="$2"
  check_markers "$file"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -qF "$BEGIN_MARK" "$file"; then
    local tmp; tmp="$(mktemp)"
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v content="$content" '
      $0==begin { print; print content; skip=1; next }
      $0==end   { print; skip=0; next }
      skip      { next }
      { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    [ -f "$file" ] && cp "$file" "$file.bak"
    { printf '\n%s\n%s\n%s\n' "$BEGIN_MARK" "$content" "$END_MARK"; } >> "$file"
  fi
}

strip_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  check_markers "$file"
  grep -qF "$BEGIN_MARK" "$file" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
    $0==begin { skip=1; next }
    $0==end   { skip=0; next }
    skip      { next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Removes $1 only if it's a symlink whose fully-resolved target is $PREFIX
# itself or a path inside it, so an unrelated symlink at the same
# conventional path is left alone.
remove_symlink_into_prefix() {
  local link="$1" resolved
  [ -L "$link" ] || return 0
  resolved="$(readlink -f -- "$link" 2>/dev/null || true)"
  case "$resolved" in
    "$PREFIX"|"$PREFIX"/*) rm -f "$link" ;;
  esac
  return 0
}

if [ "$DO_UNINSTALL" -eq 1 ]; then
  if looks_like_swarm_install "$PREFIX"; then
    remove_symlink_into_prefix "${HOME}/.claude/skills/swarm"
    remove_symlink_into_prefix "${HOME}/.local/bin/swarm"
    info "removing $PREFIX"
    rm -rf "$PREFIX"
    strip_block "${HOME}/.claude/CLAUDE.md"
    strip_block "${HOME}/.codex/AGENTS.md"
    info "uninstalled"
  else
    warn "not removing $PREFIX: it doesn't look like a swarm install (expected SKILL.md and swarm.sh); leaving it in place"
  fi
  exit 0
fi

# --- dependency checks ---
BASH_OK=0
if ((BASH_VERSINFO[0] > 4)); then
  BASH_OK=1
elif ((BASH_VERSINFO[0] == 4)) && ((BASH_VERSINFO[1] >= 3)); then
  BASH_OK=1
fi
((BASH_OK)) || die "bash >= 4.3 required (found ${BASH_VERSION})"
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq  >/dev/null 2>&1 || die "jq is required"
command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1 || \
  warn "neither 'claude' nor 'codex' found on PATH — swarm will have nothing to run"

looks_like_swarm_install "$PREFIX" || die "refusing to overwrite $PREFIX: it doesn't look like a swarm install (expected SKILL.md and swarm.sh)"

# --- locate skill/ source: local checkout or fresh clone ---
CLEANUP_DIR=""
TMP_PREFIX_DIR=""
cleanup() {
  [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"
  [ -n "$TMP_PREFIX_DIR" ] && rm -rf "$TMP_PREFIX_DIR"
  return 0
}
trap cleanup EXIT

SOURCE="${BASH_SOURCE[0]:-}"
REPO_ROOT=""
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
  CANDIDATE="$(cd "$(dirname "$SOURCE")" && pwd)"
  [ -f "$CANDIDATE/skill/SKILL.md" ] && REPO_ROOT="$CANDIDATE"
fi
if [ -z "$REPO_ROOT" ]; then
  info "cloning $REPO_URL"
  CLEANUP_DIR="$(mktemp -d)"
  git clone --depth 1 "$REPO_URL" "$CLEANUP_DIR" >/dev/null
  REPO_ROOT="$CLEANUP_DIR"
fi

# --- install: stage into a temp sibling, then swap it in atomically ---
# (move the old prefix aside, move the staged copy in, then discard the old
# one; if the swap-in fails, the old prefix is moved back so nothing is lost)
info "installing to $PREFIX"
mkdir -p "$(dirname "$PREFIX")"
TMP_PREFIX_DIR="$(mktemp -d "$(dirname "$PREFIX")/.swarm-install.XXXXXX")"
cp -r "$REPO_ROOT/skill/." "$TMP_PREFIX_DIR/"
chmod +x "$TMP_PREFIX_DIR/swarm.sh"
OLD_PREFIX_DIR=""
if [ -e "$PREFIX" ]; then
  OLD_PREFIX_DIR="$PREFIX.old.$$"
  mv "$PREFIX" "$OLD_PREFIX_DIR"
fi
if mv "$TMP_PREFIX_DIR" "$PREFIX"; then
  TMP_PREFIX_DIR=""
  [ -z "$OLD_PREFIX_DIR" ] || rm -rf "$OLD_PREFIX_DIR"
else
  [ -z "$OLD_PREFIX_DIR" ] || mv "$OLD_PREFIX_DIR" "$PREFIX"
  die "failed to move staged install into place"
fi

if [ -d "${HOME}/.claude" ]; then
  mkdir -p "${HOME}/.claude/skills"
  ln -sfn "$PREFIX" "${HOME}/.claude/skills/swarm"
  info "linked ~/.claude/skills/swarm -> $PREFIX"
fi

if [ "$DO_LINK" -eq 1 ]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sfn "$PREFIX/swarm.sh" "${HOME}/.local/bin/swarm"
  info "linked ~/.local/bin/swarm -> $PREFIX/swarm.sh"
fi

if [ "$DO_DEFAULT" -eq 1 ]; then
  BLOCK="For any task with 2+ independent parts, or worth a second opinion (architecture, hard bugs, review, research, estimates), use the swarm skill by default: $PREFIX/SKILL.md (or \`swarm\` if on PATH). Skip it for trivial single-step edits."
  upsert_block "${HOME}/.claude/CLAUDE.md" "$BLOCK"
  upsert_block "${HOME}/.codex/AGENTS.md" "$BLOCK"
  info "made swarm the default in ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md"
fi

printf '%s\n' "${GREEN}==> done${RESET}"
ROSTER_OUT="$("$PREFIX/swarm.sh" roster)" || true
if [ -z "$ROSTER_OUT" ]; then
  warn "roster check failed (no active harness on PATH?)"
else
  printf '%s\n' "$ROSTER_OUT"
fi
