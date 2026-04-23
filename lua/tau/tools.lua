local M = {}

local MAX_OUTPUT_LINES = 2000
local MAX_OUTPUT_BYTES = 50 * 1024

M.changed_files = {}


-- TODO: I want to be able to edit buffers in neovim
M.tools = {
  read = {
    name = "read",
    description = "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
    parameters = {
      type = "object",
      properties = {
        path = { type = "string", description = "Path to the file to read (relative or absolute)" },
        offset = { type = "number", description = "Line number to start reading from (1-indexed)" },
        limit = { type = "number", description = "Maximum number of lines to read" },
      },
      required = { "path" },
    },
  },
  write = {
    name = "write",
    description = "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
    parameters = {
      type = "object",
      properties = {
        path = { type = "string", description = "Path to the file to write (relative or absolute)" },
        content = { type = "string", description = "Content to write to the file" },
      },
      required = { "path", "content" },
    },
  },
  edit = {
    name = "edit",
    description = "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.",
    parameters = {
      type = "object",
      properties = {
        path = { type = "string", description = "Path to the file to edit (relative or absolute)" },
        edits = {
          type = "array",
          description = "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead.",
          items = {
            type = "object",
            properties = {
              oldText = { type = "string", description = "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call." },
              newText = { type = "string", description = "Replacement text for this targeted edit." },
            },
            required = { "oldText", "newText" },
          },
        },
      },
      required = { "path", "edits" },
    },
  },
  bash = {
    name = "bash",
    description = "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
    parameters = {
      type = "object",
      properties = {
        command = { type = "string", description = "Bash command to execute" },
        timeout = { type = "number", description = "Timeout in seconds (optional, no default timeout)" },
      },
      required = { "command" },
    },
  },
  open_buffers = {
    name = "open_buffers",
    description = "List all open buffers in Neovim. Returns buffer numbers, file names, modified status, line counts, and file types. Use this to discover which files the user is currently editing.",
    parameters = {
      type = "object",
    },
  },
  read_buffer = {
    name = "read_buffer",
    description = "Read the contents of an open Neovim buffer by buffer number. Returns buffer content as text. Supports offset/limit for large buffers. Works even for unsaved buffers ([No Name]).",
    parameters = {
      type = "object",
      properties = {
        bufnr = { type = "number", description = "Buffer number (from open_buffers)" },
        offset = { type = "number", description = "Line number to start reading from (1-indexed)" },
        limit = { type = "number", description = "Maximum number of lines to read" },
      },
      required = { "bufnr" },
    },
  },
  edit_buffer = {
    name = "edit_buffer",
    description = "Edit an open Neovim buffer using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the buffer. Changes are applied via Neovim's buffer API (not file on disk), so unsaved buffers can be edited too. The buffer is marked as modified after editing.",
    parameters = {
      type = "object",
      properties = {
        bufnr = { type = "number", description = "Buffer number (from open_buffers)" },
        edits = {
          type = "array",
          description = "One or more targeted replacements. Each edit is matched against the original buffer, not incrementally. Do not include overlapping or nested edits.",
          items = {
            type = "object",
            properties = {
              oldText = { type = "string", description = "Exact text for one targeted replacement. Must be unique in the buffer." },
              newText = { type = "string", description = "Replacement text for this targeted edit." },
            },
            required = { "oldText", "newText" },
          },
        },
      },
      required = { "bufnr", "edits" },
    },
  },
  goto_buffer = {
    name = "goto_buffer",
    description = "Switch the user's view to a specific buffer. Opens the buffer in the current window. Optionally opens in a vertical or horizontal split.",
    parameters = {
      type = "object",
      properties = {
        bufnr = { type = "number", description = "Buffer number to switch to" },
        split = { type = "string", description = "Optional: 'vertical' or 'horizontal' to open in a split" },
      },
      required = { "bufnr" },
    },
  },
  tree = {
    name = "tree",
    description = "List all files and folders in a directory recursively. Returns a tree-like listing. Defaults to the current working directory. Use this to explore the project structure.",
    parameters = {
      type = "object",
      properties = {
        path = { type = "string", description = "Directory path to list (relative or absolute). Defaults to current working directory." },
        depth = { type = "number", description = "Maximum recursion depth. Defaults to 3." },
      },
    },
  },
  grep = {
    name = "grep",
    description = "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",
    parameters = {
      type = "object",
      properties = {
        pattern = { type = "string", description = "Search pattern (regex or literal string)" },
        path = { type = "string", description = "Directory or file to search (default: current directory)" },
        glob = { type = "string", description = "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'" },
        ignoreCase = { type = "boolean", description = "Case-insensitive search (default: false)" },
        literal = { type = "boolean", description = "Treat pattern as literal string instead of regex (default: false)" },
        context = { type = "number", description = "Number of lines to show before and after each match (default: 0)" },
        limit = { type = "number", description = "Maximum number of matches to return (default: 100)" },
      },
      required = { "pattern" },
    },
  },
  find = {
    name = "find",
    description = "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).",
    parameters = {
      type = "object",
      properties = {
        pattern = { type = "string", description = "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'" },
        path = { type = "string", description = "Directory to search in (default: current directory)" },
        limit = { type = "number", description = "Maximum number of results (default: 1000)" },
      },
      required = { "pattern" },
    },
  },
  ls = {
    name = "ls",
    description = "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).",
    parameters = {
      type = "object",
      properties = {
        path = { type = "string", description = "Directory to list (default: current directory)" },
        limit = { type = "number", description = "Maximum number of entries to return (default: 500)" },
      },
    },
  },
}

local function resolve_path(path)
  if vim.fn.has("win32") == 1 and path:match("^%a:/") then
    return path
  end
  if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then
    return vim.fn.expand(path)
  end
  return vim.fn.getcwd() .. "/" .. path
end

local function truncate_output(text)
  if not text or text == "" then
    return ""
  end
  if #text <= MAX_OUTPUT_BYTES then
    local lines = vim.split(text, "\n")
    if #lines <= MAX_OUTPUT_LINES then
      return text
    end
    local truncated = table.concat(lines, "\n", #lines - MAX_OUTPUT_LINES + 1)
    return truncated .. "\n\n[Output truncated to last " .. MAX_OUTPUT_LINES .. " lines]"
  end
  local tail_start = math.max(1, #text - MAX_OUTPUT_BYTES)
  return text:sub(tail_start) .. "\n\n[Output truncated to last " .. MAX_OUTPUT_BYTES .. " bytes]"
end

function M.read_tool(input)
  local path = resolve_path(input.path)

  if vim.fn.filereadable(path) == 0 then
    return { error = "File not found: " .. path }
  end

  local f = io.open(path, "r")
  if not f then
    return { error = "Cannot open file: " .. path }
  end

  local content = f:read("*all")
  f:close()

  local ext = path:match("%.([^.]+)$")
  local image_exts = { jpg = true, jpeg = true, png = true, gif = true, webp = true, svg = true }
  if ext and image_exts[ext:lower()] then
    return {
      text = "[Image file: " .. path .. " — use image attachment to send to model]",
      is_image = true,
      path = path,
    }
  end

  local offset = input.offset or 1
  local limit = input.limit or MAX_OUTPUT_LINES
  local lines = vim.split(content, "\n")
  local total_lines = #lines

  if offset > total_lines then
    return {
      text = "File has " .. total_lines .. " lines. offset=" .. offset .. " is beyond end of file.",
      total_lines = total_lines,
    }
  end

  local end_line = math.min(offset + limit - 1, total_lines)
  local selected = {}
  for i = offset, end_line do
    table.insert(selected, lines[i])
  end

  local result = table.concat(selected, "\n")
  local out = {
    text = result,
    total_lines = total_lines,
    offset = offset,
    returned_lines = end_line - offset + 1,
  }

  if total_lines > limit then
    out.note = "File has " .. total_lines .. " lines. Showing lines " .. offset .. "-" .. end_line .. ". Use offset=" .. (end_line + 1) .. " to read more."
  end

  return out
end

function M.write_tool(input)
  local path = resolve_path(input.path)
  local content = input.content or ""

  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local f = io.open(path, "w")
  if not f then
    return { error = "Cannot write to file: " .. path }
  end

  f:write(content)
  f:close()

  local lines = vim.split(content, "\n")
  table.insert(M.changed_files, path)

  return {
    text = "File written: " .. path .. " (" .. #lines .. " lines)",
    path = path,
    lines_written = #lines,
  }
end

function M.edit_tool(input)
  local path = resolve_path(input.path)
  local edits = input.edits

  if not edits or #edits == 0 then
    return { error = "No edits provided" }
  end

  if vim.fn.filereadable(path) == 0 then
    return { error = "File not found: " .. path .. ". Use write tool to create it." }
  end

  local f = io.open(path, "r")
  if not f then
    return { error = "Cannot open file: " .. path }
  end
  local original = f:read("*all")
  f:close()

  local modified = original
  local errors = {}

  for i, edit in ipairs(edits) do
    if edit.oldText == "" then
      table.insert(errors, "Edit " .. i .. ": oldText cannot be empty")
      goto continue
    end

    local first = modified:find(edit.oldText, 1, true)
    if not first then
      table.insert(errors, "Edit " .. i .. ": oldText not found in file")
      goto continue
    end

    local second = modified:find(edit.oldText, first + 1, true)
    if second then
      table.insert(errors, "Edit " .. i .. ": oldText matches multiple locations (must be unique)")
      goto continue
    end

    modified = modified:sub(1, first - 1) .. edit.newText .. modified:sub(first + #edit.oldText)

    ::continue::
  end

  if #errors > 0 then
    return {
      error = "Edit failed:\n" .. table.concat(errors, "\n"),
      original_content = original,
    }
  end

  if modified == original then
    return { text = "No changes made — file content already matches." }
  end

  local wf = io.open(path, "w")
  if not wf then
    return { error = "Cannot write to file: " .. path }
  end
  wf:write(modified)
  wf:close()

  table.insert(M.changed_files, path)

  local orig_lines = vim.split(original, "\n")
  local new_lines = vim.split(modified, "\n")

  return {
    text = "File edited: " .. path .. " (" .. #new_lines .. " lines)",
    path = path,
    lines_before = #orig_lines,
    lines_after = #new_lines,
  }
end

function M.bash_tool(input)
  local command = input.command
  local timeout = input.timeout

  if not command or command == "" then
    return { error = "No command provided" }
  end

  local ok, result = pcall(function()
    return vim.system({ "bash", "-c", command }, { text = true }, nil):wait(timeout)
  end)

  if not ok then
    return { error = "Command execution failed: " .. result }
  end

  if not result then
    return { error = "Command timed out or failed to execute (no result returned)" }
  end

  local output = ""
  if result.stdout and result.stdout ~= "" then
    output = output .. result.stdout
  end
  if result.stderr and result.stderr ~= "" then
    if output ~= "" then
      output = output .. "\n"
    end
    output = output .. result.stderr
  end

  local truncated = truncate_output(output)

  return {
    text = truncated,
    exit_code = result.code,
    truncated = truncated ~= output,
  }
end

function M.tree_tool(input)
  local path = input.path and resolve_path(input.path) or vim.fn.getcwd()
  local max_depth = input.depth or 3

  if vim.fn.isdirectory(path) == 0 then
    return { error = "Not a directory: " .. path }
  end

  local uv = vim.uv or vim.loop
  local result = { path .. "/" }

  local function scandir(dir, depth, prefix)
    if depth > max_depth then
      return
    end
    local handle = uv.fs_scandir(dir)
    if not handle then
      return
    end
    local entries = {}
    while true do
      local name, typ = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name ~= "." and name ~= ".." then
        table.insert(entries, { name = name, type = typ })
      end
    end
    table.sort(entries, function(a, b)
      if a.type == b.type then
        return a.name < b.name
      end
      return a.type == "directory"
    end)
    for i, entry in ipairs(entries) do
      local is_last = i == #entries
      local connector = is_last and "└── " or "├── "
      local child_prefix = is_last and "    " or "│   "
      table.insert(result, prefix .. connector .. entry.name)
      if entry.type == "directory" then
        scandir(dir .. "/" .. entry.name, depth + 1, prefix .. child_prefix)
      end
    end
  end

  scandir(path, 1, "")

  local text = table.concat(result, "\n")
  return {
    text = text,
    path = path,
    depth = max_depth,
  }
end

function M.grep_tool(input)
  local pattern = input.pattern
  if not pattern or pattern == "" then
    return { error = "No pattern provided" }
  end

  local search_path = input.path and resolve_path(input.path) or vim.fn.getcwd()
  local effective_limit = input.limit or 100
  local context_lines = input.context or 0

  local rg_cmd = { "rg", "--json", "--line-number", "--color=never", "--hidden" }
  if input.ignoreCase then
    table.insert(rg_cmd, "--ignore-case")
  end
  if input.literal then
    table.insert(rg_cmd, "--fixed-strings")
  end
  if input.glob then
    table.insert(rg_cmd, "--glob")
    table.insert(rg_cmd, input.glob)
  end
  if context_lines > 0 then
    table.insert(rg_cmd, "--context")
    table.insert(rg_cmd, tostring(context_lines))
  end
  table.insert(rg_cmd, pattern)
  table.insert(rg_cmd, search_path)

  local ok, result = pcall(function()
    return vim.system(rg_cmd, { text = true }):wait()
  end)

  if not ok then
    return { error = "ripgrep (rg) is not available. Install it to use the grep tool." }
  end

  if result.code ~= 0 and result.code ~= 1 then
    return { error = result.stderr or "ripgrep failed" }
  end

  local output_lines = {}
  local match_count = 0
  local file_cache = {}

  for line in (result.stdout or ""):gmatch("[^\n]+") do
    if match_count >= effective_limit then
      break
    end
    local success, event = pcall(vim.json.decode, line)
    if success and event and event.type == "match" then
      match_count = match_count + 1
      local file_path = event.data and event.data.path and event.data.path.text or ""
      local line_num = event.data and event.data.line_number or 0
      local line_text = event.data and event.data.lines and event.data.lines.text or ""
      line_text = line_text:gsub("\r?\n", ""):gsub("\r", "")
      if line_text:len() > 500 then
        line_text = line_text:sub(1, 500) .. "..."
      end
      local rel_path = vim.fn.fnamemodify(file_path, ":~:.")
      table.insert(output_lines, string.format("%s:%d: %s", rel_path, line_num, line_text))
    end
  end

  if #output_lines == 0 then
    return { text = "No matches found" }
  end

  local output = table.concat(output_lines, "\n")
  local truncated = truncate_output(output)
  local out = { text = truncated, matches = match_count }
  if truncated ~= output then
    out.truncated = true
  end
  if match_count >= effective_limit then
    out.limit_reached = effective_limit
  end
  return out
end

function M.find_tool(input)
  local pattern = input.pattern
  if not pattern or pattern == "" then
    return { error = "No pattern provided" }
  end

  local search_path = input.path and resolve_path(input.path) or vim.fn.getcwd()
  local effective_limit = input.limit or 1000

  local fd_cmd = { "fd", "--glob", "--color=never", "--hidden", "--no-require-git", "--max-results", tostring(effective_limit) }
  if pattern:find("/") then
    table.insert(fd_cmd, "--full-path")
    if not pattern:match("^/") and not pattern:match("^%*%*/") and pattern ~= "**" then
      pattern = "**/" .. pattern
    end
  end
  table.insert(fd_cmd, pattern)
  table.insert(fd_cmd, search_path)

  local ok, result = pcall(function()
    return vim.system(fd_cmd, { text = true }):wait()
  end)

  if not ok then
    local find_cmd = { "find", search_path, "-name", input.pattern, "-type", "f" }
    ok, result = pcall(function()
      return vim.system(find_cmd, { text = true }):wait()
    end)
    if not ok then
      return { error = "Neither fd nor find is available. Install fd or find to use the find tool." }
    end
  end

  if result.code ~= 0 and result.code ~= 1 then
    return { error = result.stderr or "find command failed" }
  end

  local lines = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    line = line:gsub("\r$", "")
    line = line:gsub("^%s*(.-)%s*$", "%1")
    if line ~= "" then
      local rel = vim.fn.fnamemodify(line, ":~:.")
      table.insert(lines, rel)
    end
  end

  if #lines == 0 then
    return { text = "No files found matching pattern" }
  end

  local output = table.concat(lines, "\n")
  local truncated = truncate_output(output)
  local out = { text = truncated, files = #lines }
  if truncated ~= output then
    out.truncated = true
  end
  if #lines >= effective_limit then
    out.limit_reached = effective_limit
  end
  return out
end

function M.ls_tool(input)
  local dir_path = input.path and resolve_path(input.path) or vim.fn.getcwd()
  local effective_limit = input.limit or 500

  if vim.fn.isdirectory(dir_path) == 0 then
    return { error = "Not a directory: " .. dir_path }
  end

  local uv = vim.uv or vim.loop
  local handle = uv.fs_scandir(dir_path)
  if not handle then
    return { error = "Cannot read directory: " .. dir_path }
  end

  local entries = {}
  while true do
    local name, typ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    table.insert(entries, { name = name, type = typ })
  end

  table.sort(entries, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  local results = {}
  local entry_limit_reached = false
  for _, entry in ipairs(entries) do
    if #results >= effective_limit then
      entry_limit_reached = true
      break
    end
    local suffix = entry.type == "directory" and "/" or ""
    table.insert(results, entry.name .. suffix)
  end

  if #results == 0 then
    return { text = "(empty directory)" }
  end

  local output = table.concat(results, "\n")
  local truncated = truncate_output(output)
  local out = { text = truncated, entries = #results }
  if truncated ~= output then
    out.truncated = true
  end
  if entry_limit_reached then
    out.limit_reached = effective_limit
  end
  return out
end

local buffer_tools = require("tau.tools.buffers")

local TOOL_MAP = {
  read = M.read_tool,
  write = M.write_tool,
  edit = M.edit_tool,
  bash = M.bash_tool,
  tree = M.tree_tool,
  grep = M.grep_tool,
  find = M.find_tool,
  ls = M.ls_tool,
  open_buffers = buffer_tools.open_buffers_tool,
  read_buffer = buffer_tools.read_buffer_tool,
  edit_buffer = buffer_tools.edit_buffer_tool,
  goto_buffer = buffer_tools.goto_buffer_tool,
}

function M.execute(tool_name, input)
  local fn = TOOL_MAP[tool_name]
  if not fn then
    local names = {}
    for name in pairs(TOOL_MAP) do
      table.insert(names, name)
    end
    table.sort(names)
    return { error = "Unknown tool: " .. tool_name .. ". Available tools: " .. table.concat(names, ", ") }
  end

  local ok, result = pcall(fn, input or {})
  if not ok then
    return { error = "Tool " .. tool_name .. " failed: " .. result }
  end
  return result
end

function M.get_tool_list()
  local list = {}
  for _, tool in pairs(M.tools) do
    table.insert(list, tool)
  end
  return list
end

function M.get_changed_files()
  local seen = {}
  local unique = {}
  for _, f in ipairs(M.changed_files) do
    if not seen[f] then
      seen[f] = true
      table.insert(unique, f)
    end
  end
  return unique
end

return M
