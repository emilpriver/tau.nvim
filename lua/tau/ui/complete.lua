local M = {}

local function find_files(base)
  local cwd = vim.fn.getcwd()
  local pattern = base ~= "" and (base .. "*") or "*"
  local files = vim.fn.globpath(cwd, pattern, false, true)

  local results = {}
  for _, f in ipairs(files) do
    local rel = vim.fn.fnamemodify(f, ":.")
    if vim.fn.isdirectory(f) == 1 then
      table.insert(results, rel .. "/")
    else
      table.insert(results, rel)
    end
  end

  table.sort(results)
  return results
end

local function find_dirs(base)
  local cwd = vim.fn.getcwd()
  local pattern = base ~= "" and (base .. "*") or "*"
  local files = vim.fn.globpath(cwd, pattern, false, true)

  local results = {}
  for _, f in ipairs(files) do
    if vim.fn.isdirectory(f) == 1 then
      table.insert(results, vim.fn.fnamemodify(f, ":.") .. "/")
    end
  end

  table.sort(results)
  return results
end

local COMMANDS = {
  { word = "/model", info = "Switch model" },
  { word = "/settings", info = "Open settings" },
  { word = "/compact", info = "Compact context" },
  { word = "/tree", info = "Session tree" },
  { word = "/fork", info = "Fork session" },
  { word = "/clone", info = "Clone session" },
  { word = "/new", info = "New session" },
  { word = "/stop", info = "Stop agent" },
  { word = "/abort", info = "Abort turn" },
  { word = "/agents", info = "Show agent files" },
  { word = "/thinking", info = "Toggle thinking" },
}

function M.completefunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]

    for i = col, 1, -1 do
      local ch = line:sub(i, i)
      if ch == "@" or ch == "/" then
        return i - 1
      end
      if ch == " " or ch == "\t" then
        return -2
      end
    end
    return -2
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local trigger = ""

  for i = math.min(col, #line), 1, -1 do
    local ch = line:sub(i, i)
    if ch == "@" or ch == "/" then
      trigger = ch
      break
    end
  end

  local results = {}

  if trigger == "@" then
    local files = find_files(base)
    for _, f in ipairs(files) do
      table.insert(results, { word = f, menu = "[file]" })
    end

    local dirs = find_dirs(base)
    for _, d in ipairs(dirs) do
      table.insert(results, { word = d, menu = "[dir]" })
    end
  elseif trigger == "/" then
    for _, cmd in ipairs(COMMANDS) do
      if cmd.word:find(base, 1, true) == 1 then
        table.insert(results, { word = cmd.word, menu = "[cmd]", info = cmd.info })
      end
    end
  end

  return results
end

function M.expand_mentions(text)
  local result = text

  result = result:gsub("@([%w%_%-%./]+)/ ", function(path)
    return "[directory: " .. path .. "/] "
  end)

  result = result:gsub("@([%w%_%-%./]+)", function(path)
    local full_path = vim.fn.getcwd() .. "/" .. path
    if vim.fn.filereadable(full_path) == 1 then
      local bufnr = vim.fn.bufnr(full_path)
      if bufnr ~= -1 then
        local line = vim.api.nvim_win_get_cursor(0)[1]
        return string.format("[file: %s, line: %d]", path, line)
      end
      return "[file: " .. path .. "]"
    elseif vim.fn.isdirectory(full_path) == 1 then
      return "[directory: " .. path .. "]"
    end
    return "@" .. path
  end)

  return result
end

function M.validate_mentions(text)
  local invalid = {}
  for mention in text:gmatch("%[file: ([^%]]+)%]") do
    local path = mention:gsub(", line: %d+", ""):gsub(", lines: %d+%-%d+", "")
    local full = vim.fn.getcwd() .. "/" .. path
    if vim.fn.filereadable(full) ~= 1 and vim.fn.isdirectory(full) ~= 1 then
      table.insert(invalid, path)
    end
  end
  return invalid
end

function M.send_mention_for_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    vim.notify("No file for current buffer", vim.log.levels.WARN)
    return nil
  end

  local rel = vim.fn.fnamemodify(name, ":.")
  local mode = vim.api.nvim_get_mode().mode
  local line1, line2

  if mode:find("[vV\x16]") then
    line1 = vim.fn.line("v")
    line2 = vim.fn.line(".")
    if line1 > line2 then
      line1, line2 = line2, line1
    end
  else
    line1 = vim.fn.line(".")
    line2 = line1
  end

  if line1 == line2 then
    return "[file: " .. rel .. ", line: " .. line1 .. "]"
  else
    return "[file: " .. rel .. ", lines: " .. line1 .. "-" .. line2 .. "]"
  end
end

return M
