#!/usr/bin/env bash
# Offline harness stubs: no model calls, credentials or network.
set -euo pipefail
S=$(realpath "$(dirname "$0")/../skill/swarm.sh")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export SWARM_DEPTH=0
unset SWARM_AGENT_DIR SWARM_INHERIT_CONFIG SWARM_UNSAFE_RW SWARM_RW_ALLOW SWARM_RO_ALLOW SWARM_DETACHED_DIR
export SWARM_CLAUDE_BIN="$T/claude" SWARM_CODEX_BIN="$T/codex"
export SWARM_CLAUDE_MODELS='sonnet claude-other' SWARM_CODEX_MODELS='gpt-test gpt-other'
export TEST_ROOT=$T
FIXTURES=$(realpath "$(dirname "$0")/fixtures")
export FIXTURES
cat > "$T/harness" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
engine=${0##*/}
if [[ ${1:-} == debug ]]; then
  [[ ! -e $TEST_ROOT/discovery-fail ]] || exit 1
  echo '[{"slug":"gpt-test","visibility":"list","supported_reasoning_efforts":[{"effort":"low"},{"effort":"high"}]},{"slug":"hidden","visibility":"hide"}]'; exit
fi
printf '%s\n' "$@" > "$SWARM_AGENT_DIR/argv"
if [[ -d $TEST_ROOT/conc ]]; then # record peak concurrency
  mkdir "$TEST_ROOT/conc/$$"
  trap 'rmdir "$TEST_ROOT/conc/$$"' EXIT
  find "$TEST_ROOT/conc" -mindepth 1 -maxdepth 1 | wc -l >> "$TEST_ROOT/conc.max"
fi
out='' prompt='' model='' root=''
while (($#)); do
  case $1 in
    -p) shift ;;
    -m|--model) model=$2; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -C) root=$2; shift 2 ;;
    *) [[ $1 != *'You are agent'* ]] || prompt=$1; shift ;;
  esac
done
prompt=$(cat)
printf '%s\n' "$prompt" > "$SWARM_AGENT_DIR/prompt"
[[ $engine != codex || ( $PWD == "$root" && $root == "$SWARM_AGENT_DIR" ) ]] || exit 88
read_cmd=$(sed -n 's/^  read:  //p' <<< "$prompt")
post_cmd=$(sed -n 's/^  post:  //p' <<< "$prompt")
[[ -z $read_cmd ]] || eval "$read_cmd" >/dev/null
eval "${post_cmd% \[target_agent_id\]}" >/dev/null
# Ignore DIR and spoofed sender when bound to a worker outbox.
"$TEST_ROOT/swarm" post "$TEST_ROOT/spoof" fake bound >/dev/null
[[ $prompt != *SLOW* ]] || sleep 3
[[ $prompt != *CONC* ]] || sleep 0.1
[[ $prompt != *LAUNCHLOG* ]] || echo "$engine ${SWARM_AGENT_DIR##*/}" >> "$TEST_ROOT/launches"
if [[ $engine == codex && ${SWARM_AGENT_DIR##*/} != judge ]]; then
  if [[ $prompt == *RATE429* && ! -e $TEST_ROOT/rate-hit ]]; then
    touch "$TEST_ROOT/rate-hit"; echo '{"type":"error","message":"429 Too Many Requests"}'; exit 1
  fi
  [[ $prompt != *EXHAUST* ]] || { cat "$FIXTURES/codex-usage-limit.jsonl"; exit 1; }
  [[ $prompt != *RLITEM* ]] || { head -n 4 "$FIXTURES/codex-usage-limit.jsonl"; exit 1; }
fi
if [[ $prompt == *TREE* || ( ${SWARM_AGENT_DIR##*/} == judge && -e $TEST_ROOT/judge-tree ) ]]; then
  bash -c 'trap "" TERM; echo "$BASHPID" > "$TEST_ROOT/descendant"; while :; do sleep 1; done' &
  wait
fi
if [[ $prompt == *COMMIT* && $engine == codex ]]; then
  project=$(sed -n 's/.*Project dir: //p' <<< "$prompt" | head -1)
  common=$(git -C "$project" rev-parse --path-format=absolute --git-common-dir)
  if grep -Fxq -- "$common" "$SWARM_AGENT_DIR/argv"; then exit 89; fi
  printf '%s\n' "$SWARM_AGENT_DIR" >> "$project/worker.txt"
  if [[ $prompt == *SWITCH* ]]; then git -C "$project" switch -qc switched; fi
fi
if [[ ${SWARM_AGENT_DIR##*/} == judge && -e $TEST_ROOT/judge-no-output ]]; then
  exit 0
fi
answer="FINAL ANSWER (complete, standalone): harness answer from ${SWARM_AGENT_DIR##*/}"
[[ $prompt != *NOFINAL* ]] || answer='incomplete answer'
[[ $prompt != *MDHEADING* ]] || answer=$'Analysis first.\n\n## **FINAL ANSWER**\nharness answer'
[[ $prompt != *INLINEFINAL* ]] || answer='this merely mentions a FINAL ANSWER inline'
[[ $prompt != *RLTEXT* ]] || answer='The upstream API hit a rate limit (429 Too Many Requests); usage limit notes.'
if [[ ${SWARM_AGENT_DIR##*/} == judge ]]; then
  run_dir=${SWARM_AGENT_DIR%/a/judge}
  if [[ -f $run_dir/worktrees.jsonl ]]; then
    winner=$(jq -r .branch "$run_dir/worktrees.jsonl" | head -1)
    [[ $prompt != *BADWINNER* ]] || winner=invalid
    [[ $prompt != *NOWINNER* ]] || winner=NONE
    answer+=$'\nWINNER: '"$winner"
  fi
fi
# Loop judge: each call consumes the next judge-script line "VERDICT SCORE BEST [INCUMBENT_SCORE] [BAD|DEFECTS|STRAT|MERGE|TRAIL]".
if [[ ${SWARM_AGENT_DIR##*/} == judge && $prompt == *'You are the loop judge'* ]]; then
  n=$(( $(cat "$TEST_ROOT/judge-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$TEST_ROOT/judge-n"
  [[ $prompt != *DIRTYWIN* ]] || echo late > "$(jq -r .path "${SWARM_AGENT_DIR%/a/judge}/worktrees.jsonl" | tail -n 1)/late"
  v='' s='' b='' i='' x=''
  read -r v s b i x < <(sed -n "${n}p" "$TEST_ROOT/judge-script") || true
  if [[ $v == BAD ]]; then answer='no decision here'
  else
    json=$(jq -cn --arg v "$v" --argjson s "$s" --arg b "$b" --argjson i "${i:-0}" --arg x "${x:-}" --arg n "$n" '{verdict:$v,score:$s,incumbent_score:$i,best:$b,
      defects:(if $v == "STOP" and $x != "DEFECTS" then [] else ["defect \($n)"] end),
      directions:(if $v == "STOP" then [] else ["direction \($n)"] end),
      strategy_change:(if $x == "STRAT" then "strategy \($n)" else "" end)}')
    answer=$'Judgment.\n```json\n'"$json"$'\n```'
    [[ ${x:-} != MERGE ]] || answer=$'=== BEST ===\nmerged text\n=== END BEST ===\n'"$answer"
    [[ ${x:-} != TRAIL ]] || answer+=$'\ntrailing prose'
  fi
fi
if [[ $prompt == *EMPTY* || ( $prompt == *MIXED* && $model == gpt-test ) ]]; then
  if [[ $engine == claude ]]; then echo '{"result":"","total_cost_usd":0.1}'; else : > "$out"; fi
elif [[ $engine == claude ]]; then
  if [[ $prompt == *APIERROR* ]]; then echo '{"result":"error","is_error":true}'
  elif [[ $prompt == *CUSTOMRL* && ${SWARM_AGENT_DIR##*/} != judge ]]; then echo '{"result":"custom-throttle hit","is_error":true}'
  else jq -cn --arg answer "$answer" '{result:$answer,is_error:false,total_cost_usd:0.1,usage:{input_tokens:10}}'; fi
else
  printf '%s\n' "$answer" > "$out"
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
[[ $("$S" version) == 0.5.0 ]] || fail version
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
[[ $(jq .final "$T/run space/result.json") == null ]] || fail "batch run must not point result.final at a missing judge answer"
[[ $(cat "$T/run space/one.rc") == 0 ]] || fail run
has <("$S" status "$T/run space") 'done rc=0'
has <("$S" status "$T/run space") 'COST=0.1'
has <("$S" status "$T/run space") 'unknown'
[[ $(jq -s length "$T/run space"/a/*/outbox.jsonl) == 4 ]] || fail board
[[ ! -e $T/spoof ]] || fail spoofed-dir
[[ $(jq -r .from "$T/run space/a/two/outbox.jsonl" | sort -u) == two ]] || fail spoofed-author
[[ $(jq .usage.input_tokens "$T/run space/two.usage") == 30 ]] || fail usage
not_has "$T/run space/a/one/argv" --safe-mode
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
[[ $(jq -r .judge.model "$T/all/run.json") == claude-other ]] || fail independent-judge
[[ $(jq -r .kind "$T/all/run.json") == all ]] || fail run-kind
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
  else not_has "$f" "$T/project space/.git"; fi
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
echo $$ > "$TEST_ROOT/terminal-pid"
exec sleep 60 # a real viewer never exits on its own
STUB
chmod +x "$T/terminal"
# The run must finish even though the viewer window stays open.
# Capture through a pipe like agent harnesses do: nothing may keep our stdout/stderr open.
# shellcheck disable=SC2016 # $1/$2 are expanded by the inner bash
DISPLAY=:stub SWARM_TERMINAL="$T/terminal" timeout 30 bash -c '"$1" all -W -r 1 -o "$2" hello 2>&1 | cat > /dev/null' _ "$S" "$T/watch" ||
  fail "run kept the caller's pipe open until the watch window closed"
kill "$(cat "$T/terminal-pid")" 2>/dev/null || true
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
# Malformed outbox lines preserve valid messages.
printf '{broken\n' >> "$T/board/a/alice/outbox.jsonl"
has <("$S" read "$T/board") broadcast
has <("$S" status "$T/run space") 'TOKENS(in/out)=30/5'
# Failed participants are not retried; round-1 evidence and failures reach judge.
[[ ! -e $T/partial/r2/$failed_id.rc ]] || fail retried-failure
has "$T/partial/a/judge/prompt" "$T/partial/r1/$failed_id.md"
has "$T/partial/failures.jsonl" '65'
reject "$S" all -r 2 -m sonnet -S claude-other -o "$T/no-final" NOFINAL
# Models write the closing section as an ordinary Markdown heading, not the literal prompt text.
"$S" all -r 2 -m sonnet -S claude-other -o "$T/md-final" MDHEADING > /dev/null || fail "markdown FINAL ANSWER heading rejected"
reject "$S" all -r 2 -m sonnet -S claude-other -o "$T/inline-final" INLINEFINAL
[[ $(cat "$T/no-final/r2/a1.rc") == 65 ]] || fail missing-final-section
# Discovery is nonfatal and explicit participant + judge bypass it.
touch "$T/discovery-fail"
env -u SWARM_CODEX_MODELS "$S" all -r 1 -m sonnet -S claude-other -o "$T/explicit" hello >/dev/null
env -u SWARM_CODEX_MODELS "$S" all -r 1 -o "$T/discovery" hello >/dev/null
rm "$T/discovery-fail"
reject "$S" all -m unknown -o "$T/unknown" hello
[[ ! -d $T/unknown ]] || fail unknown-created-dir
# Defaults, subdirectory worktrees, and orchestrator identity.
mkdir -p sub
printf keep > sub/keep
git add -- sub/keep
git -c user.name=Test -c user.email=test@example.com commit -qm sub
jq -cn --arg dir "$PWD/sub" '{id:"default",prompt:"COMMIT",engine:"codex",worktree:true,dir:$dir}' > "$T/default.jsonl"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$S" run -o "$T/default" "$T/default.jsonl" >/dev/null
has "$T/default/a/default/prompt" '/sub'
[[ $(jq '.autocommitted | length' "$T/default/manifest.jsonl") == 1 ]] || fail autocommitted-paths
[[ $(git -C "$(jq -r .path "$T/default/worktrees.jsonl")" log -1 --format=%an) == swarm ]] || fail identity
"$S" clean "$T/default" --discard swarm/default/default >/dev/null
for kind in FAIL SWITCH; do
  jq -cn --arg p "COMMIT $kind" '{id:"writer",model:"gpt-test",prompt:$p,worktree:true}' > "$T/edit.jsonl"
  reject "$S" run -o "$T/edit-$kind" "$T/edit.jsonl"
  [[ $(jq -r '.base == .head' "$T/edit-$kind/manifest.jsonl") == true ]] || fail committed-failed-worker
  [[ $(jq -r '.dirty != ""' "$T/edit-$kind/manifest.jsonl") == true ]] || fail lost-edits
done
[[ $(cat "$T/edit-SWITCH/writer.rc") == 71 ]] || fail branch-switch-code
reject "$S" all -w -r 1 -m sonnet -S claude-other -o "$T/bad-winner" BADWINNER
[[ $(jq .winner "$T/bad-winner/result.json") == null ]] || fail invalid-winner
"$S" all -w -r 1 -m sonnet -S claude-other -o "$T/no-winner" NOWINNER >/dev/null
[[ $(jq .winner "$T/no-winner/result.json") == null ]] || fail none-winner
# Prompt exceeds Linux's per-argument limit; only stdin reaches either harness.
jq -cn '{id:"long",model:"gpt-test",prompt:("x" * 150000)}, {id:"long-claude",model:"sonnet",prompt:("x" * 150000)}' > "$T/long.jsonl"
"$S" run -o "$T/long" "$T/long.jsonl" >/dev/null
[[ $(wc -c < "$T/long/long.prompt") -gt 150000 ]] || fail long-prompt
SWARM_RO_ALLOW='Bash(pytest:*)' "$S" all -r 1 -m sonnet -S claude-other -o "$T/ro-allow" hello >/dev/null
has "$T/ro-allow/a/a1/argv" 'Bash(pytest:*)'
"$S" all -d -r 1 -m sonnet -S claude-other -o "$T/detached" SLOW
wait_rc=0
"$S" wait "$T/detached" || wait_rc=$?
[[ $wait_rc == 75 ]] || fail wait-running
"$S" wait "$T/detached" -t 30
[[ $(jq .rc "$T/detached/result.json") == 0 ]] || fail detached-result
[[ -s $T/detached/orchestrator.log ]] || fail detached-log
wait_rc=0
"$S" wait "$T/failed" || wait_rc=$?
[[ $wait_rc != 0 && $wait_rc != 75 ]] || fail wait-failure
# Resume retries only unfinished calls and keeps successful rounds.
touch "$T/fail-judge"
reject "$S" all -r 2 -m sonnet -S claude-other -o "$T/resume" hello
before=$(wc -l < "$T/resume/a/a1/outbox.jsonl")
rm "$T/fail-judge"
"$S" resume "$T/resume" >/dev/null
[[ $(wc -l < "$T/resume/a/a1/outbox.jsonl") == "$before" ]] || fail resume-reran-success
[[ $(jq .rc "$T/resume/result.json") == 0 ]] || fail resume-judge
for changed in task.md anon.map run.json; do
  cp "$T/resume/$changed" "$T/hash-backup"
  if [[ $changed == run.json ]]; then jq '.rounds = 3' "$T/hash-backup" > "$T/resume/$changed"
  else echo changed >> "$T/resume/$changed"; fi
  reject "$S" resume "$T/resume"
  cp "$T/hash-backup" "$T/resume/$changed"
done
# Remove one answer's rc to model interruption; only that worker is replayed.
rm "$T/resume/result.json" "$T/resume/r2/a1.rc"
"$S" resume "$T/resume" >/dev/null
[[ $(wc -l < "$T/resume/a/a1/outbox.jsonl") == $((before+2)) ]] || fail resume-missing-rc
# Reusing a worktree on a changed branch is rejected even for a completed run.
wt=$(jq -r .path "$T/no-winner/worktrees.jsonl")
git -C "$wt" switch -qc resume-switched
reject "$S" resume "$T/no-winner"
# Same recorded branch name with unrelated history is also unsafe.
recorded=$(jq -r .branch "$T/no-winner/worktrees.jsonl")
git -C "$wt" checkout -q --orphan unrelated
git -C "$wt" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm unrelated
git -C "$wt" branch -D "$recorded" >/dev/null
git -C "$wt" branch -m "$recorded"
reject "$S" resume "$T/no-winner"
printf '%s\n' '{"id":"unknown","model":"missing","prompt":"hello"}' > "$T/unknown.jsonl"
reject "$S" run -o "$T/unknown-run" "$T/unknown.jsonl"
[[ ! -d $T/unknown-run ]] || fail unknown-run-created-dir
# Commit hook failure must propagate rc 71 and preserve staged work.
printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
jq -cn '{id:"writer",model:"gpt-test",prompt:"COMMIT",worktree:true}' > "$T/hook.jsonl"
reject "$S" run -o "$T/hook" "$T/hook.jsonl"
rm .git/hooks/pre-commit
[[ $(cat "$T/hook/writer.rc") == 71 ]] || fail commit-failure-code
[[ $(jq -r '.dirty != ""' "$T/hook/manifest.jsonl") == true ]] || fail commit-failure-lost-edits
# Judge receives only the newest manifest snapshots and their diffs.
not_has "$T/commit-rounds/a/judge/prompt" "$T/commit-rounds/r1/a1.diff"
has "$T/commit-rounds/a/judge/prompt" "$T/commit-rounds/r2/a1.diff"
# --- v0.5: model[@effort][*count] specs.
rc_is() { local want=$1 rc=0; shift; "$@" >"$T/rc.log" 2>&1 || rc=$?; [[ $rc == "$want" ]] || fail "rc $rc (want $want): $*"; }
"$S" all -r 1 -m 'sonnet@xhigh gpt-test@high' -S claude-other@low -o "$T/effort" hello >/dev/null
grep -A1 -Fx -- --effort "$T/effort"/a/a*/argv | grep -Fq xhigh || fail claude-effort
has <(cat "$T/effort"/a/a*/argv) model_reasoning_effort=high
[[ $(grep -A1 -Fx -- --effort "$T/effort/a/judge/argv" | tail -n 1) == low ]] || fail judge-effort
has "$T/effort/anon.map" $'\tsonnet\txhigh'
[[ $(jq -r '.judge.effort' "$T/effort/run.json") == low && $(jq -r '[.agents[].effort] | sort | join(",")' "$T/effort/run.json") == high,xhigh ]] || fail effort-run-json
for spec in gpt-test@ultra 'sonnet*0' a@b@c 'sonnet@low sonnet@low' sonnet@huge; do
  rc_is 2 "$S" all -r 1 -m "$spec" -S claude-other -o "$T/badspec" hello
  [[ ! -d $T/badspec ]] || fail "bad spec created a run dir: $spec"
done
has "$T/rc.log" 'invalid effort'
rc_is 2 "$S" all -r 1 -m sonnet -S 'claude-other*2' -o "$T/badspec" hello
"$S" all -r 1 -m 'sonnet@low*3 sonnet@high' -S claude-other -o "$T/count" hello >/dev/null
[[ $(grep -c $'\tsonnet\tlow$' "$T/count/anon.map") == 3 && $(wc -l < "$T/count/anon.map") == 4 ]] || fail spec-count
# --- v0.5: read-only loop. The stub judge replays $T/judge-script, one line per call.
script() { rm -f "$T/judge-n"; printf '%s\n' "$@" > "$T/judge-script"; }
loop() { "$S" loop -m 'sonnet gpt-test' -S claude-other "$@"; }
rc_is 2 "$S" loop -m sonnet hello
rc_is 2 "$S" loop -r 2 -m sonnet -S claude-other hello
rc_is 2 "$S" loop -w -m sonnet -S claude-other hello
rc_is 2 "$S" all -I 3 -m sonnet -S claude-other hello
rc_is 2 "$S" stop "$T/all"
script 'CONTINUE 70 a1 0' 'STOP 90 INCUMBENT 90'
loop -o "$T/loop" hello > "$T/loop.out" 2> "$T/loop.err"
[[ $(wc -l < "$T/loop/loop.jsonl") == 2 && $(jq .ideal "$T/loop/result.json") == true && $(jq -r .kind "$T/loop/run.json") == loop ]] || fail loop-basic
[[ $(jq -c .score_history "$T/loop/result.json") == '[70,90]' && $(jq -r .best "$T/loop/result.json") == it1/a1 ]] || fail loop-result
cmp -s "$T/loop/it1/a1.md" "$T/loop/final.md" || fail loop-final
has "$T/loop.err" 'it1: CONTINUE 70 (+70) best=a1'
has "$T/loop/it2/a1.prompt" "$T/loop/best.md"
has "$T/loop/it2/a1.prompt" 'direction 1'
has "$T/loop/it2/a1.prompt" 'CHANGES:'
not_has "$T/loop/it2/a1.prompt" '  read:'
has "$T/loop/it2/judge.prompt" 'Incumbent (score 70)'
[[ ! -w $T/loop/best.md ]] || fail best-writable
# One invalid decision is retried with the reason; the evidence of the first attempt is kept.
script BAD 'STOP 80 a2 0'
loop -o "$T/loop-retry" hello >/dev/null 2>&1
[[ -f $T/loop-retry/it1/judge.attempt1.md ]] || fail judge-attempt-kept
has "$T/loop-retry/it1/judge.prompt" 'DECISION FORMAT ERROR'
# STOP with defects and text after the fence are both invalid: rc 65, then resume finishes without rerunning executors.
script 'STOP 90 a1 0 DEFECTS' 'STOP 90 a1 0 TRAIL' 'STOP 90 a1 0'
rc_is 65 loop -o "$T/loop-bad" hello
has "$T/rc.log" 'STOP requires no remaining defects'
has "$T/rc.log" 'text after the closing'
[[ $(jq -r .stop_reason "$T/loop-bad/result.json") == judge-failed && ! -f $T/loop-bad/it1/decision.json ]] || fail loop-judge-failed
before=$(cat "$T/loop-bad"/a/a*/outbox.jsonl | wc -l)
"$S" resume "$T/loop-bad" >/dev/null 2>&1
[[ $(cat "$T/loop-bad"/a/a*/outbox.jsonl | wc -l) == "$before" ]] || fail loop-resume-reran
[[ $(jq .rc "$T/loop-bad/result.json") == 0 && $(jq .ideal "$T/loop-bad/result.json") == true ]] || fail loop-resume
# judge DIR re-judges the open iteration only.
script BAD BAD 'PAUSE 40 a1 0'
rc_is 65 loop -o "$T/loop-judge" hello
rc_is 4 "$S" judge "$T/loop-judge"
[[ $(jq -r .stop_reason "$T/loop-judge/result.json") == pause && -s $T/loop-judge/final.md ]] || fail loop-judge-cmd
# Stagnation: K stalls add the block; CONTINUE without strategy_change is rejected.
script 'CONTINUE 70 a1 0' 'CONTINUE 70 INCUMBENT 70' 'CONTINUE 70 INCUMBENT 70' 'CONTINUE 70 INCUMBENT 70' 'CONTINUE 70 INCUMBENT 70' \
  'CONTINUE 75 a1 70 STRAT' 'STOP 80 a2 75'
loop -K 3 -o "$T/loop-stall" hello >/dev/null 2> "$T/loop-stall.err"
has "$T/loop-stall/it5/judge.attempt1.prompt" 'STAGNATION: no gain for 3 iterations'
has "$T/loop-stall.err" 'STAGNATION: CONTINUE requires strategy_change'
not_has "$T/loop-stall/it4/judge.prompt" STAGNATION
has "$T/loop-stall/it6/a1.prompt" 'Required strategy change: strategy 6'
has "$T/loop-stall/it6/a1.prompt" 'Already tried without gain'
# Oscillation: best a1, a2, then a1's identical text again.
script 'CONTINUE 70 a1 0' 'CONTINUE 75 a2 70' 'CONTINUE 80 a1 75' 'STOP 85 INCUMBENT 85'
loop -o "$T/loop-osc" hello >/dev/null 2>&1
has "$T/loop-osc/it4/judge.prompt" 'OSCILLATION: best equals it1.'
not_has "$T/loop-osc/it3/judge.prompt" OSCILLATION
# No hidden cap: twelve iterations run when the judge keeps improving.
mapfile -t lines < <(for i in {1..11}; do echo "CONTINUE $((i*5)) a1 $(((i-1)*5))"; done; echo 'STOP 90 INCUMBENT 90')
script "${lines[@]}"
loop -m sonnet -o "$T/loop-long" hello >/dev/null 2>&1
[[ $(wc -l < "$T/loop-long/loop.jsonl") == 12 ]] || fail loop-hidden-cap
# -I, -B and PAUSE end resumably with rc 4 (never 75).
script 'CONTINUE 70 a1 0' 'CONTINUE 75 a1 70' 'CONTINUE 80 a1 75'
rc_is 4 loop -I 2 -o "$T/loop-maxit" hello
[[ $(jq -r .stop_reason "$T/loop-maxit/result.json") == max-iter && $(jq .ideal "$T/loop-maxit/result.json") == false ]] || fail loop-max-iter
script 'CONTINUE 70 a1 0' 'CONTINUE 75 a1 70'
rc_is 4 loop -B 5 -o "$T/loop-budget" hello
[[ $(jq -r .stop_reason "$T/loop-budget/result.json") == max-sessions && $(wc -l < "$T/loop-budget/loop.jsonl") == 1 ]] || fail loop-max-sessions
script 'PAUSE 40 a1 0'
rc_is 4 loop -o "$T/loop-pause" hello
# stop DIR during a slow iteration lets it finish, then stops.
script 'CONTINUE 70 a1 0' 'CONTINUE 75 a1 70'
loop -o "$T/loop-stop" SLOW >/dev/null 2>&1 &
stop_pid=$!
for ((i=0; i<300; i++)); do [[ ! -d $T/loop-stop/it1 ]] || break; sleep 0.01; done
"$S" stop "$T/loop-stop" 2>/dev/null
stop_rc=0; wait "$stop_pid" || stop_rc=$?
[[ $stop_rc == 4 && $(jq -r .stop_reason "$T/loop-stop/result.json") == stop && $(wc -l < "$T/loop-stop/loop.jsonl") == 1 ]] || fail "loop-stop rc=$stop_rc"
# SIGINT reaches loop executors' descendants.
rm -f "$T/descendant"
interrupt_rc=0
timeout --preserve-status -s INT -k 5 1 "$S" loop -m sonnet -S claude-other -o "$T/loop-int" TREE > "$T/loop-int.log" 2>&1 || interrupt_rc=$?
[[ $interrupt_rc == 130 ]] || fail "loop interrupt exit=$interrupt_rc"
child=$(cat "$T/descendant")
[[ ! -d /proc/$child || $(ps -o stat= -p "$child") == Z* ]] || fail loop-interrupt-orphan
[[ $(cat "$T/loop-int/it1/a1.rc") == 130 && $(jq -r .stop_reason "$T/loop-int/result.json") == interrupted ]] || fail loop-interrupt-state
# --- v0.5 P1: preview, confirmation gate and mass quorum.
rc_is 2 "$S" all -r 1 -m 'sonnet@low*21' -S claude-other -o "$T/big" hello
[[ ! -d $T/big ]] || fail confirm-created-dir
has "$T/rc.log" 'rerun with -y'
has "$T/rc.log" 'quorum 13'
grep -Eq 'sonnet@low +claude +21' "$T/rc.log" || fail preview-table
"$S" mass -m 'sonnet*13' -S claude-other -o "$T/mass" hello 2> "$T/mass.err" >/dev/null
[[ $(jq .quorum "$T/mass/run.json") == 8 && $(jq .rounds "$T/mass/run.json") == 1 && ! -d $T/mass/r2 ]] || fail mass-alias
has "$T/mass.err" '13 agents × 1 rounds + judge = 14 sessions; quorum 8'
# 100 agents never exceed -j.
mkdir "$T/conc"
"$S" all -y -r 1 -j 3 -m 'sonnet*100' -S claude-other -o "$T/hundred" CONC >/dev/null 2>&1
rm -rf "$T/conc"
[[ $(sort -n "$T/conc.max" | tail -n 1) -le 3 && $(wc -l < "$T/conc.max") -ge 100 ]] || fail "concurrency peak $(sort -n "$T/conc.max" | tail -n 1)"
[[ $(cat "$T/hundred"/r1/*.rc | sort -u) == 0 ]] || fail hundred-agents
# Rate limits: transient errors are retried by the orchestrator and attempts are kept.
mkdir "$T/noshuf"; printf '#!/bin/sh\nexec cat\n' > "$T/noshuf/shuf"; chmod +x "$T/noshuf/shuf"
rm -f "$T/rate-hit"
SWARM_BACKOFF_BASE=0 "$S" all -r 1 -m 'gpt-test sonnet' -S claude-other -o "$T/rate" RATE429 >/dev/null 2>&1
codex_id=$(awk '$2 == "gpt-test" {print $1}' "$T/rate/anon.map")
[[ $(cat "$T/rate/r1/$codex_id.attempt1.rc") == 76 && $(cat "$T/rate/r1/$codex_id.rc") == 0 ]] || fail rate-retry
has "$T/rate/failures.jsonl" '"event":"retry"'
[[ ! -f $T/rate/PARTIAL ]] || fail retry-marked-partial
# While Codex cools down, Claude jobs keep launching.
rm -f "$T/rate-hit" "$T/launches"
PATH="$T/noshuf:$PATH" SWARM_BACKOFF_BASE=1 "$S" all -r 1 -j 1 -m 'gpt-test*2 sonnet*2' -S claude-other -o "$T/cool" 'RATE429 LAUNCHLOG' >/dev/null 2>&1
[[ $(grep -n '^claude a3' "$T/launches" | cut -d: -f1) -lt $(grep -n '^codex a2' "$T/launches" | cut -d: -f1) ]] || fail "claude waited for codex cooldown: $(tr '\n' ' ' < "$T/launches")"
[[ $(grep -c '^codex a1' "$T/launches") == 2 ]] || fail cooldown-retry
# Exhausted quota (real Codex --json log): rc 77, engine dead, queued agents skipped, quorum honoured.
PATH="$T/noshuf:$PATH" "$S" all -r 1 -j 1 -q 1 -m 'gpt-test*2 sonnet' -S claude-other -o "$T/exhaust" EXHAUST >/dev/null 2>&1
[[ $(cat "$T/exhaust/r1/a1.rc") == 77 && $(cat "$T/exhaust/r1/a2.rc") == 77 && $(cat "$T/exhaust/r1/a3.rc") == 0 ]] || fail exhausted-codes
[[ ! -e $T/exhaust/a/a2/argv && -s $T/exhaust/.backoff/codex.dead ]] || fail exhausted-skip
has "$T/exhaust/failures.jsonl" '"event":"skip"'
[[ $(jq .partial "$T/exhaust/result.json") == true && $(jq .rc "$T/exhaust/result.json") == 0 ]] || fail exhausted-partial
# Only error events count: the same log without them (its tool output mentions 429) stays rc 1.
reject "$S" all -r 1 -m gpt-test -S claude-other -o "$T/rlitem" RLITEM
[[ $(cat "$T/rlitem/r1/a1.rc") == 1 ]] || fail rate-from-tool-output
# A successful answer that talks about rate limits is not classified.
"$S" all -r 1 -m 'sonnet gpt-test' -S claude-other -o "$T/rltext" RLTEXT >/dev/null 2>&1
[[ $(cat "$T/rltext/r1"/*.rc | sort -u) == 0 ]] || fail rate-from-answer
# Overridable pattern; after three requeues the failure stands.
reject env SWARM_BACKOFF_BASE=0 SWARM_RATELIMIT_RE=custom-throttle "$S" all -r 1 -m sonnet -S claude-other -o "$T/customrl" CUSTOMRL
[[ $(cat "$T/customrl/r1/a1.rc") == 76 && -f $T/customrl/r1/a1.attempt3.rc && ! -f $T/customrl/r1/a1.attempt4.rc ]] || fail custom-ratelimit
# -M: the judge may write merged text, but never STOP in that iteration; off by default.
script 'CONTINUE 80 MERGED 0 MERGE' 'STOP 90 INCUMBENT 90'
loop -M -o "$T/loop-merge" hello >/dev/null 2>&1
[[ $(cat "$T/loop-merge/final.md") == 'merged text' && -s $T/loop-merge/it1/merged.md ]] || fail loop-merge
script 'CONTINUE 80 MERGED 0 MERGE' 'CONTINUE 80 MERGED 0 MERGE'
rc_is 65 loop -o "$T/loop-nomerge" hello
has "$T/rc.log" 'MERGED is not enabled'
script 'STOP 90 MERGED 0 MERGE' 'STOP 90 MERGED 0 MERGE'
rc_is 65 loop -M -o "$T/loop-stopmerge" hello
has "$T/rc.log" 'no STOP in the iteration that picks MERGED'
rc_is 2 loop -M -w -o "$T/loop-mw" hello
# rw loop: iteration 2 branches from the iteration-1 winner; losers' worktrees go, branches stay.
script 'CONTINUE 70 a1 0' 'STOP 90 a2 70'
"$S" loop -w -m 'gpt-test*2' -S claude-other -o "$T/loop-rw" COMMIT > "$T/loop-rw.out" 2>/dev/null
[[ $(jq -r 'select(.branch == "swarm/loop-rw/i2/a1") | .base' "$T/loop-rw/worktrees.jsonl") == $(git rev-parse swarm/loop-rw/i1/a1) ]] || fail rw-loop-base
[[ ! -d $(jq -r 'select(.branch == "swarm/loop-rw/i1/a2") | .path' "$T/loop-rw/worktrees.jsonl") ]] || fail rw-loser-worktree
git show-ref --verify --quiet refs/heads/swarm/loop-rw/i1/a2 || fail rw-loser-branch
[[ $(jq -r .winner "$T/loop-rw/result.json") == swarm/loop-rw/i2/a2 ]] || fail rw-loop-winner
has "$T/loop-rw.out" 'git merge -- swarm/loop-rw/i2/a2'
has "$T/loop-rw/it1/judge.prompt" "$T/loop-rw/it1/a1.diff"
git -c user.name=Test -c user.email=test@example.com merge -q --ff-only swarm/loop-rw/i2/a2
"$S" clean "$T/loop-rw" >/dev/null
[[ -z $(git branch --list 'swarm/loop-rw/*') ]] || fail rw-loop-clean
# A dirty winner is never accepted.
script 'CONTINUE 70 a1 0' 'CONTINUE 70 a1 0'
rc_is 65 "$S" loop -w -m sonnet -S claude-other -o "$T/loop-dirty" DIRTYWIN
has "$T/rc.log" 'dirty or switched worktree'
printf 'All tests passed.\n'
