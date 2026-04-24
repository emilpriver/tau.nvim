local M = {}

local layout = require("tau.ui.layout")

local function store()
	require("tau.session_storage").TauEnsureBuiltinRegistered()
	return select(1, require("tau.session_storage").TauGetSessionStorage())
end

function M.TauSessionAutosave(session)
	if not session then
		return false, "no session"
	end
	local ok, err = store().save_session(session)
	if not ok then
		vim.notify(tostring(err or "session save failed"), vim.log.levels.WARN)
	end
	return ok, err
end

function M.load_most_recent(cwd)
	cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
	local list = store().list_sessions(cwd)
	if not list or #list == 0 then
		vim.notify("No saved sessions for this directory", vim.log.levels.WARN)
		return
	end
	local top = list[1]
	local session = store().load_session(cwd, top.id)
	if not session then
		vim.notify("Failed to load session", vim.log.levels.ERROR)
		return
	end
	require("tau.state").set_session(nil, session)
	local ui = require("tau.ui")
	if ui.active and layout.is_open(ui.active.layout_state) then
		ui.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
		ui.active.session = session
		ui.refresh()
	else
		ui.open({ resume = true })
	end
	vim.notify("Continued session " .. (session.name or session.id), vim.log.levels.INFO)
end

function M.pick_and_load(cwd)
	cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
	local list = store().list_sessions(cwd)
	if not list or #list == 0 then
		vim.notify("No saved sessions for this directory", vim.log.levels.WARN)
		return
	end
	local active_s = require("tau.state").get_session()
	local labels = {}
	for _, item in ipairs(list) do
		local name = item.name and item.name ~= "" and item.name or item.id
		local ts = item.updated_at or item.created_at
		local t = ts and ts > 0 and os.date("%Y-%m-%d %H:%M", ts) or "?"
		local marker = active_s and active_s.id == item.id and "> " or "  "
		table.insert(
			labels,
			string.format("%s%s  |  edited %s  |  %d msgs", marker, name, t, item.message_count or 0)
		)
	end
	vim.ui.select(labels, {
		prompt = "Select session",
	}, function(_, idx)
		if not idx then
			return
		end
		local item = list[idx]
		if not item then
			return
		end
		local session = store().load_session(cwd, item.id)
		if not session then
			vim.notify("Failed to load session", vim.log.levels.ERROR)
			return
		end
		require("tau.state").set_session(nil, session)
		local ui = require("tau.ui")
		if ui.active and layout.is_open(ui.active.layout_state) then
			ui.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
			ui.active.session = session
			ui.refresh()
		else
			ui.open({ resume = true })
		end
		vim.notify("Loaded session " .. (session.name or session.id), vim.log.levels.INFO)
	end)
end

function M.TauSessionSetName(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		vim.notify("TauSessionSetName: empty name", vim.log.levels.WARN)
		return
	end
	local session = require("tau.state").get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	session.name = name
	M.TauSessionAutosave(session)
	vim.notify("Session name set", vim.log.levels.INFO)
end

function M.TauSessionEnd()
	require("tau.dispatcher").stop()
	require("tau.ui").close()
	require("tau.state").clear_session()
	vim.notify("Tau session ended", vim.log.levels.INFO)
end

local function html_escape(s)
	if type(s) ~= "string" then
		return ""
	end
	return s
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
end

function M.TauSessionExportHtml(path)
	path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if path == "" then
		vim.notify("TauSessionExportHtml: need file path", vim.log.levels.WARN)
		return
	end
	local session = require("tau.state").get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	local lines = {
		"<!DOCTYPE html>",
		"<html><head><meta charset=\"utf-8\"><title>"
			.. html_escape(session.name or session.id)
			.. "</title></head><body>",
		"<h1>"
			.. html_escape(session.name or session.id)
			.. "</h1>",
		"<pre>",
	}
	for _, msg in ipairs(session.messages or {}) do
		local role = html_escape(tostring(msg.role or "?"))
		local content = msg.content
		if type(content) == "string" then
			content = html_escape(content)
		else
			content = html_escape(vim.json.encode(content))
		end
		table.insert(lines, "[" .. role .. "]\n" .. content .. "\n")
	end
	table.insert(lines, "</pre></body></html>")
	vim.fn.writefile(lines, path)
	vim.notify("Exported to " .. path, vim.log.levels.INFO)
end

function M.TauSessionInfo()
	local session = require("tau.state").get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	require("tau.state").update_session_tokens()
	local path = session._storage_path or "not saved yet"
	local n = #(session.messages or {})
	local cost = session.cost_usd
	local cost_str = cost and tostring(cost) or "n/a"
	local lines = {
		"id: " .. tostring(session.id),
		"name: " .. tostring(session.name or ""),
		"cwd: " .. tostring(session.cwd),
		"file: " .. tostring(path),
		"messages: " .. tostring(n),
		"tokens: " .. tostring(session.tokens_used or 0) .. " / " .. tostring(session.context_limit or 0),
		"cost_usd: " .. cost_str,
	}
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.TauSessionFork(message_index)
	local state = require("tau.state")
	local session = state.get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	local msgs = session.messages or {}
	local n = #msgs
	if n == 0 then
		vim.notify("No messages to fork from", vim.log.levels.WARN)
		return
	end
	message_index = message_index or n
	if message_index < 1 or message_index > n then
		vim.notify("Invalid message index", vim.log.levels.WARN)
		return
	end
	local tauConfig = require("tau.config").get()
	local agents = require("tau.agents")
	local parent_id = session.id
	local new_msgs = {}
	for i = 1, message_index do
		table.insert(new_msgs, vim.deepcopy(msgs[i]))
	end
	local new_session = state.create_session({
		cwd = session.cwd,
		provider = session.provider or tauConfig.provider.name,
		model = session.model or tauConfig.provider.model,
		messages = new_msgs,
		parent_id = parent_id,
	})
	new_session._storage_path = nil
	state.set_session(nil, new_session)
	M.TauSessionAutosave(new_session)
	local ui = require("tau.ui")
	if ui.active then
		ui.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
		ui.active.session = new_session
		ui.refresh()
	end
	vim.notify("Forked session from message " .. tostring(message_index), vim.log.levels.INFO)
end

function M.TauSessionClone()
	local state = require("tau.state")
	local session = state.get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	local tauConfig = require("tau.config").get()
	local new_session = state.create_session({
		cwd = session.cwd,
		provider = session.provider or tauConfig.provider.name,
		model = session.model or tauConfig.provider.model,
		messages = vim.deepcopy(session.messages or {}),
		parent_id = session.parent_id,
	})
	new_session.name = session.name and (session.name .. " (copy)") or nil
	new_session._storage_path = nil
	state.set_session(nil, new_session)
	M.TauSessionAutosave(new_session)
	local ui = require("tau.ui")
	if ui.active then
		ui.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
		ui.active.session = new_session
		ui.refresh()
	end
	vim.notify("Cloned session", vim.log.levels.INFO)
end

function M.TauSessionTree()
	local state = require("tau.state")
	local session = state.get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	local msgs = session.messages or {}
	local choices = {}
	local indices = {}
	for i, msg in ipairs(msgs) do
		if msg.role == "user" or msg.role == "assistant" then
			local preview = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content)
			preview = preview:gsub("\n", " ")
			if #preview > 60 then
				preview = preview:sub(1, 60) .. "…"
			end
			table.insert(choices, string.format("%d [%s] %s", i, msg.role, preview))
			table.insert(indices, i)
		end
	end
	if #choices == 0 then
		vim.notify("No user/assistant messages in tree", vim.log.levels.WARN)
		return
	end
	vim.ui.select(choices, { prompt = "Continue from message (fork)" }, function(_, idx)
		if idx then
			M.TauSessionFork(indices[idx])
		end
	end)
end

return M
