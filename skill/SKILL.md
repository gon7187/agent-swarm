---
name: swarm
description: Agent swarm across every active harness (Claude Code + Codex) — parallel workers on all models, a shared message board so agents talk to each other, rounds of cross-critique, and a final judge. DEFAULT for any task with 2+ independent parts, anything worth a second opinion (architecture, hard bugs, reviews, research, estimates), or when the user says swarm / рой / "все модели" / "спроси всех". Skip for trivial single-step edits.
---

# Swarm

Tool: `~/.agents/skills/swarm/swarm.sh` (bash + jq; engines `claude -p` and `codex exec`).
Engine is picked from the model name: `claude-*` → Claude Code, everything else → Codex.

## Pick the shape

| Situation | Do |
|---|---|
| Task splits into independent parts, one harness is enough | Your harness's **native** subagents (Claude Code `Agent`, Codex `spawn_agent`), in parallel, one message |
| Same question needs several brains (design, hard bug, review, estimate, research) | `swarm.sh all` — every model answers, reads the others, argues on the board, judge synthesizes |
| Different parts, want specific models per part and shared chat | `swarm.sh run tasks.jsonl` |
| Trivial / single-step | No swarm. Multi-agent costs ~15× tokens |

## Commands

```bash
S=~/.agents/skills/swarm/swarm.sh
$S roster                                   # every model of every active harness
$S all "task"                               # all models, 2 rounds, judge = first roster model
$S all -r 3 -m "claude-opus-5-5 gpt-6-astra gpt-5.5" -S claude-fable-5-1 "task"
$S all -w "implement X"                     # rw: each agent in its own git worktree/branch
$S run -j 8 tasks.jsonl                     # {"id","model","prompt","mode":"ro|rw","worktree":true}
$S read <run-dir>                           # the board: who said what to whom
```

Opts: `-j` parallel jobs (6), `-t` timeout per agent in s (1800), `-o` run dir (`.swarm/<ts>`),
`-r` rounds, `-m` model subset, `-S` judge model, `-w` read-write + worktrees.

Output: `<run>/r<N>/<model>.md` per round, `<run>/final.md` (judge), `<run>/board.jsonl`, `*.log`, `*.rc`.
Run from the project dir — workers get it as their project. Long runs: launch in background.

## Rules

- Prompts must be self-contained: goal, constraints, output format, file ownership. Vague prompts → duplicate work.
- Default is read-only. Use `-w` / `"worktree":true` for code edits so agents don't trample each other; merge branches `swarm/<run>/<id>` yourself afterwards.
- Full roster = 11 agents × rounds. For cheap checks narrow with `-m`.
- Read `final.md` critically and verify claims before reporting — the judge can be wrong too.
- If you are a swarm worker (your prompt says so), never start a swarm; `SWARM_DEPTH` blocks nesting anyway.
