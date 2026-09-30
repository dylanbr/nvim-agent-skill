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

**Claude Code (plugin):** this repo is also a plugin marketplace:

```
/plugin marketplace add dylanbr/nvim-agent-skill
/plugin install nvim-agent-skill@nvim-agent-skill
```

**Claude Code (manual):** copy or symlink the skill into your personal or project skills directory:

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

## Editing through Neovim

By default the agent uses Neovim when you ask it to. Beyond that, the skill is useful in two ways.

**If you work in Neovim alongside the agent**, it streamlines that workflow:
- **You see changes happen** in your editor as the agent makes them.
- **Undo works on the agent's changes.** Each change the agent makes is one undo step, so `u` reverts it and `:earlier 5m` rolls back further.
- **Your buffers stay in sync:** no "file changed on disk" prompts.

**Some edits are quicker or more correct in Neovim**, even when you're not watching:
- **LSP edits:** renaming a symbol across the project, code actions, formatting. These are semantically correct, where find-and-replace also hits comments and strings.
- **Structural edits in one command:** `:g/pattern/normal A;`, `:sort u`, `:%!jq .`, re-indenting.
- **Large files:** changing one spot without reading the whole file.
- **Multi-file edits:** `:vimgrep` into the quickfix list, then `:cfdo %s/old/new/ge | update`.

The skill tells the agent about both. Small edits and new files still go through the agent's normal tools, which are faster for those.

Managed headless servers keep undo history too: attach and press `u`, or ask the agent to undo. The history ends when the server quits after its idle timeout.

### Making it the default

To have the agent route edits through your editor whenever it's open, add something like this to your `CLAUDE.md` or `AGENTS.md`:

```markdown
When my Neovim is running (`nv list` shows it), make code edits through it with the
nvim-remote skill so I can watch and undo them: one `nv lua`/`nv cmd` call per
logical change, using the vim.api functions rather than keystrokes, then `:write`
(undo still works after saving). Use your normal tools for new files and bulk
generated changes.
```

A middle option: route edits through Neovim only for files you already have open:

```markdown
Before editing a file, if my Neovim is running, check whether it's open
(`nv expr 'bufloaded("/abs/path")'`). If it is, edit that buffer with the
nvim-remote skill (by buffer number, without switching my window): run
`checktime` on it and read the lines from the buffer, not the file on disk. Make
one `nv lua` call per logical change, and save it. If it already had unsaved
changes, don't save it: stop and tell me to save it before you continue.
If the file isn't open, use your normal tools.
```

This also avoids conflicts when you have unsaved changes in a file the agent needs to edit. For that case, the skill has three options, and you can set a different default in the snippet or ask per request:

1. **Don't edit**: the agent stops and asks you to save or discard first.
2. **Edit, don't save** (the default): the agent's change joins yours in the buffer, and it stops until you save.
3. **Save, edit, save**: the agent saves your work first, then makes its change and saves again. `u` still reverts just the agent's change.

If the file also changed on disk, or anything else unexpected comes up, the agent stops and tells you rather than forcing a save.

A lighter option: let the agent edit files normally, then refresh your editor:

```markdown
After editing files, if my Neovim is running, run `nv cmd checktime` so my open
buffers reload.
```

Reloading is undoable too (for files up to 10,000 lines, Neovim's `undoreload` default), so `u` still reverts the agent's change. You just don't watch it happen.

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
