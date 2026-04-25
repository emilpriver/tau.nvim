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

## Configuration

Call `require("tau").setup({ ... })` once. Options are **deep-merged** into the defaults in [`lua/tau/config.lua`](lua/tau/config.lua).

### Setup-only

| Option | Type | Description |
|--------|------|-------------|
| `plugins` | `string[]` | Module names for `tau.plugin.init`. |

`mention_plugins` is passed to `tau.mentions.init`.

### `provider`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | `"opencode"` | Provider id. |
| `model` | string?, nil | `nil` | Default model id. |
| `base_url` | string?, nil | `nil` | Optional API base URL. |

### `models`

| Type | Default | Description |
|------|---------|-------------|
| `table?`, `nil` | `nil` | Model list filters: string or `{ match = "..." }` with optional `exact` or `latest`. |

### `mention_provider` / `mention_plugins`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mention_provider` | string | `"files"` | Active mention provider name. |
| `mention_plugins` | table | `{}` | Extra mention providers. |

### `layout`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default` | string | `"side"` | `"side"` or `"float"`. |
| `layout.side.position` | string | `"right"` | `"left"` or `"right"`. |
| `layout.side.width` | number | `80` | Side layout width (columns). |
| `layout.side.panels.history.winbar` | bool | `true` | History winbar. |
| `layout.side.panels.prompt.winbar` | bool | `true` | Prompt winbar. |
| `layout.side.panels.attachments.winbar` | bool | `true` | Attachments winbar. |
| `layout.float.width` | number | `0.6` | Float width fraction of `vim.o.columns`. |
| `layout.float.height` | number | `0.8` | Float height fraction of `vim.o.lines`. |
| `layout.float.border` | string | `"rounded"` | Float window border. |

### `panels`

| Key | Type | Default |
|-----|------|---------|
| `panels.history.title` | string | `"π"` |
| `panels.prompt.title` | string | `"Prompt"` |
| `panels.attachments.title` | string | `"attachments"` |

### `labels`

History prefixes:

| Key | Default |
|-----|---------|
| `user_message` | `` |
| `agent_response` | `󰚩` |
| `system_error` | `󱚟` |
| `tool` | `󰻂` |
| `tool_success` | `` |
| `tool_failure` | `` |
| `steer_message` | `󰾘` |
| `queued_message` | `󰗼` |
| `follow_up_message` | `󱇼` |
| `thinking` | `󰟶` |
| `attachment` | `` |
| `attachments` | `` |
| `error` | `󰘨 󱚟 󱔁 ` |

### General UI

| Key | Type | Default |
|-----|------|---------|
| `spinner` | string | `"robot"` |
| `show_thinking` | bool | `false` |
| `expand_startup_details` | bool | `true` |

### `dialog`

| Key | Type | Default |
|-----|------|---------|
| `border` | string | `"rounded"` |
| `max_width` | number | `0.8` |
| `max_height` | number | `0.8` |
| `indicator` | string | `"▸"` |
| `keys.confirm` / `cancel` / `next` / `prev` | any | `nil` |

### `zen`

| Key | Type | Default |
|-----|------|---------|
| `width` | any | `nil` |
| `keys.toggle` / `exit` | any | `nil` |

### `statusline`

| Key |
|-----|
| `layout.left`, `layout.right` |
| `components` (tokens, cache, cost, compaction, context, attention, model, thinking) |

### `verbs`

| Key | Type | Default |
|-----|------|---------|
| `use_defaults` | bool | `true` |
| `pairs` | table | `{}` |

### `on_widget`

| Type | Default |
|------|---------|
| `function?` | `nil` |

### `queue`

| Key | Type | Default |
|-----|------|---------|
| `enabled` | bool | `true` |
| `max_size` | number | `50` |
| `processing` | string | `"sequential"` |
| `show_indicator` | bool | `true` |
| `persist` | bool | `true` |

### `session`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `auto_llm_title` | bool | `false` | LLM-generated session name after first reply. |
| `title_max_chars_excerpt` | number | `4000` | Excerpt size for title prompt. |
| `title_max_length` | number | `56` | Max title length. |
| `title_model` | string?, nil | `nil` | Model for title generation. |

### Example

```lua
require("tau").setup({
  plugins = { "plugin.opencode-go" },
  provider = {
    name = "opencode",
    model = "gpt-4.1",
  },
  layout = {
    default = "side",
    side = { position = "right", width = 84 },
    float = { width = 0.65, height = 0.85, border = "double" },
  },
  show_thinking = true,
  mention_provider = "files",
  session = {
    auto_llm_title = true,
    title_model = "your-small-model-id",
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

## Contributing & AI use

See [`AI_USAGE.md`](AI_USAGE.md) for expectations around AI-assisted contributions.
