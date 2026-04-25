local M = {}

local HISTORY_NS = vim.api.nvim_create_namespace("tau_history")

local HL = {
	user = "TauUserMessage",
	assistant = "TauAssistantMessage",
	tool = "TauToolBlock",
	tool_error = "TauToolError",
	thinking = "TauThinkingBlock",
	system = "TauSystemMessage",
	timestamp = "TauTimestamp",
	separator = "TauSeparator",
	mention = "TauMention",
	command = "TauCommand",
}

function M.setup_highlights()
	local highlights = {
		TauUserMessage = { link = "DiagnosticInfo", default = true },
		TauAssistantMessage = { link = "Normal", default = true },
		TauToolBlock = { link = "Comment", default = true },
		TauToolError = { link = "DiagnosticError", default = true },
		TauThinkingBlock = { link = "Comment", default = true },
		TauSystemMessage = { link = "DiagnosticWarn", default = true },
		TauTimestamp = { link = "LineNr", default = true },
		TauSeparator = { link = "WinSeparator", default = true },
		TauMention = { link = "Underlined", default = true },
		TauCommand = { link = "Keyword", default = true },
		TauSpinner = { link = "DiagnosticInfo", default = true },
		TauStatusline = { link = "StatusLine", default = true },
		TauStatuslineWarn = { link = "DiagnosticWarn", default = true },
		TauStatuslineError = { link = "DiagnosticError", default = true },
		TauWelcome = { link = "Comment", default = true },
		TauLogo = { ctermfg = 119, fg = "#9ee65c", default = true },
		TauLogoDim = { ctermfg = 71, fg = "#4caf6a", default = true },
		TauLogoEdge = { ctermfg = 65, fg = "#2d6b3e", default = true },
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
	vim.bo[buf].filetype = "tau-history"
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

	-- Handle queued/pending user messages
	if msg.role == "user" and msg._queued then
		local label = config.labels.steer_message or "󰾘"
		local header = string.format("%s %s (queued)", label, ts)
		table.insert(lines, header)
		table.insert(extmarks, { line = #lines - 1, hl = HL.system })

		local content = msg.content
		if type(content) == "string" then
			for _, line in ipairs(vim.split(content, "\n")) do
				table.insert(lines, "  " .. line)
			end
		elseif type(content) == "table" then
			for _, part in ipairs(content) do
				if part.text then
					for _, line in ipairs(vim.split(part.text, "\n")) do
						table.insert(lines, "  " .. line)
					end
				end
			end
		end

		if msg.attachments and #msg.attachments > 0 then
			table.insert(lines, string.format("  [+%d attachment(s)]", #msg.attachments))
		end
		table.insert(lines, "")
		return lines, extmarks
	end

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
		if msg._hidden then
			return {}, {}
		end
		local label = config.labels.system_error
		table.insert(lines, label)
		table.insert(extmarks, { line = #lines - 1, hl = HL.system })

		local content = msg.content
		if type(content) == "string" then
			for _, line in ipairs(vim.split(content, "\n")) do
				table.insert(lines, "  " .. line)
			end
		end
	end

	table.insert(lines, "")
	return lines, extmarks
end

function M.render_welcome_logo()
	local logo_w = 30
	local function pad(s)
		local n = vim.fn.strwidth(s)
		if n < logo_w then
			return s .. string.rep(" ", logo_w - n)
		end
		return s
	end
	local name = "Tau"
	local name_w = vim.fn.strwidth(name)
	local name_left = math.floor((logo_w - name_w) / 2)
	local name_line = string.rep(" ", name_left) .. name .. string.rep(" ", logo_w - name_w - name_left)
	local lines = {
		pad("         ╭·───────────·╮  "),
		pad("        ╱                 ╲ "),
		pad("       │                   │"),
		pad("      │                     │"),
		pad("     │          τ            │"),
		pad("      │                     │"),
		pad("       │                   │"),
		pad("        ╲                 ╱ "),
		pad("         ╰·─        ─·╯   "),
		name_line,
		pad(""),
	}
	local extmarks = {
		{ line = 0, hl = "TauLogo" },
		{ line = 1, hl = "TauLogoDim" },
		{ line = 2, hl = "TauLogo" },
		{ line = 3, hl = "TauLogoDim" },
		{ line = 4, hl = "TauLogo" },
		{ line = 5, hl = "TauLogoDim" },
		{ line = 6, hl = "TauLogo" },
		{ line = 7, hl = "TauLogoDim" },
		{ line = 8, hl = "TauLogoEdge" },
		{ line = 9, hl = "TauLogo" },
	}
	return lines, extmarks
end

function M.render_startup_info(session, config)
	local lines = {}
	local agents_mod = require("tau.agents")
	local src = agents_mod.list_context_sources(session and session.cwd)
	local function add_section(heading, items)
		if #items == 0 then
			return
		end
		table.insert(lines, "  " .. heading)
		for _, item in ipairs(items) do
			local p = item.path and vim.fn.fnamemodify(item.path, ":~") or (item.name or "?")
			table.insert(lines, "    " .. p)
		end
	end
	add_section("AGENTS.md", src.agents)
	add_section("SYSTEM.md", src.system)
	add_section("APPEND_SYSTEM.md", src.append)
	if #lines == 0 then
		return lines
	end
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
		local logo_lines, logo_marks = M.render_welcome_logo()
		vim.list_extend(all_lines, logo_lines)
		for _, em in ipairs(logo_marks) do
			table.insert(all_extmarks, { line = em.line, hl = em.hl })
		end
		local startup = M.render_startup_info(session, config)
		if #startup > 0 then
			vim.list_extend(all_lines, startup)
		end
	else
		local startup = M.render_startup_info(session, config)
		if #startup > 0 then
			vim.list_extend(all_lines, startup)
		end

		for _, msg in ipairs(session.messages) do
			local lines, extmarks = M.render_message(msg, config)
			if #lines > 0 then
				for _, em in ipairs(extmarks) do
					em.line = em.line + #all_lines
					table.insert(all_extmarks, em)
				end
				vim.list_extend(all_lines, lines)
			end
		end

		local pending = session.queue or {}
		for _, item in ipairs(pending) do
			local lines, extmarks = M.render_message({
				role = "user",
				content = item.text,
				_queued = true,
				_queue_type = item.type,
				timestamp = item.timestamp,
			}, config)
			if #lines > 0 then
				for _, em in ipairs(extmarks) do
					em.line = em.line + #all_lines
					table.insert(all_extmarks, em)
				end
				vim.list_extend(all_lines, lines)
			end
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
