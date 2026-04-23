local M = {}

local HISTORY_NS = vim.api.nvim_create_namespace("tua_history")

local HL = {
  user = "TuaUserMessage",
  assistant = "TuaAssistantMessage",
  tool = "TuaToolBlock",
  tool_error = "TuaToolError",
  thinking = "TuaThinkingBlock",
  system = "TuaSystemMessage",
  timestamp = "TuaTimestamp",
  separator = "TuaSeparator",
  mention = "TuaMention",
  command = "TuaCommand",
}

function M.setup_highlights()
  local highlights = {
    TuaUserMessage = { link = "DiagnosticInfo", default = true },
    TuaAssistantMessage = { link = "Normal", default = true },
    TuaToolBlock = { link = "Comment", default = true },
    TuaToolError = { link = "DiagnosticError", default = true },
    TuaThinkingBlock = { link = "DiagnosticHint", default = true },
    TuaSystemMessage = { link = "DiagnosticWarn", default = true },
    TuaTimestamp = { link = "LineNr", default = true },
    TuaSeparator = { link = "WinSeparator", default = true },
    TuaMention = { link = "Underlined", default = true },
    TuaCommand = { link = "Keyword", default = true },
    TuaSpinner = { link = "DiagnosticInfo", default = true },
    TuaStatusline = { link = "StatusLine", default = true },
    TuaStatuslineWarn = { link = "DiagnosticWarn", default = true },
    TuaStatuslineError = { link = "DiagnosticError", default = true },
    TuaWelcome = { link = "Comment", default = true },
  }

  for name, def in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, def)
  end
end

function M.create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "tua-history"
  return buf
end

local function flatten_lines(lines)
  local result = {}
  for _, line in ipairs(lines) do
    if type(line) == "string" then
      for _, sub in ipairs(vim.split(line, "\n")) do
        table.insert(result, sub)
      end
    end
  end
  return result
end

function M.set_lines(buf, lines)
  lines = flatten_lines(lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.append_lines(buf, lines)
  lines = flatten_lines(lines)
  local count = vim.api.nvim_buf_line_count(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, count, count, false, lines)
  vim.bo[buf].modifiable = false
end

function M.clear(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
end

function M.format_timestamp(ts)
  if not ts then
    return ""
  end
  return os.date("%H:%M", ts) or ""
end

function M.render_message(msg, config)
  local lines = {}
  local extmarks = {}
  local ts = M.format_timestamp(msg.timestamp)

  if msg.role == "user" then
    local label = config.labels.user_message
    local header = string.format("%s %s", label, ts)
    table.insert(lines, header)
    table.insert(extmarks, { line = #lines - 1, hl = HL.user })

    local content = msg.content
    if type(content) == "string" then
      for _, line in ipairs(vim.split(content, "\n")) do
        table.insert(lines, line)
      end
    elseif type(content) == "table" then
      for _, part in ipairs(content) do
        if part.text then
          for _, line in ipairs(vim.split(part.text, "\n")) do
            table.insert(lines, line)
          end
        end
      end
    end

    if msg.attachments and #msg.attachments > 0 then
      table.insert(lines, string.format("  [+%d attachment(s)]", #msg.attachments))
    end

  elseif msg.role == "assistant" then
    local label = config.labels.agent_response
    local header = string.format("%s %s", label, ts)
    table.insert(lines, header)
    table.insert(extmarks, { line = #lines - 1, hl = HL.assistant })

    if msg.thinking and msg.thinking ~= "" then
      table.insert(lines, "  [think] Thinking...")
      table.insert(extmarks, { line = #lines - 1, hl = HL.thinking })
      for _, line in ipairs(vim.split(msg.thinking, "\n")) do
        table.insert(lines, "    " .. line)
      end
    end

    local content = msg.content
    if type(content) == "string" and content ~= "" then
      for _, line in ipairs(vim.split(content, "\n")) do
        table.insert(lines, line)
      end
    elseif type(content) == "table" then
      for _, part in ipairs(content) do
        if part.text then
          for _, line in ipairs(vim.split(part.text, "\n")) do
            table.insert(lines, line)
          end
        end
      end
    end

    if msg.tool_calls and #msg.tool_calls > 0 then
      for _, tc in ipairs(msg.tool_calls) do
        local name = tc["function"] and tc["function"].name or tc.name or "?"
        table.insert(lines, string.format("  [tool] %s", name))
        table.insert(extmarks, { line = #lines - 1, hl = HL.tool })
      end
    end

  elseif msg.role == "tool" then
    local label = config.labels.tool
    local name = msg.name or "tool"
    local status = msg.is_error and config.labels.tool_failure or config.labels.tool_success
    local header = string.format("%s %s %s", label, name, status)
    table.insert(lines, header)
    table.insert(extmarks, { line = #lines - 1, hl = msg.is_error and HL.tool_error or HL.tool })

    local content = msg.content
    if type(content) == "string" then
      local content_lines = vim.split(content, "\n")
      if #content_lines > 10 then
        for i = 1, 5 do
          table.insert(lines, "  " .. content_lines[i])
        end
        table.insert(lines, string.format("  ... +%d more lines", #content_lines - 5))
      else
        for _, line in ipairs(content_lines) do
          table.insert(lines, "  " .. line)
        end
      end
    end

  elseif msg.role == "system" then
    local label = config.labels.system_error
    table.insert(lines, label .. " " .. tostring(msg.content))
    table.insert(extmarks, { line = #lines - 1, hl = HL.system })
  end

  table.insert(lines, "")
  return lines, extmarks
end

function M.render_welcome(config)
  local lines = {
    "",
    "  Welcome to tua",
    "",
    "  Type your message and press <CR> to send.",
    "  <S-CR> for a new line.",
    "",
    "  Commands:",
    "    :TauModel          Select model",
    "    :TauCycleModel     Cycle models",
    "    :TauCompact        Compact context",
    "    :TauAgents         Show loaded agent files",
    "    :TauLogin <provider>  Authenticate",
    "",
  }
  return lines
end

function M.render_startup_info(session, config)
  local lines = {}
  local agents = require("tua.agents")
  local files = agents.list_loaded_files(session and session.cwd)

  table.insert(lines, "---")

  if session then
    table.insert(lines, string.format("  Model: %s", session.model or "default"))
    table.insert(lines, string.format("  Provider: %s", session.provider or "default"))
  end

  if #files > 0 then
    table.insert(lines, "  Agent files:")
    for _, f in ipairs(files) do
      table.insert(lines, string.format("    %s %s", f.scope, f.name))
    end
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  return lines
end

function M.refresh(buf, session, config)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  M.clear(buf)

  local all_lines = {}
  local all_extmarks = {}

  if not session or not session.messages or #session.messages == 0 then
    local welcome = M.render_welcome(config)
    vim.list_extend(all_lines, welcome)
  else
    local startup = M.render_startup_info(session, config)
    vim.list_extend(all_lines, startup)

    for _, msg in ipairs(session.messages) do
      local lines, extmarks = M.render_message(msg, config)
      for _, em in ipairs(extmarks) do
        em.line = em.line + #all_lines
        table.insert(all_extmarks, em)
      end
      vim.list_extend(all_lines, lines)
    end
  end

  M.set_lines(buf, all_lines)

  for _, em in ipairs(all_extmarks) do
    vim.api.nvim_buf_add_highlight(buf, HISTORY_NS, em.hl, em.line, 0, -1)
  end
end

function M.scroll_to_bottom(buf, win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(win, { line_count, 0 })
end

return M
