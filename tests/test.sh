#!/usr/bin/env bash
# Offline harness stubs: no model calls, credentials or network.
set -euo pipefail
S=$(realpath "$(dirname "$0")/../skill/swarm.sh")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export SWARM_DEPTH=0
unset SWARM_AGENT_DIR SWARM_INHERIT_CONFIG SWARM_UNSAFE_RW SWARM_RW_ALLOW
export SWARM_CLAUDE_BIN="$T/claude" SWARM_CODEX_BIN="$T/codex"
export SWARM_CLAUDE_MODELS='sonnet claude-other' SWARM_CODEX_MODELS='gpt-test gpt-other'
export TEST_ROOT=$T
cat > "$T/harness" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
engine=${0##*/}
if [[ ${1:-} == debug ]]; then
  echo '[{"slug":"gpt-test","visibility":"list"},{"slug":"hidden","visibility":"hide"}]'; exit
fi
printf '%s\n' "$@" > "$SWARM_AGENT_DIR/argv"
out='' prompt='' model='' root=''
while (($#)); do
  case $1 in
    -p) prompt=$2; shift 2 ;;
    -m|--model) model=$2; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -C) root=$2; shift 2 ;;
    *) [[ $1 != *'You are agent'* ]] || prompt=$1; shift ;;
  esac
done
printf '%s\n' "$prompt" > "$SWARM_AGENT_DIR/prompt"
[[ $engine != codex || ( $PWD == "$root" && $root == "$SWARM_AGENT_DIR" ) ]] || exit 88
read_cmd=$(sed -n 's/^  read:  //p' <<< "$prompt")
post_cmd=$(sed -n 's/^  post:  //p' <<< "$prompt")
[[ -z $read_cmd ]] || eval "$read_cmd" >/dev/null
eval "${post_cmd% \[target_agent_id\]}" >/dev/null
# Ignore DIR and spoofed sender when bound to a worker outbox.
"$TEST_ROOT/swarm" post "$TEST_ROOT/spoof" fake bound >/dev/null
[[ $prompt != *SLOW* ]] || sleep 3
if [[ $prompt == *TREE* || ( ${SWARM_AGENT_DIR##*/} == judge && -e $TEST_ROOT/judge-tree ) ]]; then
  bash -c 'trap "" TERM; echo "$BASHPID" > "$TEST_ROOT/descendant"; while :; do sleep 1; done' &
  wait
fi
if [[ $prompt == *COMMIT* && $engine == codex ]]; then
  project=$(sed -n 's/.*Project dir: //p' <<< "$prompt" | head -1)
  common=$(git -C "$project" rev-parse --path-format=absolute --git-common-dir)
  grep -Fxq -- "$common" "$SWARM_AGENT_DIR/argv" || exit 89
  printf '%s\n' "$SWARM_AGENT_DIR" >> "$project/worker.txt"
  git -C "$project" add -- worker.txt
  git -C "$project" -c user.name=Test -c user.email=test@example.com commit -qm worker
fi
if [[ ${SWARM_AGENT_DIR##*/} == judge && -e $TEST_ROOT/judge-no-output ]]; then
  exit 0
fi
if [[ $prompt == *EMPTY* || ( $prompt == *MIXED* && $model == gpt-test ) ]]; then
  if [[ $engine == claude ]]; then echo '{"result":"","total_cost_usd":0.1}'; else : > "$out"; fi
elif [[ $engine == claude ]]; then
  if [[ $prompt == *APIERROR* ]]; then echo '{"result":"error","is_error":true}'
  else echo '{"result":"Claude answer","is_error":false,"total_cost_usd":0.1,"usage":{"input_tokens":10}}'; fi
else
  printf 'Codex answer\n' > "$out"
  echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":2}}'
  echo '{"type":"turn.completed","usage":{"input_tokens":20,"output_tokens":3}}'
fi
[[ $prompt != *FAIL* ]] || exit 7
[[ ${SWARM_AGENT_DIR##*/} != judge || ! -e $TEST_ROOT/fail-judge ]] || exit 9
STUB
chmod +x "$T/harness"
ln -s "$T/harness" "$T/claude"
ln -s "$T/harness" "$T/codex"
ln -s "$S" "$T/swarm"
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() { if "$@" >"$T/reject.log" 2>&1; then fail "accepted: $*"; fi; }
has() { local contents; contents=$(cat "$1"); grep -Fq -- "$2" <<< "$contents" || fail "missing $2 in $1"; }
not_has() { local contents; contents=$(cat "$1"); if grep -Fq -- "$2" <<< "$contents"; then fail "unexpected $2 in $1"; fi; }
[[ $("$S" version) == 0.3.0 ]] || fail version
has <("$S" --help) 'watch DIR'
[[ $("$S" roster | wc -l) == 4 ]] || fail roster
[[ $(env -u SWARM_CODEX_MODELS "$S" roster | tail -1) == gpt-test ]] || fail discovery
mkdir -p "$T/project space"
cd "$T/project space"
git init -q
git -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
"$S" post "$T/board" alice broadcast
"$S" post "$T/board" bob private carol
not_has <("$S" read "$T/board" alice) private
has <("$S" read "$T/board" carol) private
for i in {1..10}; do "$S" post "$T/board" "$i" parallel & done
wait
[[ $(jq -s length "$T/board"/a/*/outbox.jsonl) == 12 ]] || fail outboxes
reject "$S" post "$T/board" ../escape invalid
printf '%s\n' '{"id":"one","model":"sonnet","prompt":"hello"}' '{"id":"two","model":"gpt-test","prompt":"hello"}' > "$T/tasks.jsonl"
"$S" run -j 2 -o "$T/run space" "$T/tasks.jsonl"
[[ $(cat "$T/run space/one.rc") == 0 ]] || fail run
has <("$S" status "$T/run space") 'done rc=0'
has <("$S" status "$T/run space") 'COST=0.1'
has <("$S" status "$T/run space") 'unknown'
[[ $(jq -s length "$T/run space"/a/*/outbox.jsonl) == 4 ]] || fail board
[[ ! -e $T/spoof ]] || fail spoofed-dir
[[ $(jq -r .from "$T/run space/a/two/outbox.jsonl" | sort -u) == two ]] || fail spoofed-author
[[ $(jq .usage.input_tokens "$T/run space/two.usage") == 30 ]] || fail usage
has "$T/run space/a/one/argv" --safe-mode
has "$T/run space/a/one/argv" --strict-mcp-config
has "$T/run space/a/one/argv" 'Bash(git blame:*)'
not_has "$T/run space/a/one/argv" 'Bash(rg:'
not_has "$T/run space/a/one/argv" --bare
has "$T/run space/a/two/argv" --ignore-user-config
has "$T/run space/a/two/argv" shell_environment_policy.inherit=all
not_has "$T/run space/a/two/argv" --add-dir
has <("$S" watch "$T/run space") bound
"$S" all -r 2 -o "$T/all" hello 2> "$T/all-launch"
has "$T/all-launch" '2 agents × 2 rounds + judge = 5 sessions'
[[ $(jq -r .judge "$T/all/run.json") == claude-other ]] || fail independent-judge
[[ -s $T/all/r2/a1.md && -s $T/all/final.md ]] || fail all
[[ $(jq -s length "$T/all"/a/*/outbox.jsonl) == 10 ]] || fail rounds
has "$T/all/a/a1/prompt" 'REFUTED (claim'
not_has "$T/all/a/a1/prompt" '*.md'
"$S" all -m all -r 1 -o "$T/full" hello > /dev/null
[[ $(wc -l < "$T/full/anon.map") == 4 ]] || fail full-roster
has "$T/full/a/a1/prompt" 'Round 1 is independent'
not_has "$T/full/a/a1/prompt" '  read:'
echo running > "$T/all/untouched.rc"
reject "$S" all -o "$T/all" again
[[ $(cat "$T/all/untouched.rc") == running ]] || fail collision-mutated-run
rm "$T/all/untouched.rc"
reject env SWARM_DEPTH=1 "$S" all hello
reject "$S" all -j 0 hello
reject "$S" all -q 0 hello
reject "$S" all -q 3 hello
reject "$S" all -r nope hello
reject "$S" all -t
reject "$S" all -m '../escape' hello
reject "$S" all -m 'sonnet sonnet' hello
for line in \
  '{"id":"../escape","model":"gpt-test","prompt":"hello"}' \
  '{"id":"writer","model":"sonnet","prompt":"hello","mode":"ro","worktree":true}' \
  '{"id":"writer","model":"sonnet","prompt":"hello","mode":"rw"}' \
  '{"id":"writer","model":"sonnet","prompt":"hello","engine":"bad"}' \
  '{broken'; do
  printf '%s\n' "$line" > "$T/bad.jsonl"; reject "$S" run "$T/bad.jsonl"
done
printf '%s\n' '{"id":"dup","model":"gpt-test","prompt":"hello"}' '{"id":"dup","model":"gpt-test","prompt":"hello"}' > "$T/bad.jsonl"
reject "$S" run "$T/bad.jsonl"
reject "$S" all -r 1 -o "$T/failed" FAIL
has <(cat "$T/failed"/r1/*.rc) 7
reject "$S" all -r 1 -o "$T/empty" EMPTY
[[ $(sort -u "$T/empty"/r1/*.rc) == 65 ]] || fail empty-success
reject "$S" all -m sonnet -r 1 -o "$T/apierror" APIERROR
[[ $(cat "$T/apierror/r1/a1.rc") == 65 ]] || fail apierror
"$S" all -q 1 -r 2 -o "$T/partial" MIXED > /dev/null
has "$T/partial/final.md" PARTIAL
has "$T/partial/a/judge/prompt" 'Failed answer files'
failed_id=$(awk '$2 == "gpt-test" {print $1}' "$T/partial/anon.map")
# Failed answers appear only in the explicitly failed list, not the valid one.
not_has <(sed -n '/Valid answer files/,/Failed answer files/p' "$T/partial/a/judge/prompt") "/$failed_id.md"
touch "$T/fail-judge"
reject "$S" all -r 1 -o "$T/retry" hello
before=$(wc -l < "$T/retry/a/a1/outbox.jsonl")
rm "$T/fail-judge"
"$S" judge "$T/retry" -S gpt-other > /dev/null
[[ $(cat "$T/retry/final.rc") == 0 ]] || fail retry
[[ $(wc -l < "$T/retry/a/a1/outbox.jsonl") == "$before" ]] || fail reran-workers
touch "$T/judge-no-output"
reject "$S" judge "$T/retry" -S gpt-other
[[ $(cat "$T/retry/final.rc") == 65 && ! -s $T/retry/final.md ]] || fail stale-answer
rm "$T/judge-no-output"
"$S" all -w -r 1 -o "$T/work" hello > "$T/work-summary"
has "$T/work-summary" 'git merge -- swarm/work/a'
[[ $(git worktree list --porcelain | grep -c '^worktree ') == 3 ]] || fail worktrees
[[ $(jq -s length "$T/work/manifest.jsonl") == 2 ]] || fail manifests
has "$T/work/a/judge/prompt" 'WINNER: <branch>'
for f in "$T/work"/a/a*/argv; do
  not_has "$f" --dangerously-skip-permissions
  if grep -Fq -- --permission-mode "$f"; then has "$f" acceptEdits
  else has "$f" "$T/project space/.git"; fi
done
"$S" clean "$T/work"
[[ $(git worktree list --porcelain | grep -c '^worktree ') == 1 ]] || fail clean
"$S" clean "$T/work"
printf '%s\n' '{"id":"writer","model":"gpt-test","prompt":"COMMIT","worktree":true}' > "$T/tasks.jsonl"
"$S" run -o "$T/task-work" "$T/tasks.jsonl" > /dev/null
wt=$(jq -r .path "$T/task-work/worktrees.jsonl")
[[ $(jq -r '.base != .head' "$T/task-work/manifest.jsonl") == true ]] || fail worker-commit
reject "$S" clean "$T/task-work"
echo preserve > "$wt/dirty"
reject "$S" clean "$T/task-work"
[[ -f $wt/dirty ]] || fail dirty-preservation
rm "$wt/dirty"
git -c user.name=Test -c user.email=test@example.com merge --ff-only swarm/task-work/writer >/dev/null
"$S" clean "$T/task-work"
printf '%s\n' '{"id":"writer","model":"custom","engine":"claude","prompt":"hello","mode":"rw","shared":true}' > "$T/tasks.jsonl"
SWARM_RW_ALLOW='Bash(uv run pytest:*)' "$S" run -o "$T/shared" "$T/tasks.jsonl" > /dev/null
has "$T/shared/a/writer/argv" 'Bash(uv run pytest:*)'
has "$T/shared/a/writer/argv" acceptEdits
SWARM_UNSAFE_RW=1 SWARM_INHERIT_CONFIG=1 "$S" run -o "$T/unsafe" "$T/tasks.jsonl" > /dev/null
has "$T/unsafe/a/writer/argv" --dangerously-skip-permissions
not_has "$T/unsafe/a/writer/argv" --safe-mode
"$S" all -m sonnet -t 1 -o "$T/timeout" SLOW > "$T/timeout.log" 2>&1 &
timeout_pid=$!
for ((i=0; i<200; i++)); do [[ ! -f $T/timeout/r1/a1.rc ]] || break; sleep 0.01; done
has <("$S" status "$T/timeout") running
if wait "$timeout_pid"; then fail timeout; fi
[[ $(cat "$T/timeout/r1/a1.rc") == 124 ]] || fail timeout-code
"$S" all -m sonnet -o "$T/cancel" TREE > "$T/cancel.log" 2>&1 &
cancel_pid=$!
for ((i=0; i<300; i++)); do [[ ! -s $T/descendant ]] || break; sleep 0.01; done
[[ -s $T/descendant ]] || fail descendant-not-started
child=$(cat "$T/descendant")
kill -TERM "$cancel_pid"
if wait "$cancel_pid"; then fail cancel; fi
# Reaped or zombie (awaiting the container init) is no longer spending tokens.
[[ ! -d /proc/$child || $(ps -o stat= -p "$child") == Z* ]] || fail orphan
[[ $(cat "$T/cancel/r1/a1.rc") != running ]] || fail stale-running
cat > "$T/terminal" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/terminal-argv"
STUB
chmod +x "$T/terminal"
DISPLAY=:stub SWARM_TERMINAL="$T/terminal" "$S" all -W -r 1 -o "$T/watch" hello > /dev/null
has "$T/terminal-argv" watch
has "$T/terminal-argv" "$T/watch"
env -u DISPLAY -u WAYLAND_DISPLAY "$S" all -W -r 1 -o "$T/headless" hello > /dev/null
[[ -s $T/headless/final.md ]] || fail headless
# Foreground GNU timeout delivers SIGINT without Bash background-job SIGINT masking.
rm "$T/descendant"
interrupt_rc=0
timeout --preserve-status -s INT -k 5 1 "$S" all -m sonnet -o "$T/interrupt" TREE > "$T/interrupt.log" 2>&1 || interrupt_rc=$?
[[ $interrupt_rc == 130 ]] || fail "interrupt exit=$interrupt_rc"
child=$(cat "$T/descendant")
[[ ! -d /proc/$child || $(ps -o stat= -p "$child") == Z* ]] || fail interrupt-orphan
# Mid-launch worktree failure must terminate already-started workers.
rm "$T/descendant"
mkdir "$T/notrepo" "$T/bin"
export REAL_GIT
REAL_GIT=$(command -v git)
cat > "$T/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ $* == *notrepo* ]]; then
  for ((i=0; i<300; i++)); do [[ ! -s $TEST_ROOT/descendant ]] || break; sleep 0.01; done
  exit 1
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$T/bin/git"
jq -cn '{id:"first",model:"sonnet",prompt:"TREE"},
  {id:"second",model:"gpt-test",prompt:"hello",worktree:true,dir:(env.TEST_ROOT+"/notrepo")}' > "$T/startup.jsonl"
reject env PATH="$T/bin:$PATH" "$S" run -o "$T/startup" "$T/startup.jsonl"
child=$(cat "$T/descendant")
[[ ! -d /proc/$child || $(ps -o stat= -p "$child") == Z* ]] || fail startup-orphan
[[ $(cat "$T/startup/first.rc") != running ]] || fail startup-stale
# A retrying judge also runs asynchronously so signal traps can execute promptly.
rm "$T/descendant"
touch "$T/judge-tree"
"$S" judge "$T/retry" > "$T/judge-cancel.log" 2>&1 &
judge_pid=$!
for ((i=0; i<300; i++)); do [[ ! -s $T/descendant ]] || break; sleep 0.01; done
[[ -s $T/descendant ]] || fail judge-not-started
kill -TERM "$judge_pid"
if wait "$judge_pid"; then fail judge-cancel; fi
child=$(cat "$T/descendant")
[[ ! -d /proc/$child || $(ps -o stat= -p "$child") == Z* ]] || fail judge-orphan
[[ $(cat "$T/retry/final.rc") != running && ! -d $T/retry/.judge-lock ]] || fail judge-stale
rm "$T/judge-tree"
"$S" all -w -m gpt-test -r 2 -o "$T/commit-rounds" COMMIT > /dev/null
[[ $(jq -s '[.[].base] | unique | length' "$T/commit-rounds/manifest.jsonl") == 1 ]] || fail drifting-base
[[ $(grep -c '^+/tmp/' "$T/commit-rounds/r2/a1.diff") == 2 ]] || fail incomplete-diff
# No CLI flag is allowed to silently upgrade an explicit read-only request.
printf '%s\n' '{"id":"reader","model":"sonnet","prompt":"hello","mode":"ro"}' > "$T/ro.jsonl"
reject "$S" run -w "$T/ro.jsonl"
printf 'All tests passed.\n'
