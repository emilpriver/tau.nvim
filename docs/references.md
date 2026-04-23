## Design Decisions to Make

1. **HTTP client**: `vim.system()` with `curl` vs. pure Lua HTTP via `vim.loop` TCP sockets vs. `lua-curl`
2. **JSON parsing**: `vim.json` (built-in, Neovim 0.9+) is sufficient
3. **Async model**: `vim.loop` callbacks or `vim.system()` async — no coroutines for simplicity, or use `vim.uv` for everything
4. **Token counting**: Approximate (chars / 4) vs. provider-specific tiktoken vs. API-returned usage
5. **Session format**: JSONL (line-delimited JSON) for streaming compatibility vs. single JSON file
6. **Diff engine**: Use `vim.diff()` (built-in xdiff) or shell `diff`/`git diff`
7. **Streaming**: SSE parser for OpenAI-compatible streaming responses
8. **Permission system**: Build-in vs. extension-only (pi.nvim chose extension-only, but a native plugin could ship defaults)
9. **Compaction**: Call the LLM itself to summarize, or use a separate summarization model
10. **Extension system**: Lua modules loaded from config dir vs. external plugin dependencies

---

## Key References

- **pi.dev** — Core agent philosophy, tool design, session management, extension model
- **pi.nvim** — UI patterns, panel layout, diff review protocol, attention queue, statusline design, completion integration
- **CopilotChat.nvim** — Existing Neovim chat plugin for UI patterns
- **Mini.ai** / **Mini.diff** — Neovim plugin patterns for diff and UI
