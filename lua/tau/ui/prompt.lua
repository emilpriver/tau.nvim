local M = {}

local at_retrigger_timers = {}

local function stop_at_retrigger(buf)
	local id = at_retrigger_timers[buf]
	if id then
		pcall(vim.fn.timer_stop, id)
		at_retrigger_timers[buf] = nil
	end
end

local function attach_at_completion_retrigger(buf)
	stop_at_retrigger(buf)
	local ag = vim.api.nvim_create_augroup("tau_prompt_at_" .. tostring(buf), { clear = true })
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = ag,
		buffer = buf,
		callback = function()
			if vim.fn.pumvisible() == 1 then
				return
			end
			local line = vim.api.nvim_get_current_line()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			local before = line:sub(1, col)
			local after_at_pos = before:match(".*@()")
			if not after_at_pos then
				return
			end
			local after_at = before:sub(after_at_pos)
			if after_at == "" or after_at:find("%s") then
				return
			end
			stop_at_retrigger(buf)
			at_retrigger_timers[buf] = vim.fn.timer_start(50, 0, function()
				at_retrigger_timers[buf] = nil
				vim.schedule(function()
					if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
						return
					end
					if vim.fn.mode() ~= "i" or vim.fn.pumvisible() == 1 then
						return
					end
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-u>", true, true, true), "m", false)
				end)
			end)
		end,
	})
end

function M.create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "tau-prompt"
	return buf
end

function M.get_text(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

function M.clear(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

function M.set_keymaps(buf, callbacks)
	callbacks = callbacks or {}

	local opts = { buffer = buf, silent = true }

	vim.keymap.set({ "n", "i" }, "<C-CR>", function()
		local text = M.get_text(buf)
		if text and text:gsub("%s", "") ~= "" then
			if callbacks.on_submit then
				callbacks.on_submit(text)
			end
			M.clear(buf)
		end
	end, vim.tbl_extend("force", opts, { desc = "Submit prompt" }))

	vim.keymap.set("n", "<CR>", function()
		local text = M.get_text(buf)
		if text and text:gsub("%s", "") ~= "" then
			if callbacks.on_submit then
				callbacks.on_submit(text)
			end
			M.clear(buf)
		end
	end, vim.tbl_extend("force", opts, { desc = "Submit prompt" }))

	vim.keymap.set("i", "<CR>", "<CR>", opts)

	vim.keymap.set("n", "q", function()
		if callbacks.on_close then
			callbacks.on_close()
		end
	end, vim.tbl_extend("force", opts, { desc = "Close chat" }))

	vim.keymap.set("n", "<Esc>", function()
		if callbacks.on_close then
			callbacks.on_close()
		end
	end, vim.tbl_extend("force", opts, { desc = "Close chat" }))

	vim.keymap.set({ "n", "i" }, "<C-h>", function()
		if callbacks.on_focus_history then
			callbacks.on_focus_history()
		end
	end, vim.tbl_extend("force", opts, { desc = "Focus history" }))

	vim.keymap.set({ "n", "i" }, "<C-z>", function()
		if callbacks.on_zen then
			callbacks.on_zen()
		end
	end, vim.tbl_extend("force", opts, { desc = "Toggle zen mode" }))
end

local function merge_blink_tau_provider()
	pcall(function()
		require("blink.cmp.config").merge_with({
			sources = {
				providers = {
					tau_mentions = {
						name = "Tau mentions",
						module = "tau.integrations.blink",
						min_keyword_length = 0,
						score_offset = 100,
					},
				},
				per_filetype = {
					["tau-prompt"] = { "tau_mentions", inherit_defaults = true },
				},
			},
		})
	end)
end

local function blink_tau_provider_configured()
	local ok, cfg = pcall(require, "blink.cmp.config")
	if not ok or not cfg or not cfg.sources or not cfg.sources.providers then
		return false
	end
	return cfg.sources.providers.tau_mentions ~= nil
end

function M.set_completefunc(buf)
	merge_blink_tau_provider()
	local use_blink = blink_tau_provider_configured()

	local function ensure_prompt_completion()
		if not use_blink then
			local ok_cmp, cmp = pcall(require, "cmp")
			if ok_cmp and cmp and cmp.setup and cmp.setup.buffer then
				cmp.setup.buffer({ enabled = false })
			end
		end
		vim.bo.completefunc = "v:lua.__tau_completefunc"
		local ok = pcall(function()
			vim.bo.completeopt = "menuone,noinsert,popup"
		end)
		if not ok then
			vim.bo.completeopt = "menuone,noinsert"
		end
	end

	vim.api.nvim_buf_call(buf, ensure_prompt_completion)

	local guard = vim.api.nvim_create_augroup("tau_prompt_complete_guard_" .. tostring(buf), { clear = true })
	vim.api.nvim_create_autocmd({ "InsertEnter", "BufWinEnter" }, {
		group = guard,
		buffer = buf,
		callback = function()
			vim.api.nvim_buf_call(buf, ensure_prompt_completion)
		end,
	})

	if not use_blink then
		local map_opts = { buffer = buf, remap = true, silent = true }
		vim.keymap.set("i", "@", "@<C-x><C-u>", map_opts)
		vim.keymap.set("i", "<C-Space>", "<C-x><C-u>", map_opts)
		attach_at_completion_retrigger(buf)
	end
end

function M.set_statusline(win, text)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	text = text:gsub("[^%x20-%x7E]", "")
	pcall(function()
		vim.api.nvim_win_call(win, function()
			vim.wo.statusline = text
		end)
	end)
end

function M.build_statusline(session, config)
	if not session then
		return " tau "
	end

	local parts = {}
	local model = session.model or "default"
	table.insert(parts, " " .. model .. " ")

	local thinking = require("tau.models").get_thinking_level()
	if thinking and thinking ~= "off" then
		table.insert(parts, "[think:" .. thinking .. "]")
	end

	local ctx = require("tau.state").get_token_info()
	if ctx then
		local pct = math.floor(ctx.ratio * 100)
		table.insert(parts, string.format(" %d%% (%d/%d)", pct, ctx.used, ctx.limit))
	end

	return table.concat(parts, " ")
end

return M
