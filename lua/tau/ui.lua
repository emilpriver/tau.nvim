local M = {}

local layout = require("tau.ui.layout")
local history = require("tau.ui.history")
local prompt = require("tau.ui.prompt")
local spinner = require("tau.ui.spinner")
local complete = require("tau.ui.complete")
local queue = require("tau.ui.queue")
local zen = require("tau.ui.zen")

M.active = nil

function M.open(opts)
	opts = opts or {}
	local config = require("tau.config").get()
	local state = require("tau.state")

	if M.active and layout.is_open(M.active.layout_state) then
		layout.focus_prompt(M.active.layout_state)
		return M.active
	end

	local session = state.get_session()
	if not session then
		require("tau").new_session()
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
		local cfg = require("tau.config").get()
		local provider_name = session and session.provider or cfg.provider.name or "default"
		local model = session and session.model or cfg.provider.model
		if not model then
			model = require("tau.models").get_active()
		end
		if not model then
			local plugin = require("tau.plugin").get_provider(provider_name)
			if plugin then
				model = plugin.default_model
			end
		end
		if not model then
			local fallback = require("tau.plugin").get_fallback_models(provider_name)
			if fallback and #fallback > 0 then
				model = fallback[1]
			end
		end
		return string.format(" %s | %s ", provider_name, model or "default")
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

	local augroup = vim.api.nvim_create_augroup("tau_refresh", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = function()
			if M.active then
				M.refresh()
			end
		end,
	})

	M.active = {
		layout_state = layout_state,
		hist_buf = hist_buf,
		prompt_buf = prompt_buf,
		session = session,
		config = config,
		spinner_handle = nil,
		is_busy = false,
		augroup = augroup,
	}

	layout.focus_prompt(layout_state)

	return M.active
end

function M.close()
	if not M.active then
		return
	end

	if M.active.is_busy then
		require("tau.dispatcher").stop()
		queue.set_busy(false)
	end

	if M.active.augroup then
		vim.api.nvim_del_augroup_by_id(M.active.augroup)
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

function M.refresh_winbar()
	if not M.active then
		return
	end
	local session = M.active.session
	local cfg = require("tau.config").get()
	local provider_name = session and session.provider or cfg.provider.name or "default"
	local model = session and session.model or cfg.provider.model
	if not model then
		model = require("tau.models").get_active()
	end
	if not model then
		local plugin = require("tau.plugin").get_provider(provider_name)
		if plugin then
			model = plugin.default_model
		end
	end
	if not model then
		local fallback = require("tau.plugin").get_fallback_models(provider_name)
		if fallback and #fallback > 0 then
			model = fallback[1]
		end
	end
	local info_str = string.format(" %s | %s ", provider_name, model or "default")
	local layout_state = M.active.layout_state
	local config = M.active.config
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

	local session = require("tau.state").get_session()
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
		M.refresh()
		return
	end

	local session = require("tau.state").get_session()
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

	M.refresh()
	M.start_turn()
end

function M.start_turn()
	if not M.active then
		return
	end

	local session = require("tau.state").get_session()
	if not session then
		return
	end

	M.active.is_busy = true
	M.active.thinking_line_idx = nil
	queue.set_busy(true)
	M.start_busy()

	local provider = session.provider or require("tau.config").get().provider.name
	local streaming_text = ""
	local streaming_header_added = false
	local thinking_header_added = false
	local content_started = false
	local thinking_lines_start = nil
	local ns = vim.api.nvim_create_namespace("tau_thinking")

	local function remove_thinking_line()
		if not M.active or not M.active.thinking_line_idx then
			return
		end
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
		vim.api.nvim_buf_set_lines(buf, count, count, false, { text or "  🤖 Thinking..." })
		vim.bo[buf].modifiable = false
		M.active.thinking_line_idx = count + 1
	end

	local function ensure_streaming_header()
		if streaming_header_added or not M.active then
			return
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

function M.finish_turn()
	if not M.active then
		return
	end

	M.active.is_busy = false
	queue.set_busy(false)
	M.stop_busy()
	M.refresh()
	require("tau.state").update_session_tokens()

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
	local buf = M.active.hist_buf

	pcall(function()
		vim.bo[buf].modifiable = true
		local count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, count, count, false, { "  🤖 Thinking..." })
		vim.bo[buf].modifiable = false
	end)

	M.active.spinner_handle = spinner.start({
		spinner = config.spinner,
		on_update = function(frame)
			if not M.active or not M.active.hist_buf then
				return
			end
			local elapsed = vim.fn.localtime() - start_time
			local mins = math.floor(elapsed / 60)
			local secs = elapsed % 60
			local time_str = string.format("%02d:%02d", mins, secs)
			local text = string.format("  🤖 %s Thinking... %s", frame, time_str)
			local b = M.active.hist_buf
			pcall(function()
				vim.bo[b].modifiable = true
				local count = vim.api.nvim_buf_line_count(b)
				vim.api.nvim_buf_set_lines(b, count - 1, count, false, { text })
				vim.bo[b].modifiable = false
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
