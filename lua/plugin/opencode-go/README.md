# Opencode provider (`plugin.opencode-go`)

Tau provider for the **Opencode** HTTP API (`/chat/completions`, SSE streaming, tools, optional reasoning). The module name for `require` and for `setup({ plugins = ... })` is **`plugin.opencode-go`** (Neovim loads `lua/plugin/opencode-go/init.lua`).

## Activate in tau.nvim

1. Add the module to **`setup`** so `tau.plugin` loads and registers the provider:

```lua
require("tau").setup({
  plugins = { "plugin.opencode-go" },
  provider = {
    name = "opencode",
    model = "kimi-k2.5",
  },
})
```

2. `provider.name` must be **`opencode`** — that is the `M.name` exported by this plugin and must match [`lua/tau/config.lua`](../../tau/config.lua) defaults if you rely on them.

3. Optional: override the API base (otherwise the default below is used):

```lua
provider = {
  name = "opencode",
  model = "kimi-k2.5",
  base_url = "https://opencode.ai/zen/go/v1",
},
```

## API key

The provider reads **`OPENCODE_API_KEY`** from the environment **or** a key stored via Tau auth.

| Method | What to do |
|--------|------------|
| Environment | `export OPENCODE_API_KEY=...` in the shell that starts Neovim |
| Tau auth | `:TauLogin opencode` and paste the key when prompted (keys are stored where `tau.auth` writes; see health check) |

Create or rotate keys in the Opencode account UI: [https://opencode.ai/settings](https://opencode.ai/settings)

## Models

Registered in code (also used as fallbacks when listing models fails):

- `kimi-k2.5`, `kimi-k2.6`
- `glm-5`, `glm-5.1`
- `mimo-v2-omni`, `mimo-v2-pro`

`:TauRefreshModels` / model picker use **`GET /models`** on the same base URL when credentials are valid.

Default model if unset: **`kimi-k2.5`**.

## Health and troubleshooting

Run **`:TauCheckHealth`**. It checks for the provider plugin, `curl`, and whether **`OPENCODE_API_KEY`** or an auth-file entry exists for **`opencode`**.

## Implementation notes

- Chat path: **`base_url` + `/chat/completions`** (streaming uses SSE; non-streaming uses the same endpoint with `stream: false`).
- Attachments: images as `data:` URLs in multimodal user messages when using this provider’s `build_user_message` path through Tau attachments.
