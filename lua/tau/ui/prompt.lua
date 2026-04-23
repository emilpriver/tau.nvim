local M = {}

local PROMPT_NS = vim.api.nvim_create_namespace("tau_prompt")

function M.create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "tau-prompt"
  return buf
end

function M.get_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.clear(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

function M.set_keymaps(buf, callbacks)
  callbacks = callbacks or {}

  local opts = { buffer = buf, silent = true }

  vim.keymap.set({ "n", "i" }, "<C-CR>", function()
    local text = M.get_text(buf)
    if text and text:gsub("%s", "") ~= "" then
      if callbacks.on_submit then
        callbacks.on_submit(text)
      end
      M.clear(buf)
    end
  end, vim.tbl_extend("force", opts, { desc = "Submit prompt" }))

  vim.keymap.set("n", "<CR>", function()
    local text = M.get_text(buf)
    if text and text:gsub("%s", "") ~= "" then
      if callbacks.on_submit then
        callbacks.on_submit(text)
      end
      M.clear(buf)
    end
  end, vim.tbl_extend("force", opts, { desc = "Submit prompt" }))

  vim.keymap.set("i", "<CR>", "<CR>", opts)

  vim.keymap.set("n", "q", function()
    if callbacks.on_close then
      callbacks.on_close()
    end
  end, vim.tbl_extend("force", opts, { desc = "Close chat" }))

  vim.keymap.set("n", "<Esc>", function()
    if callbacks.on_close then
      callbacks.on_close()
    end
  end, vim.tbl_extend("force", opts, { desc = "Close chat" }))

  vim.keymap.set({ "n", "i" }, "<C-h>", function()
    if callbacks.on_focus_history then
      callbacks.on_focus_history()
    end
  end, vim.tbl_extend("force", opts, { desc = "Focus history" }))

  vim.keymap.set({ "n", "i" }, "<C-z>", function()
    if callbacks.on_zen then
      callbacks.on_zen()
    end
  end, vim.tbl_extend("force", opts, { desc = "Toggle zen mode" }))


end

function M.set_completefunc(buf)
  vim.bo[buf].completefunc = "v:lua.require'tau.ui.complete'.completefunc"
end

function M.set_statusline(win, text)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  text = text:gsub("[^%x20-%x7E]", "")
  pcall(function()
    vim.api.nvim_win_call(win, function()
      vim.wo.statusline = text
    end)
  end)
end

function M.build_statusline(session, config)
  if not session then
    return " tau "
  end

  local parts = {}
  local model = session.model or "default"
  table.insert(parts, " " .. model .. " ")

  local thinking = require("tau.models").get_thinking_level()
  if thinking and thinking ~= "off" then
    table.insert(parts, "[think:" .. thinking .. "]")
  end

  local ctx = require("tau.state").get_token_info()
  if ctx then
    local pct = math.floor(ctx.ratio * 100)
    table.insert(parts, string.format(" %d%% (%d/%d)", pct, ctx.used, ctx.limit))
  end

  return table.concat(parts, " ")
end

return M
