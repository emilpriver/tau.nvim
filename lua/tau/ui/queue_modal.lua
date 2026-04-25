local M = {}

local queue = require("tau.ui.queue")

local function truncate(str, max_len)
  if not str then
    return ""
  end
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

local function format_preview(text, max_len)
  text = text:gsub("\n", " ")
  text = text:gsub("%s+", " ")
  return truncate(text, max_len)
end

local function get_queue_items()
  local all = queue.get_all()
  local items = {}
  for i, item in ipairs(all) do
    table.insert(items, {
      idx = i,
      id = item.id,
      text = item.text,
      type = item.type or "steer",
      timestamp = item.timestamp,
    })
  end
  return items
end

local function persist_queue()
  local session = require("tau.state").get_session()
  if session then
    queue.sync_to_session(session)
    require("tau.session").TauSessionAutosave(session)
  end
end

local function item_label(item, i)
  local ts = os.date("%H:%M", item.timestamp) or "??:??"
  local preview = format_preview(item.text, 52)
  return string.format("%d  [%s] %s  %s", i, item.type, ts, preview)
end

local function open_editor(item, on_save)
  local lines = vim.split(item.text, "\n", { plain = true })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = "tau-prompt"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local cfg = require("tau.config").get()
  local border = (cfg.dialog and cfg.dialog.border) or (cfg.layout.float and cfg.layout.float.border) or "rounded"

  local width = 80
  local height = math.max(10, math.min(#lines + 4, math.floor(vim.o.lines * 0.5)))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = border,
    title = " Edit Queued Message ",
    title_pos = "center",
    style = "minimal",
    focusable = true,
  })

  vim.cmd("startinsert")

  local function save_and_close()
    local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_text = table.concat(new_lines, "\n")
    if new_text and new_text:gsub("%s", "") ~= "" then
      on_save(new_text)
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<CR>", function()
    save_and_close()
  end, { buffer = buf, silent = true, desc = "Save edited message" })

  vim.keymap.set("i", "<C-CR>", function()
    save_and_close()
  end, { buffer = buf, silent = true, desc = "Save edited message" })
end

function M.open()
  local items = get_queue_items()
  if #items == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for i, item in ipairs(items) do
    table.insert(labels, item_label(item, i))
  end

  vim.ui.select(labels, {
    prompt = string.format("Queued messages (%d)", #items),
  }, function(_, idx)
    if not idx then
      return
    end

    local item = items[idx]
    local actions = { "Edit", "Delete", "Move up", "Move down" }

    vim.ui.select(actions, {
      prompt = "Action",
    }, function(choice)
      if not choice then
        vim.schedule(M.open)
        return
      end

      if choice == "Edit" then
        open_editor(item, function(new_text)
          queue.update(idx, new_text)
          persist_queue()
          vim.notify("Queue item updated", vim.log.levels.INFO)
          vim.schedule(M.open)
        end)
        return
      end

      if choice == "Delete" then
        queue.remove_at(idx)
        persist_queue()
        vim.notify(string.format("Removed item %d from queue", idx), vim.log.levels.INFO)
        if queue.size() == 0 then
          vim.notify("Queue is now empty", vim.log.levels.INFO)
          return
        end
        vim.schedule(M.open)
        return
      end

      if choice == "Move up" then
        if idx <= 1 then
          vim.notify("Already at top", vim.log.levels.WARN)
          vim.schedule(M.open)
          return
        end
        queue.move_up(idx)
        persist_queue()
        vim.schedule(M.open)
        return
      end

      if choice == "Move down" then
        if idx >= queue.size() then
          vim.notify("Already at bottom", vim.log.levels.WARN)
          vim.schedule(M.open)
          return
        end
        queue.move_down(idx)
        persist_queue()
        vim.schedule(M.open)
        return
      end
    end)
  end)
end

return M
