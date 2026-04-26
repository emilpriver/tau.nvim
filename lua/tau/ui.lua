local M = {}

local layout = require("tau.ui.layout")
local history = require("tau.ui.history")
local prompt = require("tau.ui.prompt")
local complete = require("tau.ui.complete")
local queue = require("tau.ui.queue")
local zen = require("tau.ui.zen")

M.active = nil

function M.open(opts)
	opts = opts or {}
	local config = require("tau.config").get()
	local state = require("tau.state")

	if M._opening then
		vim.wait(10000, function()
			return not M._opening
		end, 1)
		if M._opening then
			error("tau: chat UI did not finish opening in time")
		end
		return M.open(opts)
	end
	if M.active and not layout.is_open(M.active.layout_state) then
		pcall(M.close)
	end

	if M.active and layout.is_open(M.active.layout_state) then
		if opts.resume then
			M.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
			local session = state.get_session(M.active.tau_tab_id)
			M.active.session = session
			history.refresh(M.active.hist_buf, session, M.active.config)
			history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
			M.refresh_winbar()
			layout.focus_prompt(M.active.layout_state)
			return M.active
		end
		require("tau").new_session({ silent = true })
		M.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
		local session = state.get_session(M.active.tau_tab_id)
		M.active.session = session
		history.refresh(M.active.hist_buf, session, M.active.config)
		history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
		M.refresh_winbar()
		layout.focus_prompt(M.active.layout_state)
		return M.active
	end

	M._opening = true
	local open_ok, open_result = pcall(function()
		local session
		if opts.resume then
			session = state.get_session()
			if not session then
				require("tau").new_session({ silent = true })
				session = state.get_session()
			end
		else
			require("tau").new_session({ silent = true })
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

		pcall(function()
			vim.wo[layout_state.history].winfixbuf = true
			vim.wo[layout_state.prompt].winfixbuf = true
			if layout_state.main and vim.api.nvim_win_is_valid(layout_state.main) then
				vim.wo[layout_state.main].winfixbuf = true
			end
		end)

		vim.wo[layout_state.history].wrap = true
		vim.wo[layout_state.history].linebreak = true
		vim.wo[layout_state.history].cursorline = false
		vim.wo[layout_state.history].number = false
		vim.wo[layout_state.history].relativenumber = false

		vim.wo[layout_state.prompt].wrap = true
		vim.wo[layout_state.prompt].number = false
		vim.wo[layout_state.prompt].relativenumber = false

		local function get_info_str()
			return require("tau.session_display").winbar_text(session)
		end

		if config.layout.side.panels.history.winbar then
			vim.wo[layout_state.history].winbar = " History " .. get_info_str()
		end
		if config.layout.side.panels.prompt.winbar then
			vim.wo[layout_state.prompt].winbar = " Prompt " .. get_info_str()
		end

		history.refresh(hist_buf, session, config)
		history.scroll_to_bottom(hist_buf, layout_state.history)

		vim.keymap.set("n", "i", function()
			layout.focus_prompt(layout_state)
			vim.cmd("startinsert")
		end, { buffer = hist_buf, silent = true, desc = "Focus prompt and insert" })

		vim.keymap.set("n", "a", function()
			layout.focus_prompt(layout_state)
			vim.cmd("startinsert")
		end, { buffer = hist_buf, silent = true, desc = "Focus prompt and insert" })

		vim.keymap.set("n", "o", function()
			layout.focus_prompt(layout_state)
			vim.cmd("startinsert")
		end, { buffer = hist_buf, silent = true, desc = "Focus prompt and insert" })

		vim.keymap.set("n", "<CR>", function()
			layout.focus_prompt(layout_state)
		end, { buffer = hist_buf, silent = true, desc = "Focus prompt" })

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

		local function is_tau_win(win)
			if not M.active then
				return false
			end
			local ls = M.active.layout_state
			return win == ls.history or win == ls.prompt
		end

		local function find_alt_win()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(win) and not is_tau_win(win) then
					return win
				end
			end
			return nil
		end

		local augroup = vim.api.nvim_create_augroup("tau_refresh", { clear = true })
		vim.api.nvim_create_autocmd("BufEnter", {
			group = augroup,
			callback = function()
				if M.active then
					M.refresh()
				end
			end,
		})

		vim.api.nvim_create_autocmd("BufWinEnter", {
			group = augroup,
			callback = function(args)
				if not M.active then
					return
				end
				local win = vim.api.nvim_get_current_win()
				if not is_tau_win(win) then
					return
				end
				local buf = args.buf
				if vim.bo[buf].buftype ~= "" then
					return
				end
				local ls = M.active.layout_state
				local tau_buf = win == ls.history and M.active.hist_buf or M.active.prompt_buf
				if buf == tau_buf then
					return
				end
				local alt = find_alt_win()
				if not alt then
					vim.cmd("wincmd p")
					alt = vim.api.nvim_get_current_win()
					if is_tau_win(alt) then
						vim.cmd("vsplit")
						alt = vim.api.nvim_get_current_win()
					end
				end
				vim.api.nvim_win_set_buf(alt, buf)
				vim.api.nvim_win_set_buf(win, tau_buf)
				vim.api.nvim_set_current_win(alt)
			end,
		})

		M.active = {
			layout_state = layout_state,
			hist_buf = hist_buf,
			prompt_buf = prompt_buf,
			session = session,
			tau_tab_id = vim.api.nvim_get_current_tabpage(),
			config = config,
			is_busy = false,
			augroup = augroup,
		}

		M.refresh_winbar()
		layout.focus_prompt(layout_state)

		return M.active
	end)
	M._opening = false
	if not open_ok then
		error(open_result)
	end
	return open_result
end

function M.close()
	if not M.active then
		return
	end

	M.prepare_session_switch()

	local session = require("tau.state").get_context_session()
	if session then
		queue.sync_to_session(session)
	end

	if M.active.augroup then
		vim.api.nvim_del_augroup_by_id(M.active.augroup)
	end

	zen.exit()

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

function M.refresh_winbar()
	if not M.active then
		return
	end
	local state = require("tau.state")
	local tid = M.active.tau_tab_id
	local session
	if tid then
		session = state.get_session(tid) or M.active.session
	else
		session = state.get_session()
	end
	if session then
		M.active.session = session
	else
		session = M.active.session
	end
	local info_str = require("tau.session_display").winbar_text(session)
	local layout_state = M.active.layout_state
	local config = M.active.config
	if layout_state.layout == "float" and layout_state.main and vim.api.nvim_win_is_valid(layout_state.main) then
		local short = "τ"
		if session and session.name and session.name ~= "" then
			short = session.name
		elseif session and session.id and session.id ~= "" then
			short = session.id
			if #short > 28 then
				short = short:sub(1, 25) .. "…"
			end
		end
		pcall(vim.api.nvim_win_set_config, layout_state.main, {
			title = " " .. short .. " ",
			title_pos = "center",
		})
	end
	if config.layout.side.panels.history.winbar then
		pcall(function()
			vim.wo[layout_state.history].winbar = " History " .. info_str
		end)
	end
	if config.layout.side.panels.prompt.winbar then
		pcall(function()
			vim.wo[layout_state.prompt].winbar = " Prompt " .. info_str
		end)
	end
end

function M.refresh()
	if not M.active then
		return
	end

	local state = require("tau.state")
	local tid = M.active.tau_tab_id
	local session
	if tid then
		session = state.get_session(tid) or M.active.session
	else
		session = state.get_session()
	end
	if not session and M.active.session then
		session = M.active.session
	end
	if session then
		M.active.session = session
	end
	history.refresh(M.active.hist_buf, session, M.active.config)
	history.scroll_to_bottom(M.active.hist_buf, M.active.layout_state.history)
	M.refresh_winbar()
end

function M.append_message(msg)
	if not M.active then
		return
	end

	local lines, extmarks = history.render_message(msg, M.active.config)
	history.append_lines(M.active.hist_buf, lines)

	local offset = vim.api.nvim_buf_line_count(M.active.hist_buf) - #lines
	for _, em in ipairs(extmarks) do
		vim.api.nvim_buf_add_highlight(
			M.active.hist_buf,
			vim.api.nvim_create_namespace("tau_history"),
			em.hl,
			em.line + offset,
			0,
			-1
		)
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
		local steer_session = require("tau.state").get_context_session()
		if steer_session then
			queue.sync_to_session(steer_session)
			require("tau.session").TauSessionAutosave(steer_session)
		end
		M.refresh_winbar()
		return
	end

	local session = require("tau.state").get_context_session()
	if not session then
		vim.notify("No active session", vim.log.levels.ERROR)
		return
	end

	local expanded = complete.expand_mentions(text)
	local invalid = complete.validate_mentions(expanded)
	if #invalid > 0 then
		vim.notify("Invalid file mentions: " .. table.concat(invalid, ", "), vim.log.levels.WARN)
	end

	local hist = require("tau.history")
	table.insert(session.messages, hist.user(expanded))
	require("tau.session").TauSessionAutosave(session)

	M.refresh()
	M.start_turn()
end

function M.start_turn()
	if not M.active then
		return
	end

	local session = require("tau.state").get_context_session()
	if not session then
		return
	end

	M.active.is_busy = true
	M.active.thinking_line_idx = nil
	M.active.busy_status_line_1 = nil
	queue.set_busy(true)
	M.start_busy()

	local provider = session.provider or require("tau.config").get().provider.name
	local streaming_text = ""
	local streaming_header_added = false
	local thinking_header_added = false
	local content_started = false
	local thinking_lines_start = nil
	local ns = vim.api.nvim_create_namespace("tau_thinking")
	local thinking_start_time = vim.uv.hrtime()
	local thinking_timer = nil

	local function format_elapsed(seconds)
		if seconds < 60 then
			return string.format("%.1fs", seconds)
		elseif seconds < 3600 then
			return string.format("%dm %ds", math.floor(seconds / 60), math.floor(seconds % 60))
		else
			return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
		end
	end

	local function stop_thinking_timer()
		if thinking_timer then
			thinking_timer:stop()
			thinking_timer:close()
			thinking_timer = nil
		end
		thinking_start_time = nil
	end

	local function update_thinking_line()
		-- Static "Working..." display, no updates needed
	end

	local function remove_thinking_line()
		if not M.active or not M.active.thinking_line_idx then
			return
		end
		stop_thinking_timer()
		local buf = M.active.hist_buf
		local idx = M.active.thinking_line_idx - 1
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, idx, idx + 1, false, {})
		vim.bo[buf].modifiable = false
		M.active.thinking_line_idx = nil
	end

	local function add_thinking_line(text)
		if not M.active then
			return
		end
		local buf = M.active.hist_buf
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)
		local line_text = text or "  🤖 Working..."
		vim.api.nvim_buf_set_lines(buf, count, count, false, { line_text })
		vim.bo[buf].modifiable = false
		M.active.thinking_line_idx = count + 1
	end

	local function ensure_streaming_header()
		if streaming_header_added or not M.active then
			return
		end
		if M.active.busy_status_line_1 and M.active.hist_buf and vim.api.nvim_buf_is_valid(M.active.hist_buf) then
			local buf = M.active.hist_buf
			local n = M.active.busy_status_line_1
			local nlines = vim.api.nvim_buf_line_count(buf)
			if n >= 1 and n <= nlines then
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, n - 1, n, false, {})
				vim.bo[buf].modifiable = false
			end
			M.active.busy_status_line_1 = nil
		end
		streaming_header_added = true
		local buf = M.active.hist_buf
		local label = M.active.config.labels.agent_response
		local ts = require("tau.ui.history").format_timestamp()
		remove_thinking_line()
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, count, count, false, {
			string.format("%s %s", label, ts),
			"",
		})
		vim.bo[buf].modifiable = false
		add_thinking_line()
	end

	local function append_thinking_chunk(chunk)
		if not M.active then
			return
		end
		if not M.active.config.show_thinking then
			return
		end
		ensure_streaming_header()
		local buf = M.active.hist_buf
		remove_thinking_line()
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)

		if not thinking_header_added then
			thinking_header_added = true
			vim.api.nvim_buf_set_lines(buf, count, count, false, { "  [think]" })
			thinking_lines_start = count
			count = count + 1
		end

		local last_line = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ""
		local lines = vim.split(chunk, "\n")
		lines[1] = last_line .. lines[1]
		vim.api.nvim_buf_set_lines(buf, count - 1, count, false, lines)

		local end_line = vim.api.nvim_buf_line_count(buf)
		for i = thinking_lines_start, end_line - 1 do
			vim.api.nvim_buf_add_highlight(buf, ns, "TauThinkingBlock", i, 0, -1)
		end

		vim.bo[buf].modifiable = false
		add_thinking_line()
		require("tau.ui.history").scroll_to_bottom(buf, M.active.layout_state.history)
	end

	local function append_streaming_chunk(chunk)
		if not M.active then
			return
		end
		ensure_streaming_header()
		local buf = M.active.hist_buf
		local lines = vim.split(chunk, "\n")
		if #lines == 0 then
			return
		end
		remove_thinking_line()
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)

		if thinking_header_added and not content_started then
			content_started = true
			local last_line = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ""
			if last_line ~= "" then
				vim.api.nvim_buf_set_lines(buf, count, count, false, { "" })
				count = count + 1
			end
		end

		local last_line = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ""
		lines[1] = last_line .. lines[1]
		vim.api.nvim_buf_set_lines(buf, count - 1, count, false, lines)
		vim.bo[buf].modifiable = false
		add_thinking_line()
		require("tau.ui.history").scroll_to_bottom(buf, M.active.layout_state.history)
	end

	require("tau.dispatcher").run_turn_streaming(provider, session.messages, {
		model = session.model,
		thinking_level = require("tau.models").get_thinking_level(),
		on_text = function(chunk)
			if not M.active then
				return
			end
			streaming_text = streaming_text .. chunk
			append_streaming_chunk(chunk)
		end,
		on_thinking = function(chunk)
			if not M.active then
				return
			end
			append_thinking_chunk(chunk)
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
		on_error = function(err)
			if not M.active then
				return
			end
			table.insert(session.messages, {
				role = "system",
				content = err,
			})
			M.finish_turn()
		end,
		on_done = function()
			M.finish_turn()
		end,
	})
end

function M.stop_turn()
	if not M.active then
		return
	end
	require("tau.dispatcher").stop()
	M.finish_turn()
end

function M.prepare_session_switch()
	require("tau.dispatcher").stop()
	if not M.active then
		return
	end
	M.active.is_busy = false
	queue.set_busy(false)
	M.stop_busy()
end

function M.finish_turn()
	if not M.active then
		return
	end

	M.active.is_busy = false
	queue.set_busy(false)
	M.stop_busy()

	local session = require("tau.state").get_context_session()
	if session then
		require("tau.state").update_session_tokens()
		require("tau.session").TauSessionAutosave(session)
		require("tau.session_title").maybe_apply(session)
	end

	if queue.size() > 0 then
		local next_msg = queue.pop()
		if next_msg and next_msg.text then
			if session then
				require("tau.session").TauSessionAutosave(session)
			end
			vim.defer_fn(function()
				M.on_submit(next_msg.text)
			end, 100)
			return
		end
	end

	M.refresh()
end

function M.start_busy()
	if not M.active or M.active.busy_status_line_1 then
		return
	end

	local buf = M.active.hist_buf
	local spinner = require("tau.ui.spinner")
	local config = require("tau.config").get()
	
	pcall(function()
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, count, count, false, { "  🤖 Working..." })
		vim.bo[buf].modifiable = false
		M.active.busy_status_line_1 = vim.api.nvim_buf_line_count(buf)
		
		M.active.spinner = spinner.start({
			spinner = config.spinner or "robot",
			interval = config.spinner_interval or 120,
			on_update = function(frame)
				if not M.active or not M.active.busy_status_line_1 then
					return
				end
				pcall(function()
					vim.bo[buf].modifiable = true
					local line_idx = M.active.busy_status_line_1 - 1
					vim.api.nvim_buf_set_lines(buf, line_idx, line_idx + 1, false, { "  " .. frame .. " Working..." })
					vim.bo[buf].modifiable = false
				end)
			end,
		})
	end)
end

function M.stop_busy()
	if not M.active then
		return
	end

	if M.active.spinner then
		M.active.spinner.stop()
		M.active.spinner = nil
	end

	M.active.busy_status_line_1 = nil

	if M.active.thinking_line_idx then
		local b = M.active.hist_buf
		pcall(function()
			vim.bo[b].modifiable = true
			local count = vim.api.nvim_buf_line_count(b)
			vim.api.nvim_buf_set_lines(b, count - 1, count, false, {})
			vim.bo[b].modifiable = false
		end)
		M.active.thinking_line_idx = nil
	end
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
