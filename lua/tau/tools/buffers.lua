local M = {}

local MAX_OUTPUT_LINES = 2000
local MAX_OUTPUT_BYTES = 50 * 1024

local function resolve_path(path)
	if vim.fn.has("win32") == 1 and path:match("^%a:/") then
		return path
	end
	if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then
		return vim.fn.expand(path)
	end
	return vim.fn.getcwd() .. "/" .. path
end

function M.open_buffers_tool(input)
	local buffers = vim.api.nvim_list_bufs()
	local current_buf = vim.api.nvim_get_current_buf()
	local result = {}

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			if name == "" then
				name = "[No Name]"
			end
			local modified = vim.bo[buf].modified and "+" or " "
			local line_count = vim.api.nvim_buf_line_count(buf)
			local cursor = { 0, 0 }
			local all_wins = vim.api.nvim_list_wins()
			local windows = {}
			for _, win in ipairs(all_wins) do
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
					table.insert(windows, win)
				end
			end
			local is_visible = #windows > 0
			for _, win in ipairs(windows) do
				if vim.api.nvim_win_is_valid(win) then
					cursor = vim.api.nvim_win_get_cursor(win)
					break
				end
			end

			table.insert(result, {
				bufnr = buf,
				name = name,
				modified = modified == "+",
				line_count = line_count,
				current_line = cursor[1],
				is_active = buf == current_buf,
				is_visible = is_visible,
				filetype = vim.bo[buf].filetype,
			})
		end
	end

	local lines = { "Open buffers:" }
	for _, info in ipairs(result) do
		local active_mark = info.is_active and "*" or " "
		local visible_mark = info.is_visible and "v" or " "
		local mod_mark = info.modified and "+" or " "
		table.insert(lines, string.format(
			"  %s%s%s bufnr=%d lines=%d/%d ft=%s %s",
			active_mark,
			visible_mark,
			mod_mark,
			info.bufnr,
			info.current_line,
			info.line_count,
			info.filetype,
			info.name
		))
	end

	return {
		text = table.concat(lines, "\n"),
		buffer_count = #result,
	}
end

function M.read_buffer_tool(input)
	local bufnr = input.bufnr
	local offset = input.offset or 1
	local limit = input.limit or MAX_OUTPUT_LINES

	if not bufnr then
		return { error = "bufnr is required" }
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { error = "Invalid buffer: " .. bufnr }
	end

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return { error = "Buffer not loaded: " .. bufnr }
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local total_lines = #lines

	if offset > total_lines then
		return {
			text = "Buffer has " .. total_lines .. " lines. offset=" .. offset .. " is beyond end.",
			total_lines = total_lines,
		}
	end

	local end_line = math.min(offset + limit - 1, total_lines)
	local selected = {}
	for i = offset, end_line do
		table.insert(selected, lines[i])
	end

	local content = table.concat(selected, "\n")
	local out = {
		text = content,
		total_lines = total_lines,
		offset = offset,
		returned_lines = end_line - offset + 1,
		bufnr = bufnr,
		name = vim.api.nvim_buf_get_name(bufnr),
	}

	if total_lines > limit then
		out.note = "Buffer has " .. total_lines .. " lines. Showing lines " .. offset .. "-" .. end_line .. ". Use offset=" .. (end_line + 1) .. " to read more."
	end

	return out
end

function M.edit_buffer_tool(input)
	local bufnr = input.bufnr
	local edits = input.edits

	if not bufnr then
		return { error = "bufnr is required" }
	end

	if not edits or #edits == 0 then
		return { error = "No edits provided" }
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { error = "Invalid buffer: " .. bufnr }
	end

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return { error = "Buffer not loaded: " .. bufnr }
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local original = table.concat(lines, "\n")
	local modified = original
	local errors = {}

	for i, edit in ipairs(edits) do
		if not edit.oldText or edit.oldText == "" then
			table.insert(errors, "Edit " .. i .. ": oldText cannot be empty")
			goto continue
		end

		local first = modified:find(edit.oldText, 1, true)
		if not first then
			table.insert(errors, "Edit " .. i .. ": oldText not found in buffer")
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
		return { text = "No changes made — buffer content already matches." }
	end

	local new_lines = vim.split(modified, "\n")
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

	local orig_line_count = #lines
	local new_line_count = #new_lines

	return {
		text = "Buffer edited: bufnr=" .. bufnr .. " (" .. new_line_count .. " lines)",
		bufnr = bufnr,
		lines_before = orig_line_count,
		lines_after = new_line_count,
	}
end

function M.open_file_to_buffer_tool(input)
	local path = input.path
	local line_nr = input.line
	local split = input.split

	if not path or path == "" then
		return { error = "path is required" }
	end

	local full = resolve_path(path)
	full = vim.fn.fnamemodify(full, ":p")

	if vim.fn.isdirectory(full) == 1 then
		return { error = "Path is a directory, not a file: " .. full }
	end

	if split then
		if split == "vertical" or split == "v" then
			vim.cmd("vsplit")
		elseif split == "horizontal" or split == "h" or split == "s" then
			vim.cmd("split")
		end
	end

	local win = vim.api.nvim_get_current_win()
	vim.cmd("edit " .. vim.fn.fnameescape(full))

	local bufnr = vim.api.nvim_win_get_buf(win)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local line_count = vim.api.nvim_buf_line_count(bufnr)

	if type(line_nr) == "number" and line_nr >= 1 then
		line_nr = math.min(line_nr, math.max(1, line_count))
		pcall(vim.api.nvim_win_set_cursor, win, { line_nr, 0 })
	end

	return {
		text = "Opened in buffer bufnr=" .. bufnr .. " (" .. line_count .. " lines): " .. name,
		bufnr = bufnr,
		path = name,
		line_count = line_count,
	}
end

function M.goto_buffer_tool(input)
	local bufnr = input.bufnr
	local split = input.split

	if not bufnr then
		return { error = "bufnr is required" }
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { error = "Invalid buffer: " .. bufnr }
	end

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return { error = "Buffer not loaded: " .. bufnr }
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		name = "[No Name]"
	end

	if split then
		if split == "vertical" or split == "v" then
			vim.cmd("vsplit")
		elseif split == "horizontal" or split == "h" or split == "s" then
			vim.cmd("split")
		end
	end

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, bufnr)

	return {
		text = "Switched to buffer " .. bufnr .. ": " .. name,
		bufnr = bufnr,
		name = name,
	}
end

return M
