# Recipes

Five patterns that pay for the extra tokens. Run all of them from the project root; outputs land in `.swarm/<timestamp>/`.

General rule for prompts: make them self-contained. State the goal, the constraints, the files that matter and the output format you want. Agents do not see your chat history. They do follow the project's `CLAUDE.md` / `AGENTS.md`, so project conventions need not be repeated.

When you start a recipe from inside Claude Code or Codex rather than a terminal, do not run it in the foreground: use Claude Code's `run_in_background`, or add `-d` and poll with `swarm wait .swarm/<run> -t 300` (0 = done, 75 = still running). See the README section on long runs.

## 1. Architecture review

Several models propose and attack a design; the judge merges the strongest parts.

```bash
swarm all -m all -r 2 "
We need to add multi-tenant support to this service (see src/ and docs/adr/).
Constraints: single Postgres cluster, no downtime migration, < 5 ms p50 overhead.
Propose a design: data isolation model, migration plan, risks.
Output: a short design doc with a decision table and open questions."
```

Why it works: round 1 gives you genuinely independent designs (agents do not read the board yet); round 2 forces each model to refute or accept the others' claims with evidence. `-m all` is worth it here: 11 models means 23 sessions, but a design decision is expensive to get wrong. Read the `UNRESOLVED` part and the "where agents disagreed" section of `final.md` first; that is where the real decision is.

## 2. Hard-bug hunt

Different models notice different things. Let them race and cross-check each other's hypotheses.

```bash
swarm all -r 2 "
Intermittent test failure: tests/test_sync.py::test_concurrent_upload fails ~1 in 20 runs
with 'IntegrityError: duplicate key value violates unique constraint uploads_pkey'.
Find the root cause. Read src/sync/ and the test. Do not propose retries as a fix.
Output: root cause with file:line evidence, a minimal fix, and how to prove it."
```

Tips:

- Paste the exact error text and the failing command; do not paraphrase.
- Agents post hypotheses to the board early; from round 2 others must refute them with evidence instead of repeating the same investigation.
- Default read-only mode is right here: you want diagnosis, not five competing patches. To let read-only Claude agents run the failing test themselves, allow it explicitly: `SWARM_RO_ALLOW='Bash(uv run pytest:*)'`.

## 3. Parallel feature in worktrees

Split a feature by file ownership and give each part to a model. All tasks in one `run` start at the same time, and every worktree is created from your current `HEAD`, so **one run is for independent tasks only**. If one part needs another part's committed output, split the work into phases: run, review and merge the first phase, then start the next one from the merged `HEAD`.

Here the API and the UI both depend on the schema and the API contract, so they are phase 2.

`phase1.jsonl`, the shared foundation:

```jsonl
{"id":"schema","model":"claude-sonnet-5","worktree":true,"prompt":"Add an 'invoices' table + migration in db/, and write the REST contract for invoice CRUD (endpoints, request and response JSON) to docs/api/invoices.md. Own only db/ and docs/api/. Commit your work."}
```

`phase2.jsonl`, two independent tasks built on the merged contract:

```jsonl
{"id":"api","model":"gpt-5.5","worktree":true,"prompt":"Implement the invoice endpoints exactly as specified in docs/api/invoices.md, in src/api/invoices/. Own only src/api/invoices/. Include tests. If the contract is ambiguous, post the question to the board and state your assumption in your final message."}
{"id":"ui","model":"claude-sonnet-5","worktree":true,"prompt":"Add an invoices list page in web/src/pages/invoices/ that uses the API in docs/api/invoices.md. Own only that dir. Commit your work."}
```

```bash
swarm run phase1.jsonl
git diff HEAD..swarm/<run1>/schema             # review, then merge
git merge -- swarm/<run1>/schema
swarm clean .swarm/<run1>

SWARM_RW_ALLOW='Bash(npm test:*)' swarm run -j 2 phase2.jsonl
git log --oneline swarm/<run2>/api swarm/<run2>/ui
git merge -- swarm/<run2>/api swarm/<run2>/ui
swarm clean .swarm/<run2>
```

The `api` task runs on Codex, so it does not commit itself: the orchestrator commits its changes on `swarm/<run2>/api` when it finishes successfully. If that commit fails, the task gets `rc=71` and the changes stay in its worktree.

Rules that keep this sane:

- One run = tasks that can start from the same commit. Anything that needs another task's output goes into a later phase.
- Every task names the directories it owns; nobody edits outside them.
- Shared contracts (schema, API shape) are committed files from an earlier phase, not board messages. The board is for questions and for reporting mismatches.
- rw agents can edit and commit, nothing else; allow project commands such as a test runner with `SWARM_RW_ALLOW`.
- You merge. Review each branch like a PR (`manifest.jsonl` lists base and head per agent). To drop a branch you do not want, name it explicitly: `swarm clean .swarm/<run> --discard swarm/<run>/<id>`.

## 4. Research

Ask every model the same question, then have the judge reconcile the sources.

```bash
swarm all -r 1 -S claude-opus-5-5 "
Compare pgvector, Qdrant and LanceDB for 50M 768-dim embeddings, filtered search,
single-node deployment, 2026 versions. Use web search and cite sources with URLs.
Output: a comparison table (recall, latency, memory, ops burden, license) and a recommendation."
```

One round is usually enough for research: the value is in independent searches, and the judge compares citations. Add `-r 2` if the first answers conflict on facts.

## 5. Second-opinion code review

Before merging something risky, get reviewers that did not write it.

```bash
git diff main...feature/payments > /tmp/payments.diff
swarm all -r 2 -m "claude-opus-5-5 gpt-5.5 claude-sonnet-5" "
Review the diff in /tmp/payments.diff (branch feature/payments, repo is the current dir).
Focus: correctness, money handling (rounding, currency), idempotency, security.
Ignore style. For each finding: file:line, severity, a concrete failure scenario, a fix.
Drop findings you cannot back with a failure scenario."
```

The critique round is what makes this useful: false positives from one model tend to get refuted by the others on the board, and the judge keeps what survived. Verify each remaining finding yourself before acting on it.

## Keeping cost down

A run is `N × R + 1` sessions, and the number is printed before start.

- The default roster (one model per harness) is enough for most questions; `-m all` is for decisions worth real money.
- `-m` with two or three models covers most second-opinion needs.
- `-r 1` for independent opinions only; `-r 2` when you want debate; more rounds rarely help.
- A cheaper judge (`-S claude-sonnet-5`) is fine when answers are likely to converge.
- If only the judge failed, `swarm judge .swarm/<run>` reruns it without redoing the rounds; if the run was interrupted, `swarm resume .swarm/<run>` reruns only the agents that did not finish.
- `-q N` lets a run finish with N valid answers instead of stopping on the first failed agent. Failed agents drop out of later rounds.
- From inside an agent, never run a long swarm in the foreground: a host timeout kills it and the finished work with it. Use `-d` + `swarm wait`.
