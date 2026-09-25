---
name: swarm
description: Run cooperating agents across Claude Code and Codex with a shared board, critique rounds and a final judge. Use for independent subtasks, hard bugs, reviews, research or an explicit request for a swarm/all models. Skip trivial single-step work.
---

# Swarm

Use this directory's `swarm.sh`. Engine selection: `claude-*` uses `claude -p`;
other models use `codex exec`. Requires Bash 4.3+, jq, coreutils (`timeout`,
`realpath`), `flock`, and Git for worktrees. Harnesses must already be authenticated.

Choose native harness subagents for independent tasks within one harness.
Use `all` for competing answers and cross-critique; use `run` for separate tasks
with explicit owners. Never start another swarm or subagent when already a worker.

```bash
S=~/.agents/skills/swarm/swarm.sh
"$S" roster
"$S" all "Review the design; cite evidence and uncertainties"
"$S" all -r 2 -m "claude-opus-5-5 gpt-6-astra" -S claude-opus-5-5 "task"
"$S" all -w "Implement the specified change; run checks and commit"
"$S" run -j 6 tasks.jsonl
"$S" post .swarm/RUN api "Interface is ready" tests
"$S" read .swarm/RUN tests
"$S" status .swarm/RUN
"$S" clean .swarm/RUN
"$S" version
"$S" --help
```

Task file: one object per line, unique filename-safe `id`, required `model` and
`prompt`. `dir` defaults to the launch directory; `mode` defaults to `ro`.

```json
{"id":"api","model":"claude-opus-5-5","prompt":"Implement API; own src/api only; test and commit","mode":"rw","worktree":true,"dir":"/path/to/repo"}
{"id":"review","model":"gpt-6-astra","prompt":"Review current code; cite file locations","mode":"ro"}
```

Options: `-j` concurrent agents (6), `-t` per-agent timeout seconds (1800),
`-o` new output directory (default `.swarm/<timestamp>-<pid>`), `-w` writable
worktree per agent. `all` additionally uses `-r` total answer rounds (2),
`-m` space-separated model names and `-S` judge (first selected model by default).
Round 1 answers the task; later rounds read previous answers and the board.
The judge runs after successful rounds. A failed agent makes the command fail;
inspect its `.log` and `.rc`. Existing output directories are never overwritten.

Environment: `SWARM_CLAUDE_BIN` / `SWARM_CODEX_BIN` override executable names or
paths; `SWARM_CLAUDE_MODELS` / `SWARM_CODEX_MODELS` override whitespace-separated
rosters. Claude defaults to `claude-fable-5-1 claude-opus-5-5 claude-sonnet-5
claude-haiku-4-5`; Codex discovers `visibility=list` models with `codex debug models`.
Only installed harnesses appear. `SWARM_DEPTH` prevents recursive worker launches.

Outputs: `all` writes `r<N>/<model>.md`, `final.md`, matching `.log` / `.rc` files;
`run` writes `<id>.md` and matching sidecars. Both use locked `board.jsonl` messages.
`status` reports running/done, exit codes and message count.

Default permissions: Claude uses `dontAsk` with Read/Grep/Glob/WebSearch/WebFetch
and board command permissions; Codex uses `workspace-write` rooted at the run
folder, with the project available to read. Writable Claude workers use
`--dangerously-skip-permissions`; writable Codex workers use their working
directory plus the run directory. `worktree:true` implies `rw`; `mode:rw` without
worktree writes directly to `dir`. Give workers only the permissions they need.

Worktrees start at the specified repository's current HEAD, under
`<repo>/.swarm/wt/<run>-<id>`, on `swarm/<run>/<id>`. Writable runs print branches
for review and merge. Verify and merge their commits yourself. `clean` uses the
run's `worktrees.jsonl`, refuses dirty worktrees or branches not merged into the
recorded repository's current HEAD, and preserves reports. Never force cleanup
of unfinished work.

Prompts must state goals, constraints, file ownership and the expected deliverable.
Narrow the roster for cheap checks; multiple agents and rounds multiply cost.
Read the board and `final.md`, verify important claims and run relevant checks
before reporting success: a judge's answer is not proof.
