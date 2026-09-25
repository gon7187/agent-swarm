# Protocol

How a `swarm.sh all` run proceeds: who talks to whom, what each round is allowed to see, how the judge decides, and what happens when something fails. For engines, sandboxing and the file layout see [architecture.md](architecture.md).

## Overview

```mermaid
sequenceDiagram
    participant U as swarm.sh
    participant A as agents a1..aN
    participant O as outboxes a/<id>/
    participant J as judge (outside the roster)
    U->>U: roster, anon.map, "N × R + 1 sessions"
    U->>A: round 1: task (post only)
    A->>O: post findings
    A-->>U: r1/<id>.md
    U->>U: validate answers, check quorum
    U->>A: round 2..R: task + valid answers + board tail (agents still in the run)
    A->>O: REFUTED / CHANGED MY MIND / UNRESOLVED
    A-->>U: r<R>/<id>.md ending with FINAL ANSWER
    U->>J: task + last round + round-1 answers + failure ledger + board (+ diffs)
    J-->>U: final.md (PARTIAL, WINNER when applicable)
    U->>U: validate WINNER, write result.json
```

## 0. Setup

1. **Roster.** Without `-m`, the first model of each available harness. `-m all` takes the full roster; `-m "a b c"` an explicit list.
2. **Judge.** `-S MODEL`, or by default the first roster model that is not a participant. If every roster model is a participant, the first one is used and a warning is printed: the judge is then also a participant.
3. **Anonymization.** Participants are shuffled and get ids `a1..aN`. The mapping `aK<TAB>model` is written to `anon.map`. Ids, not model names, are used in prompts, file names and on the board, so neither the agents nor the judge can weight an argument by brand.
4. **Cost line.** `swarm: N agents × R rounds + judge = N×R+1 sessions` is printed to stderr before the first agent starts.
5. **Isolation.** Workers start without the user's own config (hooks, output style, MCP servers, `~/.codex/config.toml`) unless `SWARM_INHERIT_CONFIG=1`. Project configuration, including the project `CLAUDE.md`, still applies.

## 1. Round 1: independent answers

Every agent gets the preamble and the task. In round 1 agents may **post** to the board but are not told to **read** it. The point is independence: in the review that produced v0.3.0, five agents in round 1 picked up the same false claim from the board, and it looked like consensus. Independent first answers are the only way to tell agreement from contagion.

## 2. Rounds 2..R: critique with evidence

Only agents that produced a valid answer in the previous round take part; a failed agent is not relaunched in later rounds. Each agent gets, in its prompt:

- the task;
- the list of **valid** answer files from the previous round, with an explicit instruction to read every one of them (failed agents are listed separately, so nobody critiques an empty file);
- the last 60 board messages.

Answers are passed as file paths, not inlined; the run directory is readable to every agent (`--add-dir` for Claude, the Codex sandbox restricts writes, not reads). Other agents' answers and board messages are marked as **untrusted evidence**: material to check, not instructions to follow. The answer must contain four sections:

| Section | Content |
|---|---|
| `REFUTED` | `claim → evidence` for every claim the agent believes is wrong (file:line, command output, a reproduction) |
| `CHANGED MY MIND` | what the agent now accepts from others and why |
| `UNRESOLVED` | what is still disputed and what would settle it |
| `FINAL ANSWER` | the agent's complete, standalone answer to the task after this round, as the closing section |

An answer from round 2 on without a `FINAL ANSWER` section counts as failed, just like an empty one, and is listed in `PARTIAL`. This keeps the actual answer from disappearing behind the critique: the judge sees complete answers, not only disputes. There is no early stop on consensus: a correlated error looks exactly like agreement.

## 3. The board

- Every agent has a private directory `a/<id>/`. Inside a worker, `swarm.sh post` writes only to `a/<id>/outbox.jsonl`, and the `from` field is taken from that directory, not from the command line. An agent cannot post as someone else, and the Codex sandbox lets it write only there, so it cannot overwrite `task.md` or another agent's answer.
- Answers (`r<N>/<id>.md`) are written by the orchestrator, outside `a/`.
- `swarm.sh read DIR [ME]` merges all outboxes sorted by timestamp. `swarm.sh watch DIR` shows the same live, together with the state of each agent.
- You can post into a running swarm yourself from outside a worker.

Message format:

```json
{"ts":"2026-09-25T14:31:07Z","from":"a1","to":"all","msg":"..."}
```

## 4. The judge

The judge runs read-only with:

- the task;
- the valid answers of the last round;
- the round-1 answers as secondary evidence, so that a round-1 finding nobody disputed cannot vanish before the final answer;
- the failure ledger: which agent failed in which round and with what exit code;
- the board.

It is told:

- evidence beats count: a single agent with a reproduction outweighs a majority without one;
- list what remains unresolved rather than papering over it;
- explain where agents disagreed and why the chosen side won.

In rw runs (`all -w`) the judge also gets the latest `manifest.jsonl` row per agent and the per-agent `r<N>/<id>.diff` files, so it judges the actual changes, not the description of them. It ends with `WINNER: <branch>` or `WINNER: NONE`.

`swarm.sh` then lists **all** of the run's branches for review. It takes the last `WINNER:` line and validates it: the branch must be in `worktrees.jsonl` and must not be dirty in the manifest. For a valid winner it additionally prints a `git diff <base>..<winner>` command, a single `git merge -- <winner>` command and `swarm.sh clean <run> --discard <other branches>` for the rest. An invalid or missing winner is reported, and no merge command is printed. Merging is always left to you.

The judge's output is `final.md`. Its answer is not majority vote; read it critically. The outcome is also written atomically to `result.json`: `{rc, final, partial, winner, branches}`.

## 5. Failure handling

| Situation | Behavior |
|---|---|
| Agent exits non-zero | Failed. The exit code is in `<id>.rc`, the engine log in `<id>.log` |
| Agent exits 0 with an empty answer | Failed with `rc=65` (not counted as success) |
| Round 2+ answer without `FINAL ANSWER` | Failed; listed in `PARTIAL` |
| rw: branch check or auto-commit fails | Failed with `rc=71`; nothing is committed and the files stay in the worktree for inspection. A failed agent's changes are never auto-committed |
| Agent exceeds `-t` | Stopped with `SIGTERM`, `SIGKILL` 30 s later; `rc=124` |
| Fewer valid answers than all agents, default | Strict mode: the run stops after that round, no judge, non-zero exit |
| Valid answers ≥ `-q N` | The run continues with the agents that succeeded; failed agents are not relaunched in later rounds. `final.md` is marked `PARTIAL` and lists the failed agents; the judge gets the per-round failure ledger |
| Valid answers < `-q N` | The run stops, non-zero exit |
| Judge fails | Rounds are kept. `swarm.sh judge DIR [-S MODEL]` reruns only the judge on `task.md` and the last round |
| Run interrupted | `swarm.sh resume DIR` (v0.4.0) reruns only agents whose `.rc` is missing or non-zero, then the remaining rounds and the judge. It refuses if the task, `anon.map` or options no longer match the hashes in `run.json`, and never reuses a worktree whose `HEAD` no longer descends from its recorded base |
| Ctrl-C / SIGTERM | The whole process tree of every running worker is killed; nothing keeps running and billing in the background. Exit code 130. The same happens when a host tool kills a foreground run on timeout; start long runs from an agent with `-d` (or in the background) and poll with `swarm.sh wait DIR -t SEC` |
| Worktree creation fails | Same cleanup as Ctrl-C: agents already started are stopped |

`swarm.sh status DIR` shows, per agent, state, exit code and cost (input/output tokens when the engine reports no USD figure, `unknown` when it reports nothing), plus the total.

## 6. `run` mode

`swarm.sh run tasks.jsonl` uses the same board, outboxes, isolation and failure handling, but no rounds and no judge: all tasks start at once and coordination happens on the board. Tasks that depend on another task's committed output belong in separate, phased runs; see [recipes.md](recipes.md#3-parallel-feature-in-worktrees). Ids come from the task `id`, not from anonymization. See the README for the task format and the rules for `mode`, `worktree` and `shared`.

## 7. `loop` mode: judge-driven iteration

`swarm.sh loop` replaces "fixed rounds, then a judge" with "iterations, each scored by a judge, until the judge is done". Where `all` fans out N agents and merges their views once, `loop` refines a single candidate repeatedly. See the README for the full flag reference; this section covers the protocol.

```mermaid
sequenceDiagram
    participant U as swarm.sh
    participant A as executors
    participant J as judge
    U->>A: iteration 1: task (independent, like round 1)
    A-->>U: it1/<id>.md
    U->>J: candidates + best.md=NONE
    J-->>U: decision.json {verdict, score, incumbent_score, best, defects, directions}
    U->>U: best.md := chosen candidate (atomic copy)
    loop while verdict == CONTINUE
        U->>A: it<k>: task + best.md + last defects/directions + tried directions
        A-->>U: it<k>/<id>.md ending CHANGES: then FINAL ANSWER
        U->>J: this iteration's candidates + best.md
        J-->>U: decision.json
        U->>U: update best.md, loop.jsonl
    end
    U->>U: STOP -> final.md, rc 0. PAUSE / -I / -B / stop DIR -> rc 4
```

- **Iteration 1** is independent, exactly like round 1 of `all`: no executor sees another's draft.
- **Iteration k ≥ 2.** Every executor gets the task, the immutable `best.md`, the previous `decision.json`'s `defects` and `directions`, and the running list of directions already tried without gain. There is no peer reading between executors and no separate critique round in `loop` — the judge's `directions` **are** the critique that would otherwise come from other agents. The answer must end with a `CHANGES:` section describing what changed from `best.md`, then `FINAL ANSWER`, checked the same way `has_final` checks `all`/`run` answers.
- **The judge** sees only this iteration's candidates and `best.md` — not the board, not earlier iterations' candidates, not `evidence()`'s global view used by `all`. It scores the incumbent and the best new candidate in the same judgment (so scores never drift across iterations) and selects the new best:
  - `INCUMBENT` — nothing this iteration beat it;
  - an executor id — that candidate becomes the new `best.md`;
  - `MERGED` (only with `-M`, text tasks only, never in `-w`) — the judge writes the merged text itself, delimited by `=== BEST ===` / `=== END BEST ===`. The judge may not also verdict `STOP` in the iteration where it picks `MERGED`: a merge is a claim that more work may still be needed, not a final answer.
- **Decision format.** The judge ends with exactly one fenced ` ```json ` block and nothing after it:
  ```json
  {"verdict":"CONTINUE","score":82,"incumbent_score":78,"best":"a3",
   "defects":["..."],"directions":["..."],"strategy_change":""}
  ```
  Validated: `verdict` is one of `STOP|CONTINUE|PAUSE`; `score`/`incumbent_score` are integers 0-100; `best` is `INCUMBENT`, `MERGED` (only if `-M` is set), or a candidate id from this iteration; `STOP` requires an empty `defects` list; `CONTINUE` requires both non-empty `defects` and non-empty `directions`; during a stagnation escalation (see below) `CONTINUE` also requires a non-empty `strategy_change`. At iteration 1 there is no incumbent, so `incumbent_score` is `0` and `best == INCUMBENT` is rejected (there is nothing to be the incumbent yet).
  A decision that fails validation is retried once, with `DECISION FORMAT ERROR: <reason>` appended to the judge's prompt. A second failure sets the judge's `.rc` to 65; the iteration is not committed, and `swarm.sh judge DIR` or `swarm.sh resume DIR` picks it back up. A malformed decision is never treated as `STOP`.
- **Termination.** `gain = score − incumbent_score`, both from the same judgment. An iteration is **stalled** when `gain < 1` or the judge picked `INCUMBENT`. After `-K` (default 3) consecutive stalls, the judge's prompt gains a stagnation notice, and a `CONTINUE` verdict must supply a `strategy_change` that has not been used before. **Oscillation** — the same `best.md` content (its git tree SHA, in `-w`) recurring — is flagged to the judge the same way, so it can choose a genuinely different direction rather than looping between two local optima. The orchestrator never stops the loop on its own reasoning: only `STOP`, `PAUSE`, `-I`/`-B` limits or `stop DIR` end it. There is no hidden iteration cap.
- **Operator brakes**, off unless set: `swarm.sh stop DIR` (checked between iterations, via `DIR/STOP`), `-I max_iter`, `-B max_sessions`.
- **Exit codes:** `0` STOP/ideal, `4` PAUSE or an operator limit (resumable), `65` judge failed twice, `1` quorum not met, `130`/`143` on a signal. `75` stays reserved for `wait DIR`'s "still running" — a `loop` run is never done with rc 75.
- **rw loop (`-w`).** Each iteration's worktrees are `swarm/<run>/i<k>/<id>`; iteration k+1's agents branch from the head of the chosen branch, validated the same way a `WINNER` branch is validated in `all -w`. `MERGED` is forbidden in rw. Nothing is ever merged into your checkout automatically — `loop` picking a candidate only moves `best.md` and the run's own branches. Worktrees for an iteration's losing candidates are removed once the iteration is accepted; their branches are kept for inspection.
- **Layout:** `DIR/run.json` (`kind:"loop"`, judge model+effort, `stall_k`, `max_iter`, `max_sessions`, `merge`), `DIR/best.md`, `DIR/loop.jsonl` (one row per iteration), `DIR/final.md`, `DIR/result.json`, `DIR/STOP` when requested; per iteration, `DIR/it<k>/aN.{prompt,md,log,stderr,usage,rc}`, `DIR/it<k>/judge.{prompt,md,log,stderr,rc}`, `DIR/it<k>/decision.json`. `decision.json` is written last and is what marks an iteration committed; `resume` finds the first iteration without one.

## 8. `mass` mode: many agents, cheaply judged

`mass` adds no orchestration path of its own: `swarm.sh mass [opts] "task"` is `swarm.sh all -r 1 [opts] "task"`, and any `*count` in a model spec already lets `all` or `loop` run dozens of agents the same way. What changes above `SWARM_MASS_AT` agents (default 12) is how the run confirms itself, tolerates one engine failing, and how the judge scales.

- **Preview and confirmation.** Before anything starts, the usual "N × R + 1 sessions" line becomes a table of spec, engine, count and total sessions, with quorum shown alongside (USD stays `unknown`, as everywhere else). Above `SWARM_CONFIRM_OVER` sessions (default 20), a TTY is asked to confirm; a non-TTY without `-y` fails with exit code 2 before any agent starts.
- **Quorum** defaults to `ceil(0.6N)` for `mass` (the `all` default is unchanged), so a handful of failed agents out of a hundred does not turn the whole run into a hard failure; `-q` still overrides it.
- **Rate limits are the orchestrator's job, not the agent's.** Classification only looks at the exit code / `is_error` and at error events or stderr, never at answer text (an agent that merely discusses "rate limiting" in its answer is not touched):
  - **Transient** (`rate.?limit|429|too many requests|overloaded|529`, overridable via `SWARM_RATELIMIT_RE`): the agent gets rc 76, its attempt is renamed to `aN.attempt<n>.*` so nothing is overwritten, and it is requeued up to 3 times with backoff `min(900, BASE·2^n)` plus jitter (`SWARM_BACKOFF_BASE`), recorded per engine in `.backoff/<engine>`.
  - **Exhausted** (`usage.?limit|quota|insufficient.?credit` — Codex's own message is *"You've hit your usage limit..."*): the agent gets rc 77, that engine is marked dead for the rest of the run, and its remaining queued agents are skipped rather than attempted. Both outcomes are logged in `failures.jsonl` and reflected in `PARTIAL`.
  - Models are never substituted for a different one automatically, on either path.
- **Critique stays off by default** (`-r 1`, i.e. `mass` itself). With `-r 2`, a deterministic ring gives every answer exactly `P` peer readers (default 4) instead of everyone reading everyone (O(N·P), not O(N²)); the mapping is stored in `r2/peers.json`.
- **Judging is a tournament.** Agents are stratified round-robin into groups of `G = 8` by `model@effort`. Each sub-judge (id `judge-L<n>-g<m>`, its own lock) reads only its group and ends with a fenced JSON `{"top":[...],"minority":[...]}`; an invalid sub-judge decision advances its whole group rather than dropping anyone silently. Levels repeat until at most `G` answers remain, and the final judge reads the survivors plus every sub-judge's report. 100 answers forwarding the top 1 per group is 16 judge sessions total (13 first-level groups + 2 more levels + 1 final); forwarding the top 2 is 18. Only exact duplicates are collapsed (by sha256), and judges are told `aN ≡ aM` rather than seeing the same text twice.
- **Board stays scoped.** `mass` prompts never carry the global last-60-messages tail; a sub-judge sees only its own group's messages; `post` is capped at 2 KB per message and 20 messages per outbox. `swarm.sh read DIR` for a human operator is unaffected.
- **Anonymity is unchanged:** ids are still shuffled `a1..aN`, and effort still never appears in a prompt.
- **Layout:** `r1/a1..a100.*`, `j/L<n>/g<m>.*` for tournament levels, `.backoff/`, `failures.jsonl`.
- **`mass` inside `loop`.** A `loop` iteration with more executors than `G` runs its own tournament, and only the top judge writes the iteration's `decision.json`. `-X` further limits the mass-sized roster to iteration 1 — explore wide once, then refine with a smaller, cheaper set of executors in later iterations.

Ring critique, tournament judging, board caps and `-X` are the most recently designed pieces of this protocol — **v0.5.0 if they land at merge time; otherwise they follow in a later release.**
