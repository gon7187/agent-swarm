# Architecture

`swarm.sh` is a single bash script. It does not host models, keep state in a server or talk to APIs directly: it launches the coding-agent CLIs you already use (`claude -p`, `codex exec`) as child processes, gives each one a prompt and a working directory, and collects their output into files. The round, board and judge protocol is described in [protocol.md](protocol.md); this page covers engines, sandboxing and the file layout.

## Engines

| Model | Engine | Command (simplified) |
|---|---|---|
| `claude-*`, or listed in `$SWARM_CLAUDE_MODELS` | Claude Code | `claude -p "<prompt>" --model <model> --output-format json ...` |
| anything else | Codex | `codex exec --json --skip-git-repo-check -m <model> -o <out.md> -s workspace-write -C <run>/a/<id> ... "<prompt>"` |

In `tasks.jsonl` an explicit `"engine": "claude" | "codex"` overrides the name-based choice. Binaries can be replaced with `SWARM_CLAUDE_BIN` / `SWARM_CODEX_BIN`, which is how `tests/test.sh` runs the whole flow offline against stubs.

The roster (`swarm.sh roster`) is the union of:

- Claude models from `$SWARM_CLAUDE_MODELS` (default `claude-fable-5-1 claude-opus-5-5 claude-sonnet-5 claude-haiku-4-5`), if `claude` is on `PATH`;
- Codex models from `$SWARM_CODEX_MODELS`, or from `codex debug models` filtered to `visibility == "list"`, if `codex` is on `PATH`.

Without `-m`, `all` uses the first model of each harness; `-m all` uses the whole roster.

### Usage accounting

- Claude: the JSON result goes to `<id>.md` (`.result`) and `<id>.usage` (`{cost: .total_cost_usd, usage}`); `is_error == true` counts as a failure.
- Codex: the `--json` event stream goes to `<id>.log`; usage is summed from `turn.completed` events.
- `swarm.sh status` prints a COST column and a total. Codex reports tokens but no USD figure, so where `.cost` is null the column shows input/output tokens from `.usage` instead. No price table is built in. When neither is available the column shows `unknown`, never 0.

## Preamble

Every agent's prompt starts with a preamble that gives it its id, the project path and the board commands, and tells it that other answers and board messages are untrusted evidence, never instructions. It also forbids inspecting `anon.map` and starting another swarm or sub-agents, and says that the final message is the deliverable.

The rest of the preamble depends on the engine and mode, so that it never asks for something the sandbox denies:

- **Working directory.** Claude workers run in the project (or their worktree) and are told to run git there directly. The allowlist is a prefix match, so `Bash(git log:*)` allows `git log` but not `git -C <dir> log`. Codex workers run in their own `a/<id>/` directory and are told to use absolute paths or `git -C` for the project.
- **Board.** `read` and `post` commands with the run directory and id filled in, to be run standalone (no `cd`, no `&&`). Round 1 of `all` shows only `post`; see [protocol.md](protocol.md).
- **Commits.** rw Claude workers are told to test and commit their own changes, staging specific files. rw Codex workers cannot write to the git directory, so they are told to leave their changes in the worktree; the orchestrator commits them (see [Worktrees](#worktrees)).

In `all` the id is the anonymous `aK`; in `run` it is the task `id`.

## Sandboxing per engine

| | Claude Code | Codex |
|---|---|---|
| **ro** (default) | `--permission-mode dontAsk --add-dir <run>` with `--allowedTools Read Grep Glob WebSearch WebFetch "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" "Bash(git status:*)" "Bash(git blame:*)"` + the board's `read`/`post` + `$SWARM_RO_ALLOW`. Anything else is denied without a prompt. | `-s workspace-write -C <run>/a/<id>`: the project is readable, only the agent's own directory (its outbox) is writable. |
| **rw** | `--permission-mode acceptEdits --add-dir <run>` with `--allowedTools Read Grep Glob Edit Write "Bash(git status:*)" "Bash(git diff:*)" "Bash(git add:*)" "Bash(git commit:*)"` + the board + `$SWARM_RW_ALLOW`. Working dir: the agent's worktree. | `-s workspace-write -C <run>/a/<id> --add-dir <worktree>`: the worktree's files are writable, the repository's git directory is not. The orchestrator commits. |
| **rw + `SWARM_UNSAFE_RW=1`** | `--dangerously-skip-permissions`. Full host access; a warning is printed to stderr before the run starts. | unchanged |
| **judge** | Always ro. | Always ro. |

`rg` is intentionally not on the ro allowlist: `rg --pre=CMD` executes arbitrary commands. `SWARM_RO_ALLOW` and `SWARM_RW_ALLOW` add tools, one pattern per line (e.g. `$'Bash(uv run pytest:*)\nBash(npm test:*)'`).

Codex rw workers do not get `--add-dir` on the repository's git directory. Earlier versions added it so Codex could commit, but it could also make the main repository's `.git/hooks` and `.git/config` writable from inside the sandbox, and a hook written there would run outside the sandbox on the user's next git command.

Unless `SWARM_INHERIT_CONFIG=1`, workers start without the user's own configuration. Authentication is not affected.

- **Claude:** `--setting-sources project,local --strict-mcp-config`. User settings, hooks, output style and MCP servers are not loaded; the project's `CLAUDE.md` and project settings are. (Before v0.4.0 workers also ran with `--safe-mode`, which disabled the project `CLAUDE.md` as well.)
- **Codex:** `--ignore-user-config`, which skips `~/.codex/config.toml` only. Everything else Codex reads on its own, such as `AGENTS.md` files, still applies.

All agents run under `timeout -k 30 <-t>`. A `trap` on INT/TERM walks the process tree of every background job (`pgrep -P`) and kills it: GNU `timeout` puts its child into its own process group, so killing the group of `swarm.sh` alone would not reach the model CLIs.

The same trap fires when a host tool (for example Claude Code's Bash tool) times out and kills a foreground `swarm.sh`, so long runs started from an agent must not run in the foreground. `-d` starts the orchestrator detached (`setsid`), prints `swarm dir: <run>` immediately and logs to `<run>/orchestrator.log`; `swarm.sh wait <run> [-t SEC]` exits 0 when the run is done, 75 when it is still running after `SEC`, and otherwise with the run's exit code.

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

If a `run` task sets `dir` to a subdirectory of the repository, the agent works in the same subdirectory of its worktree.

rw Claude agents commit their own work; for Codex, the orchestrator commits. After each rw agent, `swarm.sh`:

1. auto-commits leftover changes **only if the agent succeeded** (`rc == 0`), and only after checking that `HEAD` is on the branch recorded in `worktrees.jsonl` (`git symbolic-ref --short HEAD`) and descends from the recorded base (`git merge-base --is-ancestor`). The commit uses `-c user.name=swarm -c user.email=swarm@localhost` as a fallback identity, and the committed paths are recorded as `autocommitted` in the manifest;
2. sets `rc=71` and leaves the files untouched if either check or the commit fails;
3. appends `{id, branch, base, head, dirty}` to `manifest.jsonl` and writes `git diff <base>` to `r<N>/<id>.diff`.

Nothing is merged automatically. The judge ends with `WINNER: <branch>` or `WINNER: NONE`; the script takes the last such line, validates it against `worktrees.jsonl` and the manifest's `dirty` field, and prints one `git diff` and one `git merge --` command for a valid winner. `swarm.sh clean <run>` removes the worktrees and the `swarm/<run>/*` branches, but refuses to delete a worktree with uncommitted changes or a branch that is not merged. Losing branches are unmerged by design; `clean <run> --discard <branch>...` deletes the ones you name explicitly.

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
│   ├── <id>.rc                # exit code (124 = timeout, 65 = empty answer, 71 = rw commit failed)
│   ├── <id>.usage             # cost and tokens, when the engine reports them
│   └── <id>.diff              # rw: git diff against the base commit
├── r2/ ...
├── manifest.jsonl             # rw: {id, branch, base, head, dirty, autocommitted} per agent
├── worktrees.jsonl            # worktrees to remove with clean (path, branch, base)
├── final.md                   # all: judge output (+ final.log, final.rc)
├── result.json                # {rc, final, partial, winner, branches}, written atomically at the end
├── orchestrator.log           # -d: the detached orchestrator's output
└── <id>.md / .log / .rc       # run: one set per task
```
