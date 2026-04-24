<div align="center">
  <h1 text-align style="width:100%">Tau.nvim</h1>
  <img alt="yoshi" width="500" src="https://github.com/emilpriver/tau.nvim/blob/main/logo.png?raw=true" />
</div>

**tau.nvim** is a Neovim plugin that embeds an **AI coding agent** in your editor: a chat UI with **streaming replies**, **tool use** (read/write files, run commands, Neovim buffers, etc.), **sessions** persisted to disk, **@mentions** for file context, and **AGENTS.md**-style project instructions. Providers (LLM backends) are **pluggable**: load them via `setup({ plugins = ... })` and/or `register_provider`.

**Requirements:** Neovim **0.10+** and **`curl`** on `PATH` (see [`:help checkhealth`](https://neovim.io/doc/user/pi_health.html) via `:TauCheckHealth`).

---

## Features

- **Chat UI** — Side split or floating layout; history buffer + prompt; optional zen mode.
- **Streaming** — Token-by-token assistant output with optional reasoning/thinking display.
- **Tools** — Model can call tools (file I/O, `bash`, buffer introspection, diagnostics, etc.); the dispatcher runs a bounded tool loop.
- **Sessions** — One session per tab; JSONL storage under `vim.fn.stdpath("state")/tau/sessions/`; scoped by **cwd**; resume via `vim.ui.select` (same UX as built-in pickers).
- **Session branching** — Lua API to fork from a message, clone a session, or pick a fork point interactively.
- **Mentions** — Insert file/selection context into the prompt (`:TauPromptContext`); extensible mention providers.
- **Agents** — Loads `AGENTS.md` from `~/.agents/` and project `.agents/` into the system prompt (`:TauAgents`).
- **Auth** — `:TauLogin` / `:TauLogout` with keys stored via `tau.auth`; providers can also read API keys from environment variables they define.
- **Extensibility** — Register **LLM providers**, **mention providers**, and **session storage** backends from other plugins or your config.

---

## Installation

Use your plugin manager and call `setup()` once.

**lazy.nvim**

```lua
{
  "emilpriver/tau.nvim", -- or: dir = "~/path/to/tau.nvim" for local dev
  lazy = false,
  config = function()
    require("tau").setup({
      plugins = { "your.provider.module" },
    })
  end,
}
```

Configure credentials the way your provider documents (often an env var and/or `:TauLogin <provider_name>`).

Then run `:TauCheckHealth` and open the UI with `:Tau` or `:Tau layout=float`.

---

## Quick start

| Action | Command |
|--------|---------|
| Open chat (new session) | `:Tau` — optional `layout=side` or `layout=float` |
| Toggle UI | `:TauToggle` |
| Close UI | `:TauClose` |
| Stop streaming | `:TauStop` |
| Abort turn | `:TauAbort` |
| New session | `:TauNew` / `:TauNewSession` |
| Continue latest session (cwd) | `:TauContinue` |
| Pick a saved session | `:TauResume` |
| End session + close + clear tab session | `:TauSessionEnd` |
| Set session display name | `:TauSessionName My feature` |
| LLM-generated session title | `:TauSessionTitleLlm` (`!` to replace existing name) |
| Session metadata | `:TauSessionInfo` |
| Export chat to HTML | `:TauExport /path/to/out.html` |
| Model picker | `:TauModel` |
| Compact context | `:TauCompact` [optional instructions] |
| Insert @-style context | `:TauPromptContext` |
| Zen mode | `:TauZen` |
| Health | `:TauCheckHealth` |

Full command list lives in [`plugin/tau.lua`](plugin/tau.lua).

---

## How it works (architecture)

1. **`require("tau").setup`** merges config, registers the default **JSONL session storage**, loads **provider plugins** (`plugin.init`), and initializes **mentions**.
2. **`:Tau` → `tau.ui.open`** creates or focuses the layout, starts a **new session** for that open (with system prompt from **`tau.agents`** when applicable), and wires keymaps.
3. **Submitting the prompt** appends a user message, **`tau.dispatcher`** calls **`tau.api.stream`** for the configured provider; chunks update the history buffer.
4. If the model returns **tool calls**, **`tau.tools`** executes them; results are appended and the model may be called again until text-only completion or a safety limit.
5. **Autosave** writes the session JSONL file after messages and completed turns; **winbar** shows `title · provider | model` (title may be manual, LLM-generated, or a short id).

Main Lua entrypoints: [`lua/tau/init.lua`](lua/tau/init.lua). UI: [`lua/tau/ui.lua`](lua/tau/ui.lua). API abstraction: [`lua/tau/api.lua`](lua/tau/api.lua). Provider modules can live under [`lua/plugin/`](lua/plugin/) or separate plugins.

---

## Configuration

`setup({ ... })` accepts options merged into [`lua/tau/config.lua`](lua/tau/config.lua). Notable areas:

| Area | Purpose |
|------|---------|
| `provider` | `name`, `model`, optional `base_url` |
| `layout` | `default` (`side` / `float`), widths, borders, panel `winbar` toggles |
| `labels`, `spinner`, `show_thinking`, `dialog`, `zen` | UI copy and behavior |
| `mention_provider`, `mention_plugins` | Mention system |
| `session` | `auto_llm_title` (default **off**), `title_max_chars_excerpt`, `title_max_length`, optional `title_model` |
| `plugins` | List of Lua module names passed to `tau.plugin.init` (each should register a provider in `setup`) |

Example — enable automatic LLM session titles and a dedicated title model:

```lua
require("tau").setup({
  plugins = { "your.provider.module" },
  session = {
    auto_llm_title = true,
    title_model = "your-small-model-id", -- optional; defaults to main provider model
  },
})
```

---

## Session storage API

Other plugins can replace or augment persistence:

- `require("tau").TauRegisterSessionStorage(name, provider)`
- `require("tau").TauSetSessionStorage(name)`
- `local backend, active_name = require("tau").TauGetSessionStorage()`

A provider must implement: **`list_sessions(cwd)`**, **`load_session(cwd, session_id)`**, **`save_session(session)`**, **`delete_session(cwd, session_id)`**. The built-in backend stores **`.jsonl`** files (header line + one JSON object per message).

---

## Session branching (Lua)

| Function | Description |
|----------|-------------|
| `require("tau").TauSessionTree()` | Choose a user/assistant message and fork from it |
| `require("tau").TauSessionFork(index?)` | Fork from message index (default: last message) |
| `require("tau").TauSessionClone()` | Duplicate the current session (new id, copied messages) |

---

## Providers

Providers implement streaming and non-streaming chat against an HTTP API and register models/auth metadata with **`tau.plugin`**.

- Register from your config: `require("tau").register_provider(require("myplugin.provider"))`, or load a module from `setup({ plugins = { "myplugin.provider" } })` that calls `register` on the shared registry.
- Set `provider.name` (and optional `provider.model`, `provider.base_url`) in `setup` to match the `name` exported by your provider plugin.

---

## Tools (agent capabilities)

Defined in [`lua/tau/tools.lua`](lua/tau/tools.lua). The model receives a schema; execution goes through **`tau.tools.execute`**. Capabilities include (among others) **read**, **write**, **edit**, **bash**, **open_buffers**, **read_buffer**, **workspace_diagnostics**, and related Neovim/workspace helpers. Output is capped (lines/bytes) with truncation behavior documented in tool descriptions.

---

## Mentions & attachments

- **`:TauPromptContext`** / `require("tau").insert_prompt_context({})` — insert context from files or selection according to the active mention provider.
- **`require("tau").register_mention_provider(...)`** — plug in custom resolvers.
- **`require("tau").attach_image(path)`** — image attachments where the active provider supports them.

---

## Troubleshooting

1. Run **`:TauCheckHealth`** — verifies Neovim version, `curl`, provider plugin, and credentials.
2. Confirm **`require("tau.config").get().provider.name`** matches a loaded provider and that credentials are configured (env vars and/or `:TauLogin` as documented for that provider).
3. If session titles or names look wrong, check **`:TauSessionInfo`** and the JSONL file under **`stdpath("state")/tau/sessions/`**.

---

## Repository layout (reference)

| Path | Role |
|------|------|
| `plugin/tau.lua` | User commands |
| `lua/tau/init.lua` | Public `require("tau")` API |
| `lua/tau/config.lua` | Defaults and `setup` merge |
| `lua/tau/ui/` | Layout, history, prompt, completion, zen |
| `lua/tau/dispatcher.lua` | Tool loop + streaming orchestration |
| `lua/tau/session*.lua` | Sessions, storage, titles, display |
| `lua/tau/tools.lua` | Tool definitions and execution |
| `lua/tau/agents.lua` | AGENTS.md loading |
| `lua/tau/mentions/` | Mention providers |
| `lua/plugin/` | Provider modules (e.g. [Opencode](lua/plugin/opencode-go/README.md)) |

---

## Contributing & AI use

See [`AI_USAGE.md`](AI_USAGE.md) for expectations around AI-assisted contributions.
