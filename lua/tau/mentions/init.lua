local M = {}

local providers = {}
local default_name = "files"

function M.ensure_default()
	if not providers[default_name] then
		M.register(require("tau.mentions.providers.files").create())
	end
end

function M.register(provider)
	if not provider or not provider.name then
		error("mention provider must have a name")
	end
	providers[provider.name] = provider
end

function M.get(name)
	M.ensure_default()
	return providers[name]
end

function M.list_names()
	M.ensure_default()
	local n = {}
	for k in pairs(providers) do
		table.insert(n, k)
	end
	table.sort(n)
	return n
end

function M.get_active()
	M.ensure_default()
	local cfg = require("tau.config").get()
	local name = cfg.mention_provider or default_name
	local p = providers[name]
	if not p then
		vim.notify(
			"tau: unknown mention_provider '" .. tostring(name) .. "', using " .. default_name,
			vim.log.levels.WARN
		)
		return providers[default_name], default_name
	end
	return p, name
end

function M.build_ctx()
	local session = require("tau.state").get_session()
	return {
		cwd = vim.fn.getcwd(),
		session_cwd = session and session.cwd or nil,
	}
end

function M.completefunc(findstart, base)
	M.ensure_default()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local trigger = ""

	if findstart == 1 then
		local col1 = col + 1
		for i = col1, 1, -1 do
			local ch = line:sub(i, i)
			if ch == "@" then
				return i - 1
			end
			if ch == " " or ch == "\t" then
				return -2
			end
		end
		return -2
	end

	for i = math.min(col + 1, #line), 1, -1 do
		local ch = line:sub(i, i)
		if ch == "@" then
			trigger = "@"
			break
		end
	end

	local ctx = M.build_ctx()
	local p = M.get_active()
	local files = providers.files

	if trigger == "@" then
		local at = p.complete_at or (files and files.complete_at)
		if at then
			return at(findstart, base, ctx)
		end
	end

	return {}
end

function M.expand(text)
	local p = select(1, M.get_active())
	local files = providers.files
	local fn = p.expand or (files and files.expand)
	if not fn then
		return text
	end
	return fn(text, M.build_ctx())
end

function M.validate(text)
	local p = select(1, M.get_active())
	local files = providers.files
	local fn = p.validate or (files and files.validate)
	if not fn then
		return {}
	end
	return fn(text, M.build_ctx())
end

function M.insert_from_editor(opts)
	local p = select(1, M.get_active())
	local files = providers.files
	local fn = p.insert_from_editor or (files and files.insert_from_editor)
	if not fn then
		return nil
	end
	return fn(opts or {}, M.build_ctx())
end

function M.insert_into_prompt(opts)
	local text = M.insert_from_editor(opts)
	if not text then
		return false
	end
	local ui = require("tau.ui")
	if not ui.active then
		ui.open()
	end
	ui.focus_prompt()
	local buf = ui.active.prompt_buf
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 then
		lines = { text }
	else
		local last = lines[#lines] or ""
		if vim.trim(last) ~= "" then
			lines[#lines] = last .. " " .. text
		else
			lines[#lines] = text
		end
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return true
end

function M.init(opts)
	opts = opts or {}
	M.register(require("tau.mentions.providers.files").create())
	for _, mod in ipairs(opts.mention_plugins or {}) do
		local ok, err = pcall(function()
			require(mod)
		end)
		if not ok then
			vim.notify("tau mentions: failed to load " .. tostring(mod) .. ": " .. tostring(err), vim.log.levels.WARN)
		end
	end
end

return M
