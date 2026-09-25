#!/usr/bin/env bash
set -euo pipefail
S=$(realpath "$(dirname "$0")/../skill/swarm.sh")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export SWARM_DEPTH=0
export SWARM_CLAUDE_BIN="$T/claude" SWARM_CODEX_BIN="$T/codex"
export SWARM_CLAUDE_MODELS='claude-test' SWARM_CODEX_MODELS='gpt-test'
cat > "$T/claude" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
prompt=$2
read_cmd=$(sed -n 's/^  read:  //p' <<< "$prompt")
post_cmd=$(sed -n 's/^  post:  //p' <<< "$prompt")
eval "$read_cmd" >/dev/null
eval "${post_cmd% \[target_agent_id\]}" >/dev/null
[[ $prompt != *SLOW* ]] || sleep 3
printf 'Claude answer\n'
[[ $prompt != *FAIL* ]] || exit 7
STUB
cat > "$T/codex" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == debug ]]; then
  echo '[{"slug":"gpt-test","visibility":"list"},{"slug":"hidden","visibility":"hide"}]'
  exit
fi
out=''
while (($#)); do
  case $1 in
    -o) out=$2; shift 2 ;;
    *) prompt=$1; shift ;;
  esac
done
read_cmd=$(sed -n 's/^  read:  //p' <<< "$prompt")
post_cmd=$(sed -n 's/^  post:  //p' <<< "$prompt")
eval "$read_cmd" >/dev/null
eval "${post_cmd% \[target_agent_id\]}" >/dev/null
printf 'Codex answer\n' > "$out"
[[ $prompt != *FAIL* ]] || exit 7
STUB
chmod +x "$T/claude" "$T/codex"
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() { if "$@" >"$T/reject.log" 2>&1; then fail "accepted: $*"; fi; }
[[ $("$S" version) == 0.2.0 ]] || fail version
[[ $("$S" --help) == *status* ]] || fail help
[[ $("$S" roster | wc -l) == 2 ]] || fail roster
[[ $(env -u SWARM_CODEX_MODELS "$S" roster | tail -1) == gpt-test ]] || fail discovery
mkdir -p "$T/project space"
cd "$T/project space"
git init -q
git -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
"$S" post "$T/board" alice broadcast
"$S" post "$T/board" bob private carol
[[ $("$S" read "$T/board" alice) != *private* ]] || fail filtering
[[ $("$S" read "$T/board" carol) == *private* ]] || fail recipient
for i in {1..10}; do "$S" post "$T/board" "$i" parallel & done
wait
[[ $(jq -s length "$T/board/board.jsonl") == 12 ]] || fail locking
printf '%s\n' '{"id":"one","model":"claude-test","prompt":"hello"}' '{"id":"two","model":"gpt-test","prompt":"hello"}' > "$T/tasks.jsonl"
"$S" run -j 2 -o "$T/run space" "$T/tasks.jsonl"
[[ $(cat "$T/run space/one.rc") == 0 ]] || fail run
[[ $("$S" status "$T/run space") == *"done rc=0"* ]] || fail status
[[ $(jq -s length "$T/run space/board.jsonl") == 2 ]] || fail board
"$S" all -r 2 -S gpt-test -o "$T/all" hello
[[ -s "$T/all/r2/claude-test.md" && -s "$T/all/final.md" ]] || fail all
[[ $(jq -s length "$T/all/board.jsonl") == 5 ]] || fail rounds
reject "$S" all -o "$T/all" again
reject env SWARM_DEPTH=1 "$S" all hello
reject "$S" all -j 0 hello
reject "$S" all -r nope hello
reject "$S" all -t
reject "$S" all -m '../escape' hello
printf '%s\n' '{"id":"../escape","model":"gpt-test","prompt":"hello"}' > "$T/bad.jsonl"
reject "$S" run "$T/bad.jsonl"
printf '%s\n' '{"id":"dup","model":"gpt-test","prompt":"hello"}' '{"id":"dup","model":"gpt-test","prompt":"hello"}' > "$T/bad.jsonl"
reject "$S" run "$T/bad.jsonl"
printf '{broken\n' > "$T/bad.jsonl"
reject "$S" run "$T/bad.jsonl"
reject "$S" all -o "$T/failed" FAIL
[[ $(cat "$T/failed/r1/gpt-test.rc") == 7 ]] || fail exit-code
"$S" all -w -r 1 -o "$T/work" hello > "$T/work-summary"
grep -q 'swarm/work/gpt-test' "$T/work-summary"
[[ $(git worktree list --porcelain | grep -c '^worktree ') == 3 ]] || fail worktrees
"$S" clean "$T/work"
[[ $(git worktree list --porcelain | grep -c '^worktree ') == 1 ]] || fail clean
[[ -z $(git branch --list 'swarm/work/*') ]] || fail branches
"$S" clean "$T/work"
printf '%s\n' '{"id":"writer","model":"gpt-test","prompt":"hello","mode":"rw","worktree":true}' > "$T/tasks.jsonl"
"$S" run -o "$T/task-work" "$T/tasks.jsonl"
wt=$(jq -r .path "$T/task-work/worktrees.jsonl")
echo preserve > "$wt/dirty"
reject "$S" clean "$T/task-work"
[[ -f $wt/dirty ]] || fail dirty-preservation
rm "$wt/dirty"
git -C "$wt" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm unmerged
reject "$S" clean "$T/task-work"
[[ -d $wt ]] || fail unmerged-preservation
git -c user.name=Test -c user.email=test@example.com merge --ff-only swarm/task-work/writer >/dev/null
"$S" clean "$T/task-work"
"$S" all -m claude-test -t 1 -o "$T/timeout" SLOW > "$T/timeout.log" 2>&1 &
timeout_pid=$!
for ((i=0; i<100; i++)); do
  [[ ! -f $T/timeout/r1/claude-test.rc ]] || break
  sleep 0.01
done
[[ $("$S" status "$T/timeout") == *running* ]] || fail running
if wait "$timeout_pid"; then fail timeout; fi
[[ $(cat "$T/timeout/r1/claude-test.rc") == 124 ]] || fail timeout-code
echo 'All tests passed.' 
