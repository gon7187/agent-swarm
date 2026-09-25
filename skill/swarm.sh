#!/usr/bin/env bash
# swarm.sh — multi-harness agents with a shared message board (bash >= 4.3 + jq).
# Usage:
#   swarm.sh roster                         list active harness models
#   swarm.sh all [opts] "task"               rounds of critique, then a final judge
#   swarm.sh run [opts] tasks.jsonl          one task per JSON line
#     {"id","model","prompt","mode":"ro|rw","worktree":false,"dir"}
#   swarm.sh post DIR FROM "text" [TO]       locked board append (default TO: all)
#   swarm.sh read DIR [ME]                   broadcasts and messages to/from ME
#   swarm.sh status DIR                      agent states and board count
#   swarm.sh clean DIR                       remove clean, merged run worktrees/branches
#   swarm.sh version | --help
# Options: -j jobs (6), -t timeout_s (1800), -o outdir (.swarm/<timestamp>)
#          -r rounds (2), -m "models", -S judge, -w (rw + isolated worktrees)
# Environment: SWARM_CLAUDE_BIN, SWARM_CODEX_BIN, SWARM_CLAUDE_MODELS,
#              SWARM_CODEX_MODELS, SWARM_DEPTH (workers cannot start swarms).
set -euo pipefail
SELF=$(realpath "$0")
CLAUDE=${SWARM_CLAUDE_BIN:-claude}
CODEX=${SWARM_CODEX_BIN:-codex}
CLAUDE_MODELS=${SWARM_CLAUDE_MODELS-'claude-fable-5-1 claude-opus-5-5 claude-sonnet-5 claude-haiku-4-5'}

die() { echo "swarm: $*" >&2; exit 2; }
help_text() { sed -n '2,/^set /{ /^set /d; s/^# \{0,1\}//; p; }' "$SELF"; }
safe_name() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; }
roster() {
  if command -v "$CLAUDE" >/dev/null; then
    tr ' \t' '\n' <<< "$CLAUDE_MODELS" | sed '/^$/d'
  fi
  if command -v "$CODEX" >/dev/null; then
    if [[ ${SWARM_CODEX_MODELS+x} ]]; then
      tr ' \t' '\n' <<< "$SWARM_CODEX_MODELS" | sed '/^$/d'
    else
      "$CODEX" debug models | jq -r '.. | objects | select(.visibility? == "list") | .slug // empty'
    fi
  fi
}
post() {
  local dir=$1 from=$2 message=$3 to=${4:-all}
  mkdir -p "$dir"
  (flock -x 9
   jq -cn --arg f "$from" --arg t "$to" --arg m "$message" --arg ts "$(date -u +%FT%TZ)" \
     '{ts:$ts,from:$f,to:$t,msg:$m}' >> "$dir/board.jsonl"
  ) 9>"$dir/board.lock"
}
read_board() {
  [[ -f $1/board.jsonl ]] || { echo '(board empty)'; return; }
  (flock -s 9
   jq -r --arg me "${2:-}" 'select($me == "" or .to == "all" or .to == $me or .from == $me)
     | "[\(.ts)] \(.from) -> \(.to): \(.msg)"' "$1/board.jsonl"
  ) 9>"$1/board.lock"
}
status() {
  local dir=$1 f rc count=0
  [[ -d $dir ]] || die "no run directory: $dir"
  shopt -s nullglob
  for f in "$dir"/*.rc "$dir"/r*/*.rc; do
    rc=$(cat "$f")
    if [[ $rc == running ]]; then printf '%s running\n' "${f#"$dir/"}";
    else printf '%s done rc=%s\n' "${f#"$dir/"}" "$rc"; fi
  done
  [[ ! -f $dir/board.jsonl ]] || count=$(jq -s length "$dir/board.jsonl")
  echo "board: $count messages"
}
clean() {
  local dir=$1 row repo path branch current f
  [[ -d $dir ]] || die "no run directory: $dir"
  [[ -f $dir/worktrees.jsonl ]] || { echo 'No worktrees recorded.'; return; }
  shopt -s nullglob
  for f in "$dir"/*.rc "$dir"/r*/*.rc; do
    [[ $(cat "$f") != running ]] || die "agent still running: $f"
  done
  while IFS= read -r row; do
    repo=$(jq -r .repo <<< "$row"); path=$(jq -r .path <<< "$row"); branch=$(jq -r .branch <<< "$row")
    # Never force removal: dirty files and unmerged agent commits belong to the user.
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$repo" merge-base --is-ancestor "$branch" HEAD || die "merge $branch before cleaning"
    fi
    if [[ -d $path ]]; then
      current=$(git -C "$path" symbolic-ref --short HEAD) || die "detached worktree: $path"
      [[ $current == "$branch" ]] || die "worktree branch changed: $path"
      [[ -z $(git -C "$path" status --porcelain) ]] || die "dirty worktree: $path"
      git -C "$repo" worktree remove "$path"
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$repo" branch -d "$branch"
    fi
  done < "$dir/worktrees.jsonl"
}
preamble() {
  printf 'You are agent "%s" in a swarm. Project dir: %s\n' "$2" "$3"
  printf 'Shared message board:\n  read:  %q read %q %q\n' "$SELF" "$1" "$2"
  printf '  post:  %q post %q %q "message" [target_agent_id]\n' "$SELF" "$1" "$2"
  echo 'Read the board before starting and before finishing; post findings briefly.'
  echo 'You are a worker: never start another swarm or spawn sub-agents. Your final message is your deliverable.'
}
run_one() {
  local id=$1 model=$2 mode=$3 wd=$4 prompt=$5 md=$6 rc=0
  local log=${md%.md}.log
  local -a cmd
  prompt="$(preamble "$dir" "$id" "$wd")
---
$prompt"
  echo running > "${md%.md}.rc"
  if [[ $model == claude-* ]]; then
    cmd=("$CLAUDE" -p "$prompt" --model "$model")
    if [[ $mode == rw ]]; then cmd+=(--dangerously-skip-permissions)
    else cmd+=(--permission-mode dontAsk --allowedTools Read Grep Glob WebSearch WebFetch
      "Bash($SELF read:*)" "Bash($SELF post:*)"); fi
    (cd "$wd" && timeout "$timeout_s" "${cmd[@]}" </dev/null >"$md" 2>"$log") || rc=$?
  else
    cmd=("$CODEX" exec --skip-git-repo-check -m "$model" -o "$md" -s workspace-write)
    if [[ $mode == rw ]]; then cmd+=(-C "$wd" --add-dir "$dir"); else cmd+=(-C "$dir"); fi
    timeout "$timeout_s" "${cmd[@]}" "$prompt" </dev/null >"$log" 2>&1 || rc=$?
  fi
  echo "$rc" > "${md%.md}.rc"
  return "$rc"
}
worktree() {
  local id=$1 source=$2 repo wt branch
  repo=$(git -C "$source" rev-parse --show-toplevel) || die 'worktree needs a git repo'
  branch="swarm/$(basename "$dir")/$id"
  git check-ref-format --branch "$branch" >/dev/null || die "invalid worktree branch: $branch"
  wt="$repo/.swarm/wt/$(basename "$dir")-$id"
  git -C "$repo" worktree add -q -b "$branch" "$wt" HEAD >&2
  jq -cn --arg repo "$repo" --arg path "$wt" --arg branch "$branch" \
    '{repo:$repo,path:$path,branch:$branch}' >> "$dir/worktrees.jsonl"
  printf '%s\n' "$wt"
}
throttle() { while (($(jobs -rp | wc -l) >= jobs_max)); do wait -n || true; done; }
check_results() {
  local f failed=0
  for f in "$@"; do [[ $(cat "${f%.md}.rc") == 0 ]] || failed=1; done
  return "$failed"
}
branches() {
  if [[ -f $dir/worktrees.jsonl ]]; then
    echo 'Branches to review and merge:'
    jq -r '"  \(.branch)  \(.path)"' "$dir/worktrees.jsonl"
  fi
}
sub=${1:---help}; shift || true
case $sub in
  help|-h|--help) help_text; exit 0 ;;
  version) echo 0.2.0; exit 0 ;;
  roster) (($# == 0)) || die 'roster takes no arguments'; roster; exit ;;
  post) (($# >= 3 && $# <= 4)) || die 'post DIR FROM TEXT [TO]'; post "$@"; exit ;;
  read) (($# >= 1 && $# <= 2)) || die 'read DIR [ME]'; read_board "$@"; exit ;;
  status) (($# == 1)) || die "status DIR"; status "$1"; exit ;;
  clean) (($# == 1)) || die "clean DIR"; clean "$1"; exit ;;
  all|run) ;;
  *) die "unknown command: $sub (see --help)" ;;
esac
[[ ${SWARM_DEPTH:-0} == 0 ]] || { echo 'swarm: refusing to nest' >&2; exit 3; }
export SWARM_DEPTH=1
jobs_max=6 timeout_s=1800 out='' rounds=2 models='' synth='' rw=0
while getopts ':j:t:o:r:m:S:wh' opt; do
  case $opt in
    j) jobs_max=$OPTARG ;; t) timeout_s=$OPTARG ;; o) out=$OPTARG ;;
    r) rounds=$OPTARG ;; m) models=$OPTARG ;; S) synth=$OPTARG ;; w) rw=1 ;;
    h) help_text; exit 0 ;; *) die 'invalid option or missing value (see --help)' ;;
  esac
done
shift $((OPTIND - 1))
(($# == 1)) || die "$sub requires exactly one task argument"
for n in "$jobs_max" "$timeout_s" "$rounds"; do
  [[ $n =~ ^[1-9][0-9]*$ && ${#n} -le 8 ]] || die 'jobs, timeout and rounds must be positive integers'
done
PROJECT=$PWD
files=()
if [[ $sub == run ]]; then
  tasks=$(jq -sc --arg dir "$PROJECT" '
    map(. + {mode:(.mode // "ro"),worktree:(.worktree // false),dir:(.dir // $dir)})
    | if length > 0 and all(.[];
      (.id | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
      (.model | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
      (.prompt | type == "string") and (.dir | type == "string" and length > 0) and
      (.mode == "ro" or .mode == "rw") and (.worktree | type == "boolean")) and
      ((map(.id) | unique | length) == length)
      then . else error("invalid or duplicate tasks") end' "$1") || die 'invalid tasks.jsonl'
  mapfile -t lines < <(jq -c '.[]' <<< "$tasks")
  for t in "${lines[@]}"; do
    wd=$(jq -r .dir <<< "$t")
    [[ -d $wd ]] || die "missing working directory: $wd"
  done
else
  if [[ -z $models ]]; then models=$(roster) || die 'model discovery failed'; fi
  read -ra ms <<< "${models//$'\n'/ }"
  ((${#ms[@]})) || die 'no active harnesses'
  declare -A seen=()
  for m in "${ms[@]}"; do
    safe_name "$m" || die "invalid model: $m"
    [[ ! ${seen[$m]+yes} ]] || die "duplicate model: $m"
    seen[$m]=1
  done
  synth=${synth:-${ms[0]}}
  safe_name "$synth" || die 'invalid judge model'
fi
dir=$(realpath -m "${out:-.swarm/$(date +%Y%m%d-%H%M%S)-$$}")
# mkdir is the run reservation: never silently overwrite another run's evidence.
mkdir -p "$(dirname "$dir")"
mkdir "$dir" || die 'output directory already exists'
: > "$dir/board.jsonl"
echo "swarm dir: $dir" >&2
if [[ $sub == run ]]; then
  for t in "${lines[@]}"; do
    id=$(jq -r .id <<< "$t"); model=$(jq -r .model <<< "$t")
    mode=$(jq -r .mode <<< "$t"); wd=$(jq -r .dir <<< "$t")
    [[ -d $wd ]] || die "missing working directory: $wd"
    wd=$(realpath "$wd")
    if ((rw)) || [[ $(jq -r .worktree <<< "$t") == true ]]; then
      wd=$(worktree "$id" "$wd"); mode=rw
    fi
    files+=("$dir/$id.md")
    throttle
    run_one "$id" "$model" "$mode" "$wd" "$(jq -r .prompt <<< "$t")" "$dir/$id.md" &
  done
  wait
  status "$dir"; branches
  check_results "${files[@]}"
  exit
fi
task=$1
mode=ro; ((rw == 0)) || mode=rw
declare -A wds
for m in "${ms[@]}"; do
  wds[$m]=$PROJECT
  if ((rw)); then wds[$m]=$(worktree "$m" "$PROJECT"); fi
done
printf '%s\n' "$task" > "$dir/task.md"
failed=0
for ((r=1; r<=rounds; r++)); do
  mkdir "$dir/r$r"
  files=()
  for m in "${ms[@]}"; do
    p="TASK:
$task"
    if ((r > 1)); then
      p+="
ROUND $r of $rounds. Read all previous answers in $dir/r$((r-1))/*.md and the board.
Critique errors, post disagreements, adopt correct findings and give your improved answer."
    fi
    files+=("$dir/r$r/$m.md")
    throttle
    run_one "$m" "$m" "$mode" "${wds[$m]}" "$p" "$dir/r$r/$m.md" &
  done
  wait
  check_results "${files[@]}" || failed=1
  ((failed == 0)) || break
done
if ((failed == 0)); then
  run_one judge "$synth" ro "$PROJECT" "TASK:
$task
You are the final judge. Read all answers in $dir/r$rounds/*.md and the board.
Resolve disagreements on the merits, not by majority. Write the best final answer and briefly explain disputed decisions." "$dir/final.md" || failed=1
fi
status "$dir"; branches
[[ ! -f $dir/final.md ]] || echo "final: $dir/final.md"
exit "$failed"
