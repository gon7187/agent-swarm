#!/usr/bin/env bash
# swarm.sh — agent swarm over every active harness (claude, codex), with a shared message board.
#
#   swarm.sh roster                              list every model of every active harness
#   swarm.sh all [opts] "task"                   same task -> every model, N rounds of debate, then synthesis
#       -r ROUNDS (default 2)  -m "m1 m2" (subset of roster)  -S SYNTH_MODEL  -w (rw + worktree per agent)
#   swarm.sh run [opts] tasks.jsonl              different tasks -> different agents, one shared board
#       line: {"id":"api","model":"gpt-5.5","prompt":"...","mode":"ro|rw","worktree":true,"dir":"..."}
#   common opts: -j JOBS (default 6)  -t TIMEOUT_S (default 1800)  -o OUTDIR
#
#   swarm.sh post DIR FROM "text" [TO]           post to the board (TO = agent id, default: all)
#   swarm.sh read DIR [ME]                       print board messages (for ME + broadcasts)
#
# Engine is inferred from the model: claude-* -> claude CLI, anything else -> codex CLI.
set -euo pipefail

SELF=$(realpath "$0")
CLAUDE_MODELS="claude-fable-5-1 claude-opus-5-5 claude-sonnet-5 claude-haiku-4-5"

roster() {
  command -v claude >/dev/null && tr ' ' '\n' <<<"$CLAUDE_MODELS"
  command -v codex >/dev/null && codex debug models 2>/dev/null |
    jq -r '.. | objects | select(has("slug") and .visibility == "list") | .slug'
  return 0
}

post() { # DIR FROM TEXT [TO]
  local dir=$1 from=$2 text=$3 to=${4:-all}
  jq -cn --arg f "$from" --arg t "$to" --arg m "$text" --arg ts "$(date +%T)" \
    '{ts:$ts, from:$f, to:$t, msg:$m}' |
    flock "$dir/board.lock" tee -a "$dir/board.jsonl" >/dev/null
}

read_board() { # DIR [ME]
  [[ -f $1/board.jsonl ]] || { echo "(board empty)"; return 0; }
  jq -r --arg me "${2:-}" 'select($me == "" or .to == "all" or .to == $me or .from == $me)
    | "[\(.ts)] \(.from) -> \(.to): \(.msg)"' "$1/board.jsonl"
}

preamble() { # DIR ID
  cat <<EOF
You are agent "$2" in a swarm of AI agents working in parallel. Project dir: $PROJECT
Shared message board (use it to coordinate, share findings, challenge others, avoid duplicate work):
  read:  $SELF read $1 $2
  post:  $SELF post $1 $2 "message" [target_agent_id]
Read the board before starting and before finishing; post key findings and disagreements briefly.
You are a worker: never start another swarm or spawn sub-agents. Your final message is your deliverable.
---
EOF
}

# run_one DIR ID MODEL MODE WORKDIR PROMPT OUTFILE
run_one() {
  local dir=$1 id=$2 model=$3 mode=$4 wd=$5 prompt=$6 md=$7 log=${7%.md}.log rc=0 cmd
  prompt="$(preamble "$dir" "$id")
$prompt"
  if [[ $model == claude-* ]]; then
    cmd=(claude -p "$prompt" --model "$model")
    if [[ $mode == rw ]]; then cmd+=(--dangerously-skip-permissions)
    else cmd+=(--permission-mode dontAsk --allowedTools Read Grep Glob WebSearch WebFetch
      "Bash($SELF read:*)" "Bash($SELF post:*)"); fi
    (cd "$wd" && timeout "$timeout_s" "${cmd[@]}" </dev/null >"$md" 2>>"$log") || rc=$?
  else
    cmd=(codex exec --skip-git-repo-check -m "$model" -o "$md" -s workspace-write)
    # ro: sandbox root is the run dir (board writable, project readable only); rw: project + run dir
    if [[ $mode == rw ]]; then cmd+=(-C "$wd" --add-dir "$dir"); else cmd+=(-C "$dir"); fi
    timeout "$timeout_s" "${cmd[@]}" "$prompt" </dev/null >>"$log" 2>&1 || rc=$?
  fi
  echo "$rc" >"${md%.md}.rc"
}

worktree() { # DIR ID -> prints worktree path
  local repo; repo=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) ||
    { echo "swarm: -w/worktree needs a git repo" >&2; return 1; }
  local wt; wt="$repo/.swarm/wt/$(basename "$1")-$2"
  git -C "$repo" worktree add -q -b "swarm/$(basename "$1")/$2" "$wt" HEAD >&2
  echo "$wt"
}

throttle() { while (($(jobs -rp | wc -l) >= jobs_max)); do wait -n || true; done; }

summary() { # DIR FILES...
  local dir=$1; shift
  printf '%-22s %-4s %s\n' AGENT RC OUTPUT
  for f in "$@"; do printf '%-22s %-4s %s\n' "$(basename "${f%.md}")" "$(cat "${f%.md}.rc" 2>/dev/null || echo '?')" "$f"; done
  echo "board: $dir/board.jsonl ($(wc -l <"$dir/board.jsonl" 2>/dev/null || echo 0) msgs)"
}

sub=${1:-help}; shift || true
case $sub in
  roster) roster; exit ;;
  post) post "$@"; exit ;;
  read) read_board "$@"; exit ;;
  all | run) ;;
  *) sed -n '2,16p' "$SELF"; exit 2 ;;
esac

# Workers must not spawn swarms of their own (fork-bomb guard).
if [[ ${SWARM_DEPTH:-0} -ge 1 ]]; then
  echo "swarm: refusing to nest (SWARM_DEPTH=$SWARM_DEPTH). Do the task yourself." >&2
  exit 3
fi
export SWARM_DEPTH=1

jobs_max=6 timeout_s=1800 out="" rounds=2 models="" synth="" rw=0
while getopts "j:t:o:r:m:S:w" opt; do
  case $opt in
    j) jobs_max=$OPTARG ;; t) timeout_s=$OPTARG ;; o) out=$OPTARG ;;
    r) rounds=$OPTARG ;; m) models=$OPTARG ;; S) synth=$OPTARG ;; w) rw=1 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
PROJECT=$PWD
dir=$(realpath -m "${out:-.swarm/$(date +%Y%m%d-%H%M%S)}")
mkdir -p "$dir"
echo "swarm dir: $dir" >&2

if [[ $sub == run ]]; then
  mapfile -t lines < <(jq -c 'select(.id and .prompt)' "${1:?tasks.jsonl required}")
  [[ ${#lines[@]} -gt 0 ]] || { echo "swarm: no valid tasks" >&2; exit 2; }
  default_model=$(roster | head -1)
  files=()
  for t in "${lines[@]}"; do
    id=$(jq -r .id <<<"$t"); model=$(jq -r ".model // \"$default_model\"" <<<"$t")
    mode=$(jq -r '.mode // "ro"' <<<"$t"); wd=$(jq -r ".dir // \"$PROJECT\"" <<<"$t")
    [[ $(jq -r '.worktree // false' <<<"$t") == true ]] && wd=$(worktree "$dir" "$id")
    files+=("$dir/$id.md")
    throttle; run_one "$dir" "$id" "$model" "$mode" "$wd" "$(jq -r .prompt <<<"$t")" "$dir/$id.md" &
  done
  wait; summary "$dir" "${files[@]}"; exit
fi

# --- all: every model answers, then rounds of cross-critique via board + previous answers ---
task=${1:?task text required}
read -ra ms <<<"${models:-$(roster | tr '\n' ' ')}"
[[ ${#ms[@]} -gt 0 ]] || { echo "swarm: no active harnesses" >&2; exit 2; }
mode=ro; ((rw)) && mode=rw
declare -A wds
for m in "${ms[@]}"; do wds[$m]=$PROJECT; ((rw)) && wds[$m]=$(worktree "$dir" "$m"); done
echo "$task" >"$dir/task.md"

for ((r = 1; r <= rounds; r++)); do
  mkdir -p "$dir/r$r"
  for m in "${ms[@]}"; do
    p="TASK:
$task"
    if ((r > 1)); then
      p+="

ROUND $r of $rounds. Previous-round answers of all agents are in $dir/r$((r - 1))/*.md (read them).
Critique them, adopt what is right, point out errors (post them to the board), and give your improved answer."
    fi
    throttle; run_one "$dir" "$m" "$m" "$mode" "${wds[$m]}" "$p" "$dir/r$r/$m.md" &
  done
  wait
  echo "== round $r done" >&2
done

last=("$dir/r$rounds"/*.md)
synth=${synth:-$(roster | head -1)}
run_one "$dir" "synth" "$synth" ro "$PROJECT" "TASK:
$task

You are the final judge. Final answers of ${#ms[@]} agents are in $dir/r$rounds/*.md; the board has their discussion.
Read them all, resolve disagreements on the merits (not by majority), and write the single best final answer.
Note briefly where agents disagreed and why you sided as you did." "$dir/final.md"
summary "$dir" "${last[@]}" "$dir/final.md"
((rw)) && echo "worktrees: $(git -C "$PROJECT" worktree list | grep -c swarm/) (branches swarm/$(basename "$dir")/*)"
echo "final: $dir/final.md"
