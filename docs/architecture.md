# Architecture

`swarm.sh` is a single bash script. It does not host models, keep state in a server or talk to APIs directly: it launches the coding-agent CLIs you already use (`claude -p`, `codex exec`) as child processes, gives each one a prompt and a working directory, and collects their output into files. The round, board and judge protocol is described in [protocol.md](protocol.md); this page covers engines, sandboxing and the file layout.

## Engines

| Model | Engine | Command (simplified) |
|---|---|---|
| `claude-*`, or listed in `$SWARM_CLAUDE_MODELS` | Claude Code | `claude -p "<prompt>" --model <model> --output-format json ...` |
| anything else | Codex | `codex exec --json --skip-git-repo-check -m <model> -o <out.md> -s workspace-write ... "<prompt>"` |

In `tasks.jsonl` an explicit `"engine": "claude" | "codex"` overrides the name-based choice. Binaries can be replaced with `SWARM_CLAUDE_BIN` / `SWARM_CODEX_BIN`, which is how `tests/test.sh` runs the whole flow offline against stubs.

The roster (`swarm.sh roster`) is the union of:

- Claude models from `$SWARM_CLAUDE_MODELS` (default `claude-fable-5-1 claude-opus-5-5 claude-sonnet-5 claude-haiku-4-5`), if `claude` is on `PATH`;
- Codex models from `$SWARM_CODEX_MODELS`, or from `codex debug models` filtered to `visibility == "list"`, if `codex` is on `PATH`.

Without `-m`, `all` uses the first model of each harness; `-m all` uses the whole roster.

### Usage accounting

- Claude: the JSON result goes to `<id>.md` (`.result`) and `<id>.usage` (`{cost: .total_cost_usd, usage}`); `is_error == true` counts as a failure.
- Codex: the `--json` event stream goes to `<id>.log`; usage is summed from `turn.completed` events.
- `swarm.sh status` prints a COST column and a total. Missing data is shown as `unknown`, never as 0.

## Preamble

Every agent's prompt starts with a preamble that gives it its id, the project path and the board commands:

```text
You are agent "<id>" in a swarm of AI agents working in parallel. Project dir: <project>
Your cwd is scratch space; the project is <project> (use absolute paths or git -C).
Shared message board:
  read:  <swarm.sh> read <run> <id>
  post:  <swarm.sh> post <run> <id> "message" [target_agent_id]
Run board commands standalone (no cd, no &&).
You are a worker: never start another swarm or spawn sub-agents. Your final message is your deliverable.
```

In `all` the id is the anonymous `aK`; in `run` it is the task `id`. Round 1 of `all` asks agents to post only; see [protocol.md](protocol.md).

## Sandboxing per engine

| | Claude Code | Codex |
|---|---|---|
| **ro** (default) | `--permission-mode dontAsk --add-dir <run>` with `--allowedTools Read Grep Glob WebSearch WebFetch "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" "Bash(git status:*)" "Bash(git blame:*)"` + the board's `read`/`post`. Anything else is denied without a prompt. | `-s workspace-write -C <run>/a/<id>`: the project is readable, only the agent's own directory (its outbox) is writable. |
| **rw** | `--permission-mode acceptEdits --add-dir <run>` with `--allowedTools Read Grep Glob Edit Write "Bash(git status:*)" "Bash(git diff:*)" "Bash(git add:*)" "Bash(git commit:*)"` + the board + `$SWARM_RW_ALLOW`. Working dir: the agent's worktree. | `-s workspace-write -C <worktree> --add-dir <run>/a/<id>`. |
| **rw + `SWARM_UNSAFE_RW=1`** | `--dangerously-skip-permissions`. Full host access; a warning is printed. | unchanged |
| **judge** | Always ro. | Always ro. |

`rg` is intentionally not on the ro allowlist: `rg --pre=CMD` executes arbitrary commands.

Unless `SWARM_INHERIT_CONFIG=1`, workers start without the user's own configuration: Claude without user settings, hooks and MCP servers, Codex with `--ignore-user-config`. Authentication is not affected.

All agents run with stdin closed (`</dev/null`) and under `timeout -k 30 <-t>`. A `trap` on INT/TERM walks the process tree of every background job (`pgrep -P`) and kills it: GNU `timeout` puts its child into its own process group, so killing the group of `swarm.sh` alone would not reach the model CLIs.

### Mode and worktree

`mode` controls permissions; `worktree` controls where the agent works. They are independent, and contradictions are rejected:

| `mode` | `worktree` | Result |
|---|---|---|
| unset | `true` | `rw` in its own worktree |
| unset | unset / `false` | `ro` in the project |
| `rw` | `true` | `rw` in its own worktree |
| `rw` | `false` | rejected unless `"shared": true` (several writers in one checkout) |
| `ro` | `true` | rejected |

In `all`, `-w` means `rw` + one worktree per agent.

### Worktrees

Each worktree agent gets:

- path `<repo>/.swarm/wt/<run>-<id>`,
- branch `swarm/<run>/<id>`, created from the current `HEAD` (uncommitted changes are not included; `-w` warns when the tree is dirty).

rw agents commit their own work. After each rw agent, `swarm.sh` appends `{id, branch, base, head, dirty}` to `manifest.jsonl` and writes `git diff <base>` to `r<N>/<id>.diff`. Nothing is merged automatically; the judge names a `WINNER` and the script prints the merge command. `swarm.sh clean <run>` removes the worktrees and the `swarm/<run>/*` branches, but refuses to delete a worktree with uncommitted changes or a branch that is not merged.

### Nesting guard

`swarm.sh` exports `SWARM_DEPTH=1` before launching agents and refuses to start a swarm when `SWARM_DEPTH >= 1`. The board subcommands (`read`, `post`) and `roster` still work inside workers.

## File layout of a run

```text
<run>/                         # -o, default .swarm/<YYYYmmdd-HHMMSS>
├── task.md                    # the task text
├── anon.map                   # all: aK <TAB> model
├── a/<id>/outbox.jsonl        # the agent's board messages (its only writable place in ro)
├── r1/                        # all: one dir per round
│   ├── <id>.md                # the agent's answer (written by swarm.sh)
│   ├── <id>.log               # engine log / event stream
│   ├── <id>.rc                # exit code (124 = timeout, 65 = empty answer)
│   ├── <id>.usage             # cost and tokens, when the engine reports them
│   └── <id>.diff              # rw: git diff against the base commit
├── r2/ ...
├── manifest.jsonl             # rw: {id, branch, base, head, dirty} per agent
├── worktrees.jsonl            # worktrees to remove with clean
├── final.md                   # all: judge output (+ final.log, final.rc)
└── <id>.md / .log / .rc       # run: one set per task
```
