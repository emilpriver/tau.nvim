local M = {}

M.sessions = {}
M.current_tab = nil
M.active_tab_id = nil

function M.init()
	M.sessions = {}
	M.current_tab = vim.api.nvim_get_current_tabpage()
end

function M.get_session(tab_id)
	tab_id = tab_id or vim.api.nvim_get_current_tabpage()
	return M.sessions[tab_id]
end

function M.get_context_session()
	local ui_mod = rawget(package.loaded, "tau.ui")
	if ui_mod and ui_mod.active and ui_mod.active.tau_tab_id then
		local s = M.get_session(ui_mod.active.tau_tab_id)
		if s then
			return s
		end
	end
	return M.get_session()
end

function M.set_session(tab_id, session)
	tab_id = tab_id or vim.api.nvim_get_current_tabpage()
	local prev = M.sessions[tab_id]
	if prev ~= session then
		local ui_mod = rawget(package.loaded, "tau.ui")
		if ui_mod and ui_mod.prepare_session_switch then
			ui_mod.prepare_session_switch()
		end
	end
	M.sessions[tab_id] = session
end

function M.clear_session(tab_id)
	tab_id = tab_id or vim.api.nvim_get_current_tabpage()
	if M.sessions[tab_id] ~= nil then
		local ui_mod = rawget(package.loaded, "tau.ui")
		if ui_mod and ui_mod.prepare_session_switch then
			ui_mod.prepare_session_switch()
		end
	end
	M.sessions[tab_id] = nil
end

function M.create_session(opts)
	opts = opts or {}
	local h = vim.loop.hrtime() or 0
	local suffix = string.format("%012x", h % 0xFFFFFFFFFFFF)
	return {
		id = opts.id or (vim.fn.strftime("%Y%m%d-%H%M%S") .. "-" .. suffix),
		cwd = opts.cwd or vim.fn.getcwd(),
		name = opts.name or nil,
		parent_id = opts.parent_id,
		messages = opts.messages or {},
		queue = opts.queue or {},
		model = opts.model or require("tau.config").get().provider.model,
		provider = opts.provider or require("tau.config").get().provider.name,
		tokens_used = 0,
		context_limit = 0,
		compacted_count = 0,
		created_at = vim.fn.localtime(),
		updated_at = vim.fn.localtime(),
	}
end

function M.update_session_tokens(tab_id)
	local session = M.get_session(tab_id)
	if not session then
		return
	end

	local context = require("tau.context")
	local model = session.model or require("tau.config").get().provider.model
	session.tokens_used = context.count_messages_tokens(session.messages)
	session.context_limit = context.get_context_limit(model)
	session.updated_at = vim.fn.localtime()
end

function M.get_token_info(tab_id)
	local session = M.get_session(tab_id)
	if not session then
		return nil
	end

	M.update_session_tokens(tab_id)

	return {
		used = session.tokens_used,
		limit = session.context_limit,
		ratio = session.context_limit > 0 and session.tokens_used / session.context_limit or 0,
		compacted = session.compacted_count,
	}
end

return M
