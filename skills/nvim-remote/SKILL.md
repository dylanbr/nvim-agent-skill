---
name: nvim-remote
description: Drive Neovim live over its RPC socket — the user's running editor, or a managed headless one started on demand — to send keystrokes, run Ex commands, evaluate Vimscript/Lua, and read editor state (mode, cursor, visible lines, windows, diagnostics). Use when the user asks you to drive, control, pair in, or do something "in/with/using nvim/neovim/vim" or this skill, or to connect to a Neovim socket. Also use when an edit is quicker or safer in Neovim: LSP rename/code actions/formatting, :g/:normal/:sort-style structural edits, targeted edits in large files, or changes the user may want to review and undo step by step. Not for small edits or new files, which your own tools do in one step.
---

# nvim-remote

Drive a live Neovim session like someone at the keyboard. The user can watch changes happen in real time.

All interaction goes through the helper script `scripts/nv` (relative to this skill's directory). Call it by absolute path:

```sh
NV=<this skill dir>/scripts/nv
```

Requires `nvim`, `perl`, `lsof`. `python3` is strongly recommended: `nv` uses it for the fast mode query that tells "waiting for input" apart from "hung". `jq` is optional, for pretty JSON.

## Which Neovim gets used

`nv` picks the target automatically:

1. **`-s SOCKET`** if given. Shell state doesn't persist between calls, so pass it on *every* call; an exported variable won't carry over.
2. **The user's own Neovim**, if exactly one is running. Every Neovim creates a socket at startup, so the user doesn't need `--listen`.
   - If several are running, `nv` lists them (with cwd and current file) and stops. Ask the user which one.
   - If one exists but isn't responding, `nv` stops with an error instead of quietly using something else. Go to Troubleshooting.
3. **A managed headless Neovim for this session**, started automatically in the current directory. Details below.

Run `$NV list` to see everything: the user's editors and all managed servers, each marked as this session's or another's.

### Managed servers

- **One per agent session**, so parallel sessions never share buffers, cursor or cwd. The session ID is `<agent>-<id>` (e.g. `claude-code-1a2b3c4d`). `nv` detects the agent name and the agent's own session ID where it can, and otherwise remembers a random ID for the calling agent process. Set `NV_SESSION` on every call to choose the ID yourself.
- **Started in the cwd of the first call.** `cd` to the right directory first, and **use absolute paths** for files anyway. `nv` warns if you call it from a directory other than the server's.
- **Started with `--clean`** (no user config or plugins), so behaviour is predictable. Set `NV_USER_CONFIG=1` on the call that starts it if the user wants their config, mappings and plugins, for example to demo their setup.
- **The user can't see it unless they attach.** When `nv` prints "started headless Neovim", pass the attach command on to the user:
  ```sh
  nvim --server <socket> --remote-ui     # also printed by: $NV attach
  ```
- **Lifecycle:** it quits after 15 minutes idle (`NV_IDLE` seconds), but never while a UI is attached or while it has unsaved changes. `$NV stop` shuts it down early. It refuses if there are unsaved changes and confirms the process actually exited. It only ever stops managed servers.
- Sockets live in a private per-user directory (`$TMPDIR/nv-$USER`, mode 700).

### Several sessions on one editor

If the user has one Neovim of their own and several agent sessions use it, they **all share it**. There's no way to isolate sessions inside one editor. `nv` warns when another session used the same Neovim in the last 10 minutes: "another agent session (…) used this Neovim Ns ago". When you see that:
- Re-check `state` right before acting. The file, cursor or mode may have changed under you.
- Prefer single atomic `lua`/`cmd` calls over multi-step `send` sequences, which can interleave with another session's keys.
- Tell the user another session is active on the same editor.

## Commands

| Command | What it does |
|---|---|
| `$NV state` | JSON snapshot: mode (+ `blocking`), file, filetype, modified, cursor, **visible lines numbered with `>` marking the cursor line**, windows (incl. floating), tab, diagnostic counts, `ui_attached`, last message. **This is your "eyes".** |
| `$NV send 'KEYS'` | Type keys as a human would, in Vim key notation (`<Esc>`, `<CR>`, `<C-w>`). **`<leader>` is NOT expanded**: it's typed literally and leaves Neovim waiting for more keys. Look up the real key with `$NV expr 'get(g:, "mapleader", "\\")'`. |
| `$NV cmd 'EXCMD'` | Run an Ex command and print its output (`ls`, `messages`, `map ,f`). Doesn't disturb the mode or cmdline. |
| `$NV expr 'EXPR'` | Evaluate Vimscript; result as JSON. |
| `$NV lua 'CODE'` | Run Lua. A returned string prints raw; anything else prints as JSON. |
| `$NV lua -f file.lua` | Same, from a file (use for anything multi-line or quote-heavy). |
| `$NV lines [A [B]]` | Numbered buffer lines A..B (default: whole buffer). |
| `$NV buf read\|edit\|save PATH …` | Safely read and edit a file the user has open, by buffer. See "Editing a file the user has open". |
| `$NV escape` | Back to normal mode from anything: pending keys, insert, visual, cmdline, hit-enter prompt, terminal. Works even when Neovim is waiting for input. Prints the resulting mode. |
| `$NV list` | All the user's Neovims and managed servers, with status. |
| `$NV start` / `stop` / `attach` | Managed server: start explicitly, stop, or print the command the user runs to watch it. If the user also has their own Neovim open, other commands still go to *theirs* unless you pass `-s <managed socket>`. |
| `$NV doctor` | Diagnose an unresponsive Neovim. See Troubleshooting. |
| `$NV interrupt` | Send CTRL-C as input. |
| `$NV kill [-9]` | Last resort: terminate the Neovim process. |

**Every command exits non-zero on failure**, including Lua and Vimscript errors (printed as `nv: error: …`). Check exit codes; don't assume success.

Global flags: `-s SOCKET`, `-t SECONDS` (per-call timeout, default 5, min 1). Env: `NV_IDLE` (min 10), `NV_USER_CONFIG=1`, `NV_TIMEOUT`, `NVIM_SOCKET` (same as `-s`), `NV_SESSION` (session ID override).

## When to edit through Neovim

Two reasons, beyond being asked to:

1. **The user works in Neovim alongside you.** Editing through their editor keeps them in the loop: they see each change as it happens, `u` undoes it, and their buffers never go stale.
2. **Neovim is quicker or more correct for the edit**, whether or not anyone is watching. See the list below.

Where Neovim wins:

- **LSP edits**: `vim.lsp.buf.rename()`, code actions, `vim.lsp.buf.format()`. They're semantically correct, unlike text replacement, which also hits comments and strings. They need a language server: the user's Neovim, or a managed server started with `NV_USER_CONFIG=1`.
- **Structural edits in one command**: `:g/pat/normal A;`, `:g/pat/d`, `:'<,'>sort u`, `:%!jq .`, `=` to re-indent, text objects. Each replaces many individual edits.
- **Large files**: jump to and change one spot without reading the whole file into context.
- **Multi-file edits with review**: `:vimgrep /pat/ **/*.ts`, then `:cfdo %s/old/new/ge | update`.
- **Undo**: every `nv lua` or `nv cmd` call is **one undo step**, even with several edits inside it. (That holds for the current buffer. Consecutive calls that change a buffer *not* shown in the current window merge into one step; `nv buf edit` avoids this.) `nv cmd undo` takes back your last change precisely; `:earlier 2m` rolls back further. The user can attach (or look at their editor) and press `u` to step back through your work. On a managed server the history lasts only as long as the server, which quits after `NV_IDLE` idle.

Your own file tools are still better for small targeted edits and new files. `sed`/`perl` match `:s` for plain regex replacements.

**Editing a file the user has open**: use `$NV buf`. It edits the buffer by number, so the user's window doesn't switch, and it runs the checks below for you. `buf read` on a file that isn't open exits 3: use your own tools.

```sh
$NV buf read /abs/path [A [B]]       # checktime, then a header and numbered lines A..B
$NV buf edit /abs/path TICK A B [--save] <<'EOF'
replacement lines
EOF
```
- `buf read` prints `ok buf=N tick=T modified=true|false lines=L`, then the lines. Take line numbers from this, not from the file on disk: the buffer can differ from it.
- `buf edit` replaces lines A..B (1-based, inclusive) with stdin; `B = A-1` inserts before line A, and `--delete` (no stdin) deletes. It first re-runs `checktime` and checks the buffer is unchanged since the read at `TICK`. Its output includes the new tick, for the next edit. Each call is one undo step.
- Pass the new lines with a heredoc, as above, not through a pipe. That keeps it a single `nv` command.

Exit status tells you what to do:

| Exit | Meaning | Do |
|---|---|---|
| 0 | Done | Carry on |
| 3 | Not open in Neovim | Use your own tools |
| 4 | Stop: a `checktime` warning (W11 changed on disk but not reloaded, W12 changed on disk *and* in the buffer, W13 created, W16 permissions changed, E211 deleted), a stale buffer, or `--save` with unsaved changes | Change nothing more. Tell the user what it says |
| 5 | The buffer changed since your read: the user typed or the file reloaded | Re-read and try once more; if it happens again, stop and tell the user |

**If the header says `modified=true`**, the user has unsaved work in that buffer. Do what they've asked for (in their instructions or the request), and if they haven't said, use option 2:
1. **Don't edit.** Stop and tell them to save or discard their changes before you can continue.
2. **Edit, don't save** (default). Use `buf edit` without `--save`. Your change is then only in the buffer, so tests, builds and anything else that reads the file won't see it. Stop and tell them to save the file before you can continue.
3. **Save, edit, save.** `$NV buf save /abs/path TICK` saves their work as they left it; then re-read and edit with `--save`.

Never pick a more forceful option than the user asked for, and never save their unsaved work unless they chose option 3. (`buf edit --save` refuses a buffer with unsaved changes, so you can't do it by accident.)

**Prompts:** a save can still hit Neovim's "file has been changed since reading it … (y/n)?" prompt, for example if the file changes between the check and the write. `nv` times out and reports what Neovim is waiting for and whose editor it is. Only answer a prompt you caused and understand:
- **A managed server nobody is attached to:** answer this write prompt with `$NV send n`. That declines, so nothing is written. Then stop and work out why the file changed.
- **The user's own Neovim, or a managed server they're attached to:** leave the prompt. Stop and tell the user their Neovim is asking whether to overwrite a file that changed on disk. It's their decision.

Never answer `y`, and never `escape` or `interrupt` a prompt in the user's editor.

**Edited a file outside Neovim** (with your own tools) that the user has open? Run `nv cmd checktime`. Unmodified buffers reload, and the reload is itself undoable (files up to `'undoreload'`, 10000 lines by default), so the user can still press `u` to see or revert your change.

## Working loop

1. **Look before acting.** Run `$NV state` first to see the mode, file and what's on screen.
2. **Act.**
   - To *demonstrate* or *pair*, where the user wants to see vim being used, use `send` with real keystrokes: motions, text objects, macros, their plugin mappings.
   - To just get something *done*, prefer the precise channels: `cmd` for Ex commands, or `lua` with the `vim.api` functions. They don't depend on mode, cursor position or user mappings, so they're more reliable.
   - Use **absolute paths** when opening or writing files.
3. **Verify.** Run `state` again (or `lines`/`expr`) to confirm the result. Don't assume a keystroke sequence did what you meant: mappings, plugins, autopairs and `smartindent` can all change what keys do.
4. **Report** briefly what you did. If it happened in a managed server the user isn't attached to (`ui_attached: false`), give them the attach command.

## Keystroke gotchas

- Start sequences from a known state. If `state` shows a mode other than `n`, or `blocking: true`, run `$NV escape` first.
- **Never leave a key sequence unfinished.** Keys like `z`, `g`, `"`, `m`, `q`, `f`, `t`, `r`, operators (`d`, `c`, `y`, `<`, `>`), `<C-w>`, or a literal `<leader>` leave Neovim waiting for the next key. **While it waits, it queues all other RPC calls**, so every `nv` command times out until `escape`.
- `send` returns before Neovim has processed the keys. For long sequences or ones that trigger async work (LSP, Telescope, completion), `sleep 0.2` before reading state.
- Inserting literal text: `<` must be written `<lt>`. For large text, don't type it. Use `lua` with `vim.api.nvim_buf_set_lines` / `nvim_put`, which also avoids autoindent and autopair mangling.
- A multi-line `:echo` or error triggers a hit-enter prompt (`mode` starts with `r`), and then keys go to the prompt. `escape` handles this.

## Troubleshooting a stuck Neovim

**How to tell it's stuck:** a command fails with "timed out … stuck or waiting for input", or `nv` reports a Neovim that "isn't responding".

**Step 1: diagnose.** Run `$NV -s SOCKET doctor`; the socket is in the error message. It works without Neovim's cooperation. It reports the process state, CPU usage, child processes (flagging only those started *after* Neovim, since plugins and LSP servers start with it), and whether Neovim answers a fast mode query. Then it prints a **verdict** and a **fix**.

**Step 2: fix, from least to most drastic.** Every row was reproduced in testing:

| Verdict | What doctor sees | Fix |
|---|---|---|
| **Waiting for input**: unfinished key sequence, `getchar()` | Fast query answers with `blocking: true`; everything else times out | `$NV escape` (safe: doesn't move the cursor) |
| **Waiting at a prompt**: confirm (`r?`), hit-enter (`r`), `-- More --` (`rm`), `input()` (`c`) | Mode starts with `r` or `c`; doctor says whose editor it is | Answer only a prompt you caused and understand. Otherwise, or in the user's editor, leave it and tell the user. |
| **Waiting on a child process**: `:!cmd`, `system()` | No answer, ~0% CPU, a shell child (`sh -c …`) or other recently started child. A non-shell child may just be an LSP server; read the children list. | `$NV interrupt` cancels it. Or kill only that child PID, not Neovim. |
| **Busy**: Vimscript infinite loop or huge operation | No answer, high CPU | `$NV interrupt` |
| **Busy: pure-Lua infinite loop** | No answer, high CPU, and `interrupt` says "could not deliver CTRL-C" | Only `$NV kill -9`. Lua loops never check for interrupts and ignore SIGTERM. |
| **Stopped** (user pressed CTRL-Z) | `stat` contains `T` | Ask the user to `fg` it, or `kill -CONT <pid>` |
| **Stale socket** | "no process owns it" | `rm` the socket file. Nothing is running. |

Re-run `doctor` after each fix until it says `healthy`.

**Step 3: kill, as a last resort.** `$NV kill` sends SIGTERM and `$NV kill -9` sends SIGKILL. It refuses if the socket isn't owned by an `nvim` process.
- For the **user's own editor**, always ask first: killing it loses unsaved changes, though swap files usually allow recovery with `nvim -r <file>`.
- **Your session's managed server** is yours to kill, unless it has unsaved buffers. Then ask.
- **Another session's managed server**: don't touch it. Tell the user. (`doctor`/`escape`/`interrupt`/`kill` never pick one without an explicit `-s`.)

**Never** send SIGINT (`kill -INT`) to Neovim. It terminates a headless instance instead of interrupting it. `nv interrupt` delivers CTRL-C as input, which is the safe way.

**Avoid causing hangs:** don't leave key sequences unfinished. Don't run `:!` commands that wait for input or run indefinitely (run those in your own shell instead). Don't send Lua with unbounded loops. Prefer `cmd`/`lua` over keystrokes that might open prompts.

## Etiquette and safety

- It's the user's live editor. Don't `:q`, `:qa!`, `:bd!` or discard unsaved changes (`modified: true`) unless they asked for it. Ask before `:w` unless saving is clearly part of the request.
- The user may be typing at the same time. If state changes unexpectedly between calls, assume they did it, re-read the state, and don't fight them.
- Keep changes undoable. Normal edits are, and the user can press `u`. Group each logical change into one `lua`/`cmd` call so it's one undo step, and mention `u` for big changes.
- Anyone with access to a socket gets full control of that Neovim, including shell commands via `:!`. Remind the user if they choose a `--listen` path in a shared or world-readable location.
- Socket paths must be under ~104 characters on macOS; longer paths fail with "connection refused".

## Useful Lua snippets

```lua
-- replace lines 10..12 (0-based, end-exclusive) in current buffer
vim.api.nvim_buf_set_lines(0, 9, 12, false, {"new a", "new b"})
-- move cursor (1-based line, 0-based col)
vim.api.nvim_win_set_cursor(0, {42, 0})
-- open a file (absolute path)
vim.cmd.edit("/abs/path/to/file")
-- list buffers
return vim.tbl_map(function(b) return {b, vim.api.nvim_buf_get_name(b)} end, vim.api.nvim_list_bufs())
-- diagnostics in current buffer
return vim.tbl_map(function(d) return {d.lnum + 1, d.severity, d.message} end, vim.diagnostic.get(0))
-- what does a key do? (use the real leader key, not <leader>)
return vim.fn.maparg(",f", "n", false, true)
```
