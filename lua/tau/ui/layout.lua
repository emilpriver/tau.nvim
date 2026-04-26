local M = {}

local LAYOUT_NS = vim.api.nvim_create_namespace("tau_layout")

function M.create_side(config)
  local position = config.layout.side.position
  local width = config.layout.side.width
  local original_win = vim.api.nvim_get_current_win()

  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()

  if position == "right" then
    vim.cmd("wincmd L")
  end

  vim.api.nvim_win_set_width(win, width)

  vim.cmd("split")
  local prompt_win = vim.api.nvim_get_current_win()
  local history_win = vim.fn.win_getid(vim.fn.winnr("#"))

  vim.api.nvim_win_set_height(prompt_win, math.max(8, math.floor(vim.o.lines * 0.2)))

  return {
    history = history_win,
    prompt = prompt_win,
    layout = "side",
    main = win,
    original_win = original_win,
  }
end

function M.create_float(config)
  local float_cfg = config.layout.float
  local width = math.floor(vim.o.columns * float_cfg.width)
  local height = math.floor(vim.o.lines * float_cfg.height)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  local original_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    border = float_cfg.border,
    style = "minimal",
    title = " tau ",
    title_pos = "center",
  })

  vim.cmd("split")
  local prompt_win = vim.api.nvim_get_current_win()
  local history_win = vim.fn.win_getid(vim.fn.winnr("#"))

  vim.api.nvim_win_set_height(prompt_win, math.max(6, math.floor(height * 0.25)))

  return {
    history = history_win,
    prompt = prompt_win,
    layout = "float",
    main = win,
    float_buf = buf,
    original_win = original_win,
  }
end

function M.close(layout)
  if not layout then
    return
  end

  if layout.layout == "float" and layout.float_buf then
    pcall(vim.api.nvim_buf_delete, layout.float_buf, { force = true })
  end

  local wins = {}
  if layout.history and vim.api.nvim_win_is_valid(layout.history) then
    table.insert(wins, layout.history)
  end
  if layout.prompt and vim.api.nvim_win_is_valid(layout.prompt) then
    table.insert(wins, layout.prompt)
  end

  for _, win in ipairs(wins) do
    pcall(vim.api.nvim_win_close, win, true)
  end
end

function M.is_open(layout)
  if not layout then
    return false
  end
  if not layout.history or not vim.api.nvim_win_is_valid(layout.history) then
    return false
  end
  if not layout.prompt or not vim.api.nvim_win_is_valid(layout.prompt) then
    return false
  end
  return true
end

function M.focus_history(layout)
  if layout and layout.history and vim.api.nvim_win_is_valid(layout.history) then
    vim.api.nvim_set_current_win(layout.history)
  end
end

function M.focus_prompt(layout)
  if layout and layout.prompt and vim.api.nvim_win_is_valid(layout.prompt) then
    vim.api.nvim_set_current_win(layout.prompt)
  end
end

return M
