local M = {}

local ZEN_NS = vim.api.nvim_create_namespace("tua_zen")

M.active = false
M.original_wins = {}

function M.toggle()
  if M.active then
    M.exit()
  else
    M.enter()
  end
end

function M.enter()
  if M.active then
    return
  end

  local ui = require("tua.ui")
  if not ui.active then
    vim.notify("Open chat first with :Tau", vim.log.levels.WARN)
    return
  end

  M.original_wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= ui.active.layout_state.history and win ~= ui.active.layout_state.prompt then
      table.insert(M.original_wins, win)
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end

  local prompt_win = ui.active.layout_state.prompt
  if vim.api.nvim_win_is_valid(prompt_win) then
    vim.api.nvim_set_current_win(prompt_win)
    vim.cmd("resize 20")
  end

  vim.cmd("highlight TuaZenBackdrop guibg=#1a1a1a ctermbg=234")
  local backdrop = vim.api.nvim_create_buf(false, true)
  local backdrop_win = vim.api.nvim_open_win(backdrop, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    col = 0,
    row = 0,
    style = "minimal",
    focusable = false,
    zindex = 1,
  })
  vim.wo[backdrop_win].winhighlight = "Normal:TuaZenBackdrop"
  vim.wo[backdrop_win].winblend = 30

  M.backdrop_win = backdrop_win
  M.active = true

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    M.exit()
  end, { buffer = ui.active.prompt_buf, silent = true, desc = "Exit zen mode" })
end

function M.exit()
  if not M.active then
    return
  end

  if M.backdrop_win and vim.api.nvim_win_is_valid(M.backdrop_win) then
    vim.api.nvim_win_close(M.backdrop_win, true)
  end

  M.backdrop_win = nil
  M.active = false

  vim.notify("Zen mode exited", vim.log.levels.INFO)
end

return M
