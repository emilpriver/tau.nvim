local M = {}

local registry = {}
local active = nil
local BUILTIN = "jsonl"

local function ensure_dirs(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

local function cwd_key(cwd)
	cwd = vim.fs.normalize(cwd or "")
	local sum = 5381
	local cap = math.min(#cwd, 8192)
	for i = 1, cap do
		sum = (sum * 33 + string.byte(cwd, i)) % 2147483647
	end
	return string.format("%08x", sum)
end

local function sessions_root()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "tau", "sessions")
end

local function session_file_path(cwd, session_id)
	local key = cwd_key(cwd)
	local safe_id = session_id:gsub("[^%w%-_%.]", "_")
	return vim.fs.joinpath(sessions_root(), key, safe_id .. ".jsonl")
end

function M.TauRegisterSessionStorage(name, provider)
	if type(name) ~= "string" or name == "" then
		vim.notify("TauRegisterSessionStorage: invalid name", vim.log.levels.ERROR)
		return
	end
	if type(provider) ~= "table" then
		vim.notify("TauRegisterSessionStorage: provider must be a table", vim.log.levels.ERROR)
		return
	end
	for _, key in ipairs({ "list_sessions", "load_session", "save_session", "delete_session" }) do
		if type(provider[key]) ~= "function" then
			vim.notify(
				"TauRegisterSessionStorage: provider must implement " .. key,
				vim.log.levels.ERROR
			)
			return
		end
	end
	registry[name] = provider
	if not active then
		active = name
	end
end

function M.TauSetSessionStorage(name)
	if not registry[name] then
		vim.notify("Tau: unknown session storage '" .. tostring(name) .. "'", vim.log.levels.ERROR)
		return false
	end
	active = name
	return true
end

function M.TauGetSessionStorage()
	if not active or not registry[active] then
		M.TauEnsureBuiltinRegistered()
	end
	return registry[active], active
end

function M.TauListSessionStorageNames()
	local names = {}
	for k in pairs(registry) do
		table.insert(names, k)
	end
	table.sort(names)
	return names
end

local builtin = {}

function builtin.read_meta(path)
	local lines = vim.fn.readfile(path)
	if not lines or #lines == 0 then
		return nil
	end
	local ok, obj = pcall(vim.json.decode, lines[1])
	if ok and obj and obj.kind == "session" then
		return obj
	end
	return nil
end

function builtin.list_sessions(cwd)
	cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
	local dir = vim.fs.joinpath(sessions_root(), cwd_key(cwd))
	if vim.fn.isdirectory(dir) == 0 then
		return {}
	end
	local files = vim.fn.globpath(dir, "*.jsonl", false, true)
	if type(files) == "string" then
		files = { files }
	end
	local out = {}
	for _, path in ipairs(files) do
		if path ~= "" then
			local meta = builtin.read_meta(path)
			if meta and vim.fs.normalize(meta.cwd or "") == cwd then
				local raw = vim.fn.readfile(path)
				local msg_count = 0
				for i = 2, #raw do
					local line = raw[i]
					if line and line ~= "" then
						local ok, obj = pcall(vim.json.decode, line)
						if ok and obj and obj.kind == "message" then
							msg_count = msg_count + 1
						end
					end
				end
				table.insert(out, {
					id = meta.id,
					name = meta.name,
					cwd = meta.cwd,
					created_at = meta.created_at or 0,
					updated_at = meta.updated_at or meta.created_at or 0,
					message_count = msg_count,
					path = path,
				})
			end
		end
	end
	table.sort(out, function(a, b)
		local ua = a.updated_at or 0
		local ub = b.updated_at or 0
		if ua ~= ub then
			return ua > ub
		end
		return (a.created_at or 0) > (b.created_at or 0)
	end)
	return out
end

function builtin.load_session(cwd, session_id)
	local path = session_file_path(cwd, session_id)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local lines = vim.fn.readfile(path)
	local session_meta = nil
	local messages = {}
	for _, line in ipairs(lines) do
		if line ~= "" then
			local ok, obj = pcall(vim.json.decode, line)
			if ok and obj then
				if obj.kind == "session" then
					session_meta = obj
				elseif obj.kind == "message" and obj.msg then
					table.insert(messages, obj.msg)
				end
			end
		end
	end
	if not session_meta then
		return nil
	end
	local loaded_name = session_meta.name
	if type(loaded_name) ~= "string" or loaded_name == "" then
		loaded_name = nil
	end
	return {
		id = session_meta.id,
		cwd = session_meta.cwd,
		name = loaded_name,
		parent_id = session_meta.parent_id,
		messages = messages,
		queue = type(session_meta.queue) == "table" and session_meta.queue or {},
		model = session_meta.model,
		provider = session_meta.provider,
		tokens_used = session_meta.tokens_used or 0,
		context_limit = session_meta.context_limit or 0,
		compacted_count = session_meta.compacted_count or 0,
		created_at = session_meta.created_at,
		updated_at = session_meta.updated_at,
		cost_usd = session_meta.cost_usd,
		_storage_path = path,
	}
end

function builtin.save_session(session)
	if not session or not session.id or not session.cwd then
		return false, "no session"
	end
	session.updated_at = vim.fn.localtime()
	local path = session._storage_path or session_file_path(session.cwd, session.id)
	session._storage_path = path
	ensure_dirs(path)
	local context = require("tau.context")
	local model = session.model or require("tau.config").get().provider.model
	session.tokens_used = context.count_messages_tokens(session.messages or {})
	session.context_limit = context.get_context_limit(model)
	local name_str = nil
	if type(session.name) == "string" and session.name ~= "" then
		name_str = session.name
	end
	local head = {
		kind = "session",
		id = session.id,
		cwd = session.cwd,
		name = name_str,
		parent_id = session.parent_id,
		queue = session.queue or {},
		model = session.model,
		provider = session.provider,
		tokens_used = session.tokens_used,
		context_limit = session.context_limit,
		compacted_count = session.compacted_count or 0,
		created_at = session.created_at,
		updated_at = session.updated_at,
		cost_usd = session.cost_usd,
	}
	local lines = { vim.json.encode(head) }
	for _, msg in ipairs(session.messages or {}) do
		table.insert(lines, vim.json.encode({ kind = "message", msg = msg }))
	end
	local wok, werr = pcall(vim.fn.writefile, lines, path, "s")
	if not wok then
		wok, werr = pcall(vim.fn.writefile, lines, path)
	end
	if not wok then
		return false, tostring(werr or "writefile failed")
	end
	if name_str then
		local verify = vim.fn.readfile(path)
		if not verify or verify[1] == nil or verify[1] == "" then
			return false, "session file empty after write"
		end
		local dec_ok, meta = pcall(vim.json.decode, verify[1])
		if not dec_ok or type(meta) ~= "table" or meta.kind ~= "session" then
			return false, "session header corrupt after write"
		end
		if meta.name ~= name_str then
			return false, "session name missing in file (got " .. tostring(meta.name) .. ")"
		end
	end
	return true
end

function builtin.delete_session(cwd, session_id)
	local path = session_file_path(cwd, session_id)
	if vim.fn.filereadable(path) == 1 then
		vim.fn.delete(path)
		return true
	end
	return false
end

function M.TauEnsureBuiltinRegistered()
	if registry[BUILTIN] then
		if not active then
			active = BUILTIN
		end
		return
	end
	registry[BUILTIN] = {
		list_sessions = function(cwd)
			return builtin.list_sessions(cwd)
		end,
		load_session = function(cwd, sid)
			return builtin.load_session(cwd, sid)
		end,
		save_session = function(s)
			return builtin.save_session(s)
		end,
		delete_session = function(cwd, sid)
			return builtin.delete_session(cwd, sid)
		end,
	}
	if not active then
		active = BUILTIN
	end
end

M._sessions_root = sessions_root
M._cwd_key = cwd_key
M._session_file_path = session_file_path

return M
