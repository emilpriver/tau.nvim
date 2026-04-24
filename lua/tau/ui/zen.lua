local M = {}

M.active = false
M.saved = nil

local function prune_shape(node, excl)
  if type(node) == "number" then
    if excl[node] then
      return nil
    end
    local buf = vim.api.nvim_win_get_buf(node)
    local pos = vim.api.nvim_win_get_cursor(node)
    return { "leaf", buf, pos }
  end
  local dir = node[1]
  local kids = {}
  for i = 2, #node do
    local p = prune_shape(node[i], excl)
    if p ~= nil then
      kids[#kids + 1] = p
    end
  end
  if #kids == 0 then
    return nil
  end
  if #kids == 1 then
    return kids[1]
  end
  local out = { dir }
  for _, k in ipairs(kids) do
    out[#out + 1] = k
  end
  return out
end

local function restore_shape(win, node)
  if node[1] == "leaf" then
    pcall(vim.api.nvim_win_set_buf, win, node[2])
    pcall(vim.api.nvim_win_set_cursor, win, node[3])
    return
  end
  local dir = node[1]
  local kids = {}
  for i = 2, #node do
    kids[#kids + 1] = node[i]
  end
  if #kids == 1 then
    restore_shape(win, kids[1])
    return
  end
  if dir == "col" then
    vim.api.nvim_set_current_win(win)
    vim.cmd("leftabove split")
    local top = vim.api.nvim_get_current_win()
    local bot = vim.fn.win_getid(vim.fn.winnr("#"))
    restore_shape(top, kids[1])
    if #kids == 2 then
      restore_shape(bot, kids[2])
    else
      local rest = { "col" }
      for j = 2, #kids do
        rest[#rest + 1] = kids[j]
      end
      restore_shape(bot, rest)
    end
  elseif dir == "row" then
    vim.api.nvim_set_current_win(win)
    vim.cmd("leftabove vsplit")
    local left = vim.api.nvim_get_current_win()
    local right = vim.fn.win_getid(vim.fn.winnr("#"))
    restore_shape(left, kids[1])
    if #kids == 2 then
      restore_shape(right, kids[2])
    else
      local rest = { "row" }
      for j = 2, #kids do
        rest[#rest + 1] = kids[j]
      end
      restore_shape(right, rest)
    end
  end
end

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

  local ui = require("tau.ui")
  if not ui.active then
    vim.notify("Open chat first with :Tau", vim.log.levels.WARN)
    return
  end

  local ls = ui.active.layout_state
  if not vim.api.nvim_win_is_valid(ls.history) or not vim.api.nvim_win_is_valid(ls.prompt) then
    return
  end

  if ls.layout == "float" then
    vim.notify("Zen mode is only available for side layout", vim.log.levels.WARN)
    return
  end

  local cfg = ui.active.config.layout.side
  local prompt_buf = ui.active.prompt_buf

  local excl = { [ls.history] = true, [ls.prompt] = true }
  local cur = vim.api.nvim_get_current_win()
  local focus_saved = nil
  if not excl[cur] and vim.api.nvim_win_is_valid(cur) then
    focus_saved = { buf = vim.api.nvim_win_get_buf(cur), pos = vim.api.nvim_win_get_cursor(cur) }
  end

  M.saved = {
    layout_shape = prune_shape(vim.fn.winlayout(), excl),
    focus = focus_saved,
    cursor = vim.api.nvim_win_get_cursor(ls.prompt),
    tau_position = cfg.position,
    tau_width = cfg.width,
  }

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and not excl[win] then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end

  vim.api.nvim_set_current_win(ls.history)
  vim.cmd("resize 999")

  vim.api.nvim_set_current_win(ls.prompt)
  local prompt_h = math.max(8, math.floor(vim.o.lines * 0.22))
  vim.api.nvim_win_set_height(ls.prompt, prompt_h)

  vim.api.nvim_set_current_win(ls.prompt)
  vim.cmd("startinsert!")

  M.active = true

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    M.exit()
  end, { buffer = prompt_buf, silent = true, desc = "Exit zen mode" })
end

function M.exit()
  if not M.active then
    return
  end

  local ui = require("tau.ui")

  if not ui.active then
    M.saved = nil
    M.active = false
    return
  end

  local ls = ui.active.layout_state
  local prompt_buf = ui.active.prompt_buf

  local prompt_text = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(ls.prompt)

  pcall(vim.keymap.del, { "n", "i" }, "<Esc>", { buffer = prompt_buf })

  if vim.api.nvim_win_is_valid(ls.prompt) then
    pcall(vim.api.nvim_win_close, ls.prompt, true)
  end

  if M.saved.layout_shape then
    vim.api.nvim_set_current_win(ls.history)
    if M.saved.tau_position == "right" then
      vim.cmd("leftabove vsplit")
    else
      vim.cmd("rightbelow vsplit")
    end
    local editor_root = vim.api.nvim_get_current_win()
    restore_shape(editor_root, M.saved.layout_shape)
  end

  vim.api.nvim_set_current_win(ls.history)
  pcall(vim.api.nvim_win_set_width, ls.history, M.saved.tau_width)

  vim.api.nvim_set_current_win(ls.history)
  vim.cmd("split")
  local new_prompt = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_prompt, prompt_buf)
  pcall(vim.api.nvim_win_set_height, new_prompt, math.max(8, math.floor(vim.o.lines * 0.2)))

  pcall(function()
    vim.wo[ls.history].winfixbuf = true
    vim.wo[new_prompt].winfixbuf = true
  end)

  vim.wo[ls.history].wrap = true
  vim.wo[ls.history].linebreak = true
  vim.wo[ls.history].cursorline = false
  vim.wo[ls.history].number = false
  vim.wo[ls.history].relativenumber = false

  vim.wo[new_prompt].wrap = true
  vim.wo[new_prompt].number = false
  vim.wo[new_prompt].relativenumber = false

  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, prompt_text)
  pcall(vim.api.nvim_win_set_cursor, new_prompt, cursor)

  local config = ui.active.config
  if config.layout.side.panels.history.winbar then
    pcall(function()
      local info_str = require("tau.session_display").winbar_text(ui.active.session)
      vim.wo[ls.history].winbar = " History " .. info_str
    end)
  end
  if config.layout.side.panels.prompt.winbar then
    pcall(function()
      local info_str = require("tau.session_display").winbar_text(ui.active.session)
      vim.wo[new_prompt].winbar = " Prompt " .. info_str
    end)
  end

  local restored_editor = ls.original_win
  if M.saved.focus then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= ls.history and w ~= new_prompt and vim.api.nvim_win_get_buf(w) == M.saved.focus.buf then
        vim.api.nvim_set_current_win(w)
        pcall(vim.api.nvim_win_set_cursor, w, M.saved.focus.pos)
        restored_editor = w
        break
      end
    end
  end
  if not restored_editor or not vim.api.nvim_win_is_valid(restored_editor) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= ls.history and w ~= new_prompt then
        restored_editor = w
        break
      end
    end
  end

  local main_win = ls.history
  if ls.main and vim.api.nvim_win_is_valid(ls.main) then
    main_win = ls.main
  end

  ui.active.layout_state = {
    history = ls.history,
    prompt = new_prompt,
    layout = "side",
    main = main_win,
    original_win = restored_editor,
  }

  M.saved = nil
  M.active = false
end

return M
