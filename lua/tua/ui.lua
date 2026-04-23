local M = {}

local layout = require("tua.ui.layout")
local history = require("tua.ui.history")
local prompt = require("tua.ui.prompt")
local spinner = require("tua.ui.spinner")
local complete = require("tua.ui.complete")
local queue = require("tua.ui.queue")
local zen = require("tua.ui.zen")

M.active = nil

function M.open(opts)
  opts = opts or {}
  local config = require("tua.config").get()
  local state = require("tua.state")

  if M.active and layout.is_open(M.active.layout_state) then
    layout.focus_prompt(M.active.layout_state)
    return M.active
  end

  local session = state.get_session()
  if not session then
    require("tua").new_session()
    session = state.get_session()
  end

  history.setup_highlights()

  local layout_mode = opts.layout or config.layout.default
  local layout_state
  if layout_mode == "float" then
    layout_state = layout.create_float(config)
  else
    layout_state = layout.create_side(config)
  end

  local hist_buf = history.create_buffer()
  local prompt_buf = prompt.create_buffer()

  vim.api.nvim_win_set_buf(layout_state.history, hist_buf)
  vim.api.nvim_win_set_buf(layout_state.prompt, prompt_buf)

  vim.wo[layout_state.history].wrap = true
  vim.wo[layout_state.history].linebreak = true
  vim.wo[layout_state.history].cursorline = false
  vim.wo[layout_state.history].number = false
  vim.wo[layout_state.history].relativenumber = false

  vim.wo[layout_state.prompt].wrap = true
  vim.wo[layout_state.prompt].number = false
  vim.wo[layout_state.prompt].relativenumber = false

  if config.layout.side.panels.history.winbar then
    vim.wo[layout_state.history].winbar = " History "
  end
  if config.layout.side.panels.prompt.winbar then
    vim.wo[layout_state.prompt].winbar = " Prompt "
  end

  history.refresh(hist_buf, session, config)
  history.scroll_to_bottom(hist_buf, layout_state.history)

  prompt.set_keymaps(prompt_buf, {
    on_submit = function(text)
      M.on_submit(text)
    end,
    on_close = function()
      M.close()
    end,
    on_focus_history = function()
      layout.focus_history(layout_state)
    end,
    on_zen = function()
      zen.toggle()
    end,
  })

  prompt.set_completefunc(prompt_buf)

  M.active = {
    layout_state = layout_state,
    hist_buf = hist_buf,
    prompt_buf = prompt_buf,
    session = session,
    config = config,
    spinner_handle = nil,
    is_busy = false,
  }

  layout.focus_prompt(layout_state)

  return M.active
end

function M.close()
  if not M.active then
    return
  end

  zen.exit()

  if M.active.spinner_handle then
    M.active.spinner_handle.stop()
    M.active.spinner_handle = nil
  end

  layout.close(M.active.layout_state)
  M.active = nil
end

function M.toggle(opts)
  if M.active and layout.is_open(M.active.layout_state) then
    M.close()
  else
    M.open(opts)
  end
end

function M.refresh()
  if not M.active then
    return
  end

  local session = require("tua.state").get_session()
  history.refresh(M.active.hist_buf, session, M.active.config)
  history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
end

function M.append_message(msg)
  if not M.active then
    return
  end

  local lines, extmarks = history.render_message(msg, M.active.config)
  history.append_lines(M.active.hist_buf, lines)

  local offset = vim.api.nvim_buf_line_count(M.active.hist_buf) - #lines
  for _, em in ipairs(extmarks) do
    vim.api.nvim_buf_add_highlight(M.active.hist_buf, vim.api.nvim_create_namespace("tua_history"), em.hl, em.line + offset, 0, -1)
  end

  history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
end

function M.on_submit(text)
  if not M.active then
    return
  end

  if M.active.is_busy then
    queue.push(text, "steer")
    M.append_message({
      role = "user",
      content = text,
      _queued = true,
      _queue_type = "steer",
    })
    M.refresh()
    return
  end

  local session = require("tua.state").get_session()
  if not session then
    vim.notify("No active session", vim.log.levels.ERROR)
    return
  end

  local expanded = complete.expand_mentions(text)
  local invalid = complete.validate_mentions(expanded)
  if #invalid > 0 then
    vim.notify("Invalid file mentions: " .. table.concat(invalid, ", "), vim.log.levels.WARN)
  end

  local hist = require("tua.history")
  table.insert(session.messages, hist.user(expanded))

  M.refresh()
  M.start_turn()
end

function M.start_turn()
  if not M.active then
    return
  end

  local session = require("tua.state").get_session()
  if not session then
    return
  end

  M.active.is_busy = true
  queue.set_busy(true)
  M.start_busy()

  local provider = session.provider or require("tua.config").get().provider.name

  require("tua.dispatcher").run_turn_streaming(provider, session.messages, {
    model = session.model,
    thinking_level = require("tua.models").get_thinking_level(),
    on_text = function(chunk)
      if not M.active then
        return
      end
    end,
    on_thinking = function(chunk)
      if not M.active then
        return
      end
    end,
    on_tool_start = function(name, input, id)
      if not M.active then
        return
      end
    end,
    on_tool_result = function(id, name, result, is_error)
      if not M.active then
        return
      end
    end,
    on_done = function()
      M.finish_turn()
    end,
  })
end

function M.finish_turn()
  if not M.active then
    return
  end

  M.active.is_busy = false
  queue.set_busy(false)
  M.stop_busy()
  M.refresh()
  require("tua.state").update_session_tokens()

  if queue.size() > 0 then
    local next_msg = queue.pop()
    if next_msg then
      vim.defer_fn(function()
        M.on_submit(next_msg.text)
      end, 100)
    end
  end
end

function M.start_busy()
  if not M.active or M.active.spinner_handle then
    return
  end

  local config = M.active.config
  local start_time = vim.fn.localtime()

  M.active.spinner_handle = spinner.start({
    spinner = config.spinner,
    on_update = function(frame)
      if not M.active or not M.active.layout_state then
        return
      end
      local elapsed = vim.fn.localtime() - start_time
      local mins = math.floor(elapsed / 60)
      local secs = elapsed % 60
      local time_str = string.format("%02d:%02d", mins, secs)
      local text = string.format(" [%s] Working... %s ", frame, time_str)
      pcall(function()
        vim.wo[M.active.layout_state.prompt].winbar = text
      end)
    end,
  })
end

function M.stop_busy()
  if not M.active then
    return
  end

  if M.active.spinner_handle then
    M.active.spinner_handle.stop()
    M.active.spinner_handle = nil
  end

  pcall(function()
    vim.wo[M.active.layout_state.prompt].winbar = " Prompt "
  end)
end

function M.focus_history()
  if M.active then
    layout.focus_history(M.active.layout_state)
  end
end

function M.focus_prompt()
  if M.active then
    layout.focus_prompt(M.active.layout_state)
  end
end

function M.scroll_history(direction, lines_count)
  if not M.active then
    return
  end
  local win = M.active.layout_state.history
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  lines_count = lines_count or 3
  local current = vim.api.nvim_win_get_cursor(win)
  local delta = direction == "up" and -lines_count or lines_count
  local new_row = math.max(1, current[1] + delta)

  vim.api.nvim_win_set_cursor(win, { new_row, 0 })
end

function M.scroll_history_to_bottom()
  if not M.active then
    return
  end
  history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
end

return M
