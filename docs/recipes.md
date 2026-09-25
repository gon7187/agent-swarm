# Recipes

Five patterns that pay for the extra tokens. Run all of them from the project root; outputs land in `.swarm/<timestamp>/`.

General rule for prompts: make them self-contained. State the goal, the constraints, the files that matter and the output format you want. Agents do not see your chat history.

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
- Default read-only mode is right here: you want diagnosis, not five competing patches.

## 3. Parallel feature in worktrees

Split a feature by file ownership, give each part to a model, and let them coordinate the contract on the board.

`tasks.jsonl`:

```jsonl
{"id":"schema","model":"claude-sonnet-5","mode":"rw","worktree":true,"prompt":"Add an 'invoices' table + migration in db/. Own only db/. Post the final column list to the board as soon as it is stable. Commit your work."}
{"id":"api","model":"gpt-5.5","mode":"rw","worktree":true,"prompt":"Add CRUD endpoints for invoices in src/api/invoices/. Own only src/api/invoices/. Take the schema from the board (agent 'schema'); ask there if unclear. Include tests. Commit your work."}
{"id":"ui","model":"claude-sonnet-5","mode":"rw","worktree":true,"prompt":"Add an invoices list page in web/src/pages/invoices/. Own only that dir. Take the API shape from the board (agent 'api'). Commit your work."}
```

```bash
SWARM_RW_ALLOW='Bash(npm test:*)' swarm run -j 3 tasks.jsonl
git log --oneline swarm/<run>/schema swarm/<run>/api swarm/<run>/ui
git merge swarm/<run>/schema swarm/<run>/api swarm/<run>/ui
swarm clean .swarm/<run>
```

Rules that keep this sane:

- Every task names the directories it owns; nobody edits outside them.
- Shared contracts (schema, API shape) are published on the board, with an explicit producer.
- rw agents can edit and commit, nothing else; allow project commands such as a test runner with `SWARM_RW_ALLOW`.
- You merge. Review each branch like a PR (`manifest.jsonl` lists base and head per agent).

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
- If only the judge failed, `swarm judge .swarm/<run>` reruns it without redoing the rounds.
- `-q N` lets a run finish with N valid answers instead of stopping on the first failed agent.
