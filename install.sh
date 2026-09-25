#!/usr/bin/env bash
# install.sh — install the swarm skill.
#
#   curl -fsSL https://raw.githubusercontent.com/gon7187/agent-swarm/main/install.sh | bash
#   or: git clone https://github.com/gon7187/agent-swarm && ./install.sh
#
#   --default        make swarm the default for multi-part tasks (edits ~/.claude/CLAUDE.md
#                     and ~/.codex/AGENTS.md, idempotent marked block, backs up on first edit)
#   --uninstall       remove the installed skill, symlinks, and marked blocks
#   --prefix DIR      install location (default: ~/.agents/skills/swarm)
#   --no-link         skip the ~/.local/bin/swarm convenience symlink
#   -h, --help        show this help
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

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --default) DO_DEFAULT=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --no-link) DO_LINK=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# Replace or append an idempotent marked block in $1, backing up on first edit.
upsert_block() {
  local file="$1" content="$2"
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

if [ "$DO_UNINSTALL" -eq 1 ]; then
  info "removing $PREFIX"
  rm -rf "$PREFIX"
  [ -L "${HOME}/.claude/skills/swarm" ] && rm -f "${HOME}/.claude/skills/swarm"
  [ -L "${HOME}/.local/bin/swarm" ] && rm -f "${HOME}/.local/bin/swarm"
  strip_block "${HOME}/.claude/CLAUDE.md"
  strip_block "${HOME}/.codex/AGENTS.md"
  info "uninstalled"
  exit 0
fi

# --- dependency checks ---
((BASH_VERSINFO[0] >= 4)) || die "bash >= 4 required (found ${BASH_VERSION})"
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq  >/dev/null 2>&1 || die "jq is required"
command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1 || \
  warn "neither 'claude' nor 'codex' found on PATH — swarm will have nothing to run"

# --- locate skill/ source: local checkout or fresh clone ---
CLEANUP_DIR=""
cleanup() { [ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"; }
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

# --- install ---
info "installing to $PREFIX"
rm -rf "$PREFIX"
mkdir -p "$(dirname "$PREFIX")"
cp -r "$REPO_ROOT/skill" "$PREFIX"
chmod +x "$PREFIX/swarm.sh"

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
"$PREFIX/swarm.sh" roster || warn "roster check failed (no active harness on PATH?)"
