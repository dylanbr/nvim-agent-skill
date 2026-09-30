# nvim-agent-skill

A Neovim agent skill for Claude Code and other AI coding agents. It lets an agent drive Neovim live over its RPC socket: send keystrokes, run Ex commands, evaluate Vimscript and Lua, and read editor state (mode, cursor, visible lines, windows, diagnostics).

The agent can work in **your running Neovim** while you watch, or in a **headless Neovim it starts on demand**. You can attach to that one at any time to see what it's doing.

## Features

- **Finds your editor automatically.** Every Neovim opens an RPC socket at startup, so no `--listen` is needed.
- **Managed headless servers** when no editor is running:
  - one per agent session, so parallel agents don't collide
  - `--clean` by default
  - quit after 15 minutes idle, but never while you're attached or while there are unsaved changes
- **Handles stuck editors.** `nv doctor` works out why Neovim isn't responding (waiting for keys, a shell command, a busy loop, a suspended process) and gives the fix. `escape`, `interrupt` and, as a last resort, `kill` recover it.
- **Multi-agent aware.** It warns when another agent session has recently used the same editor.

## Install

The skill is the `skills/nvim-remote` directory, in the [Agent Skills](https://agentskills.io) format (`SKILL.md` plus scripts).

**Claude Code:** copy or symlink it into your personal or project skills directory:

```sh
ln -s "$PWD/skills/nvim-remote" ~/.claude/skills/nvim-remote        # all projects
ln -s "$PWD/skills/nvim-remote" .claude/skills/nvim-remote          # one project
```

**Other agents:** put `skills/nvim-remote` wherever your agent loads Agent Skills from.

### Requirements

- Neovim 0.10+ (tested on 0.12)
- `bash`, `perl`, `lsof`: preinstalled on macOS and most Linux systems
- `python3` (strongly recommended): used for a fast RPC query that tells "waiting for input" apart from "hung"
- `jq` (optional): pretty-printed JSON output

## Usage

Ask your agent to do something "in nvim", or to drive, control or pair in Neovim. The agent uses the `nv` helper script:

```sh
nv state                 # what's on screen: mode, file, cursor, visible lines…
nv send 'ciwhello<Esc>'  # type keys
nv cmd 'ls'              # run an Ex command, print its output
nv lua 'return vim.api.nvim_buf_line_count(0)'
nv doctor                # diagnose a stuck Neovim
```

To watch a managed headless server, run the attach command it prints:

```sh
nvim --server <socket> --remote-ui
```

Run `nv --help` for all commands, and see [SKILL.md](skills/nvim-remote/SKILL.md) for the full guide the agent follows.

## Sessions

Each agent session gets its own managed server, named `<agent>-<id>` (for example `claude-code-1a2b3c4d`).

**Agent name:** taken from `$AI_AGENT` if set (Claude Code sets it), otherwise from the agent's process name.

**ID**, in order of preference:
1. `$NV_SESSION`, if set; this replaces the whole name
2. Claude Code's session ID
3. a random ID remembered for the calling agent process

All sessions share your own Neovim, since one editor can't be split between them. `nv` warns when another session has used it recently.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `NV_IDLE` | `900` | Seconds before an idle managed server quits (min 10) |
| `NV_USER_CONFIG` | unset | `1` = managed servers load your config and plugins instead of `--clean` |
| `NV_TIMEOUT` | `5` | Per-call RPC timeout in seconds (also `-t`) |
| `NVIM_SOCKET` | unset | Socket to use (also `-s`) |
| `NV_SESSION` | detected | Session ID override |

## Security

Anyone who can connect to a Neovim socket has full control of that Neovim, including running shell commands. Managed server sockets live in a private per-user directory (mode 700). If you start Neovim with `--listen`, choose a path other users can't reach.

## License

MIT. See [LICENSE](LICENSE).
