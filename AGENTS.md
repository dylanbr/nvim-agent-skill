# AGENTS.md

This file provides guidance to AI coding agents working with code in this repository.

An Agent Skill (and Claude Code plugin) that lets an agent drive Neovim over its RPC socket. The skill is `skills/nvim-remote/`: `SKILL.md` is the guide the agent reads, and `scripts/nv` is the only entry point it calls.

## Commands

```sh
tests/run.sh                          # full suite; needs nvim, perl, lsof, python3
bash -n skills/nvim-remote/scripts/nv # syntax check
skills/nvim-remote/scripts/nv --help  # usage, printed from the script's header comment
```

There is no build or linter. The test suite is one sequential script sharing one server, so there's no way to run a single test; comment out sections if needed. It starts its own managed server (`NV_SESSION=nvtest-$$`) and passes `-s` on every call.

When trying things by hand, never touch the user's running Neovim: set `NV_SESSION` to something unique, `nv start`, and pass `-s <socket>` (from `nv attach`) on every call. Keep socket paths under ~104 characters on macOS, or Neovim silently fails to listen (deep temp or scratch directories can be too long; `$TMPDIR` is fine).

## Architecture

- **`nv` (bash)** resolves a socket (`-s`/`$NVIM_SOCKET`, else the user's single running Neovim, else this session's managed headless server), then talks to it with `nvim --server … --remote-expr/--remote-send`, wrapped in a perl `alarm` timeout (exit 142 = timed out). Lua from commands (`lua`, `cmd`, `expr`, `state`, `buf` …) isn't inlined into `--remote-expr`: `lua_code` writes it to a temp file and `lua_file` runs it with `dofile` inside `luaeval`, returning strings raw and anything else as JSON, with errors marked `__NV_ERROR__`. `lua_quote` makes Lua long-bracket literals for passing text in. Only short fixed internal snippets (e.g. `touch_socket`, `unsaved_count`) are passed as expressions directly.
- **`nvrpc.py`** is a stdlib msgpack-rpc client used only for `nvim_get_mode`, a "fast" call Neovim answers even while blocked on input or a prompt. That's how `nv` tells "waiting for input / at a prompt" apart from "hung" (`rpc_mode`, `prompt_kind`, `doctor`). Without python3 it falls back to `--remote-expr`, which can't make that distinction.
- **`idle.lua`** is a module: `nv start` runs its `start()` in every managed server, an idle timer that quits after `NV_IDLE` seconds (validated by `nv`), never while a UI is attached or buffers are unsaved. `nv stop` calls its `unsaved()` too, so both use the same rule. `nv` records activity in `vim.g.nv_last_activity` via `touch_socket`, which also tracks which session last used the editor.
- **`buf.lua`** backs `nv buf read|edit|save`, safe edits to files the user has open. Each function returns text whose first word is a status (`ok`, `not-open`, `stop`, `changed`), which `cmd_buf` maps to exit codes 0/3/4/5. Edits go by buffer number (the user's window never switches), check `checktime` warnings and `changedtick` against the tick from the read, and force a new undo block per edit.
- **Managed servers** live in `$TMPDIR/nv-$USER` (mode 700, overridable with `NV_MANAGED_DIR`), one per agent session; the session ID logic is in `init_session`.

## Design rules

- The safe-edit and prompt handling follow the user's policy: on any edge case, **stop and tell the user** rather than guess; never force anything they haven't asked for (e.g. never save their unsaved work, never answer `y`, never escape or interrupt a prompt in their editor). Only a prompt `nv` itself caused, on a managed server nobody is attached to, may be answered (with `n`).
- Behaviour is documented in three places that must stay in sync: the header comment in `nv` (which is `--help`), `SKILL.md` (for the agent) and `README.md` (for users). `SKILL.md` is loaded into the agent's context on every use, so keep it tight.
- Neovim quirks that the code relies on are verified in `tests/run.sh`; add a test when relying on a new one.

## Releases

Bump `version` in `.claude-plugin/plugin.json` following the scheme in `README.md` (Development). Bump once per push: commits that haven't been pushed yet share one version.
