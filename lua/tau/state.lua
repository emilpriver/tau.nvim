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

function M.set_session(tab_id, session)
	tab_id = tab_id or vim.api.nvim_get_current_tabpage()
	M.sessions[tab_id] = session
end

function M.clear_session(tab_id)
	tab_id = tab_id or vim.api.nvim_get_current_tabpage()
	M.sessions[tab_id] = nil
end

function M.create_session(opts)
	opts = opts or {}
	return {
		id = opts.id or vim.fn.strftime("%Y%m%d-%H%M%S") .. "-" .. vim.fn.rand(),
		cwd = opts.cwd or vim.fn.getcwd(),
		name = opts.name or nil,
		messages = opts.messages or {},
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
