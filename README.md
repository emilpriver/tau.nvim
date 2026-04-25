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

Call `require("tau").setup({ ... })` once. Options are **deep-merged** into the defaults in [`lua/tau/config.lua`](lua/tau/config.lua). You can inspect the result with `require("tau.config").get()`.

### Setup-only

| Option | Type | Description |
|--------|------|-------------|
| `plugins` | `string[]` | Lua module names passed to `tau.plugin.init`. Each module should register a provider (or perform setup side effects). Example: `{ "plugin.opencode-go" }` for the bundled Opencode provider. |

`mention_plugins` is merged into config and passed to `tau.mentions.init` (same table you set under `setup({ mention_plugins = ... })`).

### `provider`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | `"opencode"` | Active provider id (must match a registered provider). |
| `model` | string?, nil | `nil` | Default model id; may be set by provider or `:TauModel`. |
| `base_url` | string?, nil | `nil` | Optional API base URL when the provider supports it. |

### `models`

| Type | Default | Description |
|------|---------|-------------|
| `table?`, `nil` | `nil` | If set, a list of **filters** for `:TauModel` / internal model resolution. Each entry is either a **string** (substring match, case-insensitive) or a table: `{ match = "..." }`, optionally `exact = true` (require exact id) or `latest = true` (pick latest among matches). If `nil`, all models returned by the provider are used. |

### `mention_provider` / `mention_plugins`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mention_provider` | string | `"files"` | Name of the active mention provider module under `tau.mentions`. |
| `mention_plugins` | table | `{}` | Extra mention provider modules or options (see `tau.mentions`). |

### `layout`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `default` | string | `"side"` | Initial layout: `"side"` or `"float"`. Overridden by `:Tau layout=float` etc. |
| `layout.side.position` | string | `"right"` | `"left"` or `"right"` for the chat split. |
| `layout.side.width` | number | `80` | Width of the side layout (columns). |
| `layout.side.panels.history.winbar` | bool | `true` | Show winbar on the history window. |
| `layout.side.panels.prompt.winbar` | bool | `true` | Show winbar on the prompt window. |
| `layout.side.panels.attachments.winbar` | bool | `true` | Winbar toggle for attachments panel (when used). |
| `layout.float.width` | number | `0.6` | Float width as a fraction of `vim.o.columns`. |
| `layout.float.height` | number | `0.8` | Float height as a fraction of `vim.o.lines`. |
| `layout.float.border` | string | `"rounded"` | `:help nvim_open_win` border style for float layout. |

### `panels`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `panels.history.title` | string | `"π"` | Label metadata (reserved for UI that reads `config.panels`). |
| `panels.prompt.title` | string | `"Prompt"` | Same. |
| `panels.attachments.title` | string | `"attachments"` | Same. |

### `labels`

Icons / prefixes for history rendering (Nerd Font glyphs by default):

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

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `spinner` | string | `"robot"` | Spinner preset name passed to `tau.ui.spinner` while waiting. |
| `show_thinking` | bool | `false` | When true, stream reasoning/thinking blocks in the history (if the provider sends them). Toggled with `:TauToggleThinking`. |
| `expand_startup_details` | bool | `true` | Present in defaults; not read by core yet. |

### `dialog`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `border` | string | `"rounded"` | Used for some floating editors (e.g. queue message edit) when set. |
| `max_width` | number | `0.8` | Reserved. |
| `max_height` | number | `0.8` | Reserved. |
| `indicator` | string | `"▸"` | Reserved. |
| `dialog.keys.confirm` / `cancel` / `next` / `prev` | any | `nil` | Reserved keybinding hooks. |

### `zen`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `width` | any | `nil` | Reserved. |
| `zen.keys.toggle` / `exit` | any | `nil` | Reserved. |

Zen mode currently uses a hardcoded `<Esc>` buffer mapping to exit.

### `statusline`

Nested `layout` (left/right segment names) and `components` (icons, token warn/error thresholds, etc.) are **defined in defaults** for a richer statusline; the current prompt statusline builder uses a simpler hardcoded format and does not read this tree yet.

### `verbs`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `use_defaults` | bool | `true` | Reserved. |
| `pairs` | table | `{}` | Reserved. |

### `on_widget`

| Type | Default | Description |
|------|---------|-------------|
| `function?`, `nil` | `nil` | Reserved callback hook. |

### `queue`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Reserved; queue behavior is always available when the UI submits while busy. |
| `max_size` | number | `50` | Reserved cap (not enforced in core yet). |
| `processing` | string | `"sequential"` | Matches current behavior (one queued turn after another). |
| `show_indicator` | bool | `true` | Reserved. |
| `persist` | bool | `true` | Queue is stored on `session.queue` and in session JSONL; not gated off this flag yet. |

### `session`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `auto_llm_title` | bool | `false` | After the first assistant reply, call the LLM once to set a short tab title (if name still empty). |
| `title_max_chars_excerpt` | number | `4000` | Max chars of transcript sent into the title prompt. |
| `title_max_length` | number | `56` | Max length of generated title string. |
| `title_model` | string?, nil | `nil` | Optional model id for title generation; defaults to the session/provider model. |

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
