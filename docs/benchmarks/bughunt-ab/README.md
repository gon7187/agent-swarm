# Benchmark: swarm configurations — seeded bug hunt

An A/B test of swarm configurations on a task with ground truth: find bugs that were deliberately planted in a small codebase.
Companion to the [landing page benchmark](../landing-ab/README.md), which tested a creative task.

Date: 2026-09-26. Swarm version 0.5.1.

## Setup

- **Fixture:** a copy of a small async HTTP client library (5 modules, 631 lines of Python: token-bucket rate limiter, retrying httpx transport, typed errors, rate presets). The copy was stripped of tests and git history and committed as a single commit.
- **Ground truth:** 12 bugs planted with one-line edits ([`seeded.diff`](seeded.diff), [`eval/inject.py`](eval/inject.py)). Each of 14 candidate mutations was first run against the original test suite: 12 were caught, S1 and S2 were not. The final set is 10 caught mutations plus S1 and S2. The tests were then removed so that nobody can just read red tests.
- **Task:** identical for everyone ([`TASK.md`](TASK.md)). The repo is read-only; agents may run `.venv/bin/python` to confirm a hypothesis. Output is a list of `file:line`, defect, failure scenario, severity, confidence, and whether the finding was verified. The prompt states that false positives cost as much as misses.
- **Scoring:** recall on the 12 seeded bugs, false positives (reported defects that are not real), and wall time and cost. Real defects outside the seeded set are counted as *extra findings*. They are not scored and are not listed here.

### Seeded bugs

| ID | Where | Defect | Difficulty |
|---|---|---|---|
| S1 | limiter `acquire` | sleep computed from base rate, not the halved adaptive rate | hard |
| S2 | limiter `observe_retry_after` | a shorter `Retry-After` overwrites a longer active pause | medium |
| S3 | limiter `acquire` | `tokens > 1.0` instead of `>=`: `burst=1` buckets spin forever | medium |
| S4 | limiter `_credit` | post-window segment starts at `half_start`, so the window is credited twice | medium |
| S5 | transport | 504 missing from retryable statuses (contradicts a docstring) | easy |
| S7 | client factory | `setdefault` → assignment: token overwrites the caller's `Authorization` header | medium |
| S8 | rate presets | `"3/s"` where the comment on the same line says 3 req/min | easy |
| S10 | `Retry-After` parser | naive HTTP-date read as local time instead of UTC | hard |
| S11 | transport | `stop_after_attempt(max_attempts + 1)`: one extra attempt | medium |
| S12 | transport | `Retry-After` from any retryable 5xx pauses and halves the limiter (should be 429 only) | medium |
| S13 | limiter `try_acquire` | refill before the pause check, and `<=` at the deadline | hard |
| S14 | errors | 422 no longer maps to the validation error (contradicts its docstring) | easy |

## Contestants

| | Configuration | Sessions |
|---|---|---|
| **A** | `gpt-6-astra` solo (`swarm.sh run`, one task) | 1 |
| **B** | `claude-opus-5-5` solo | 1 |
| **C1** | `all -r 2 -m "gpt-6-luna*16" -S gpt-6-luna`: 16 identical cheap workers, mass mode (ring critique, tournament judging) | 35 |
| **C2** | C1's worker answers re-judged with `judge DIR -S claude-opus-5-5` | +3 |
| **C3** | C1's worker answers re-judged with `judge DIR -S gpt-6-astra` | +3 |
| **D** | `all -r 2 -m all -S claude-opus-5-5`: the full roster, 11 different models (4 Claude, 7 GPT), normal mode | 23 |

C2 and C3 change only the judge, so they isolate the judge's effect.

## Results

| | Seeded found (of 12) | False positives | Extra findings | Wall time | Cost (USD) |
|---|---|---|---|---|---|
| **A** astra solo | 9 | 0 | 8 | 3m28s | 1.05 |
| **B** opus solo | 9 | 0 | 1 | **1m20s** | **0.43** |
| **C1** luna×16, luna judge | 6 | 0 | 2 | 8m09s | 0.27 |
| **C2** luna×16, opus judge | 7 | 0 | 1 | 8m09s + 1m20s | ~1.33 |
| **C3** luna×16, astra judge | 7 | 0 | 2 | 8m09s + 3m52s | ~2.83 |
| **D** `-m all`, opus judge | **10** | 0 | 1 | 13m11s | 13.73 (Claude 8.01 + OpenAI 5.72) |
| A ∪ B (union of the two solo lists) | **11** | 0 | 8 | 3m28s in parallel | 1.48 |

Which seeded bugs each contestant found:

| | S1 | S2 | S3 | S4 | S5 | S7 | S8 | S10 | S11 | S12 | S13 | S14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A astra | · | ✓ | ✓ | ✓ | ✓ | · | ✓ | · | ✓ | ✓ | ✓ | ✓ |
| B opus | ✓ | · | ✓ | ✓ | ✓ | · | ✓ | ✓ | ✓ | ✓ | · | ✓ |
| C1 luna judge | · | · | ✓ | ✓ | ✓ | · | ✓ | · | · | · | ✓ | ✓ |
| C2 opus judge | · | · | ✓ | ✓ | ✓ | · | ✓ | · | ✓ | · | ✓ | ✓ |
| C3 astra judge | · | ✓ | ✓ | ✓ | ✓ | · | ✓ | · | · | · | ✓ | ✓ |
| D `-m all` | · | ✓ | ✓ | ✓ | ✓ | · | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

S7 (a one-line `setdefault` → assignment) was found by nobody in any configuration. S1 was rejected explicitly by the opus judges ("only extra wake-ups, tokens are never granted early"), which is fair: it is a performance defect, not a correctness one. Counting S1 as debatable, D missed only S7.

### Per-model recall inside D, round 1

Approximate: keyword match on the round-1 answers, spot-checked by hand.

| Model | Seeded found |
|---|---|
| claude-opus-5-5 | 11 |
| claude-fable-5-1, claude-sonnet-5 | 10 |
| gpt-5.5 | 9 |
| gpt-5.6-sol, gpt-5.6-terra, gpt-6-astra, gpt-5.6-luna | 7–8 |
| claude-haiku-4-5 | 7 |
| gpt-6-sol, gpt-6-luna | 4–5 |

The union of round 1 covered 11 of 12 (all but S7). Claude models consistently caught S1 and S10; GPT models were the ones catching S2.

## What the A/B shows

1. **Diversity beats headcount.** Sixteen copies of one model share one set of blind spots. All 16 luna workers together (raw, before judging) reached ~9 seeded bugs, and none of them found S2, S7 or S10. Eleven *different* models reached 11 in round 1.
2. **Mass-mode tournament judging hurts recall on this kind of task.** Only 4 of 16 answers reached the final judge. Findings supported by many workers were dropped: S11 was reported by 13/16 workers and rejected by the luna and astra judges; S12 was reported by 7/16 and lost by all three judges. In normal mode (D) the judge reads every answer, and it kept 10.
3. **Critique rounds converge rather than discover.** Round 2 spread the popular findings to everyone (S3: 5/16 → 16/16). It found nothing new, and it cut one true finding from 9/16 to 4/16 workers.
4. **A stronger judge adds 1–2 bugs, partly from its own head.** The astra judge contributed S2, which no luna worker had found. A strict judge also moves borderline-but-real findings into "unresolved", which trades recall for precision.
5. **No configuration produced false positives.** The judges' main value here was filtering overstatements and wrong line numbers, not rejecting fake bugs.
6. **Cost/quality:** two different strong models, run solo in parallel and merged (A ∪ B), gave 11/12 for $1.48. The full-roster swarm gave 10/12 for $13.73. A cheap homogeneous swarm is cheap ($0.27), but no judge lifts it above 7/12.

**Recommendation for bug hunts:** run 2–3 *different* strong models for one round and merge their findings without a filtering tournament. Use `all -m all` when a missed bug is expensive and cost is secondary. Avoid homogeneous mass swarms for recall-oriented tasks.

**Limitations:** one run per configuration (n = 1), one small fixture, and seeded bugs that are one-line edits. The ranking between A and B in particular is within run-to-run noise: inside D, the astra worker found ~7 seeded bugs versus 9 in its solo run.

## Costs

Claude costs come from the harness's `.usage` files. OpenAI costs are computed with [`eval/cost.py`](eval/cost.py) from token counts at [OpenAI API](https://developers.openai.com/api/docs/pricing) standard short-context prices as of September 2026 (per 1M input / cached input / output tokens):

| Model | Price per 1M input / cached input / output tokens |
|---|---|
| gpt-6-astra | $10 / $1 / $50 |
| gpt-6-sol | $2 / $0.20 / $10 |
| gpt-6-luna | $0.10 / $0.01 / $0.50 |
| gpt-5.6-sol | $4 / $0.40 / $20 |
| gpt-5.6-terra | $2 / $0.20 / $12 |
| gpt-5.6-luna | $0.20 / $0.02 / $1.20 |
| gpt-5.5 | $5 / $0.50 / $30 |

Reasoning tokens are assumed to be included in `output_tokens`.

## Files

- [`TASK.md`](TASK.md): the prompt every contestant got.
- [`seeded.diff`](seeded.diff): the 12 planted bugs against the original fixture.
- [`eval/inject.py`](eval/inject.py): the candidate mutations. `probe` checks which ones the original tests catch; `apply` plants them.
- [`eval/cost.py`](eval/cost.py): OpenAI cost from the swarm run directories.
