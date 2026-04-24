local M = {}

local function message_text(content)
	if type(content) == "string" then
		return content
	end
	if content == nil then
		return ""
	end
	local ok, enc = pcall(vim.json.encode, content)
	if ok then
		return enc
	end
	return ""
end

local function excerpt_from_messages(msgs, max_chars)
	max_chars = max_chars or 4000
	local parts = {}
	local n = 0
	for _, m in ipairs(msgs or {}) do
		if m.role ~= "system" then
			local text = message_text(m.content)
			if m.role == "assistant" and type(m.reasoning_content) == "string" and m.reasoning_content ~= "" then
				text = text ~= "" and (text .. "\n" .. m.reasoning_content) or m.reasoning_content
			end
			if text ~= "" then
				local line = (m.role or "?") .. ": " .. text
				if n + #line > max_chars then
					local rest = max_chars - n
					if rest > 0 then
						table.insert(parts, line:sub(1, rest))
					end
					break
				end
				table.insert(parts, line)
				n = n + #line + 1
			end
		end
	end
	return table.concat(parts, "\n")
end

local function sanitize_title(s, max_len)
	if not s then
		return ""
	end
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub('^["\']', ""):gsub('["\']$', "")
	s = s:gsub("[\r\n]+", " ")
	s = s:gsub("%s+", " ")
	if #s > max_len then
		s = s:sub(1, max_len)
	end
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function has_assistant_reply(msgs)
	for _, m in ipairs(msgs or {}) do
		if m.role == "assistant" then
			local t = message_text(m.content)
			if t == "" and type(m.reasoning_content) == "string" and m.reasoning_content ~= "" then
				t = m.reasoning_content
			end
			if t ~= "" then
				return true
			end
			if type(m.tool_calls) == "table" and #m.tool_calls > 0 then
				return true
			end
		end
	end
	return false
end

function M._run(expected_session_id)
	local state = require("tau.state")
	local session = state.get_session()
	if not session or session.id ~= expected_session_id then
		return
	end
	local cfg = require("tau.config").get()
	local scfg = cfg.session or {}
	if not scfg.auto_llm_title then
		return
	end
	if session.name and session.name ~= "" then
		return
	end
	if session._tau_llm_title_done then
		return
	end
	if not has_assistant_reply(session.messages) then
		return
	end

	local excerpt = excerpt_from_messages(session.messages, scfg.title_max_chars_excerpt)
	if excerpt == "" then
		session._tau_llm_title_done = true
		return
	end

	local provider = session.provider or cfg.provider.name
	local max_len = scfg.title_max_length or 56
	local sys =
		"You name chat sessions. Output exactly one short title: 3-7 words, no quotes, no colons, no newlines, describe the user topic or task only."
	local messages = {
		{ role = "system", content = sys },
		{ role = "user", content = excerpt },
	}

	local call_opts = {
		max_tokens = 64,
		thinking_level = "off",
	}
	if scfg.title_model and scfg.title_model ~= "" then
		call_opts.model = scfg.title_model
	end

	local ok, result = pcall(require("tau.api").call, provider, messages, call_opts)
	if not ok then
		session._tau_llm_title_attempts = (session._tau_llm_title_attempts or 0) + 1
		if session._tau_llm_title_attempts >= 2 then
			session._tau_llm_title_done = true
			vim.notify("Tau session title failed: " .. tostring(result), vim.log.levels.WARN)
		end
		return
	end
	local raw_title = ""
	if type(result.text) == "string" and result.text ~= "" then
		raw_title = result.text
	elseif type(result.thinking) == "string" and result.thinking ~= "" then
		raw_title = result.thinking
	end
	if raw_title == "" then
		session._tau_llm_title_attempts = (session._tau_llm_title_attempts or 0) + 1
		if session._tau_llm_title_attempts >= 2 then
			session._tau_llm_title_done = true
			vim.notify("Tau session title: empty model reply", vim.log.levels.WARN)
		end
		return
	end

	local title = sanitize_title(raw_title, max_len)
	if title == "" then
		session._tau_llm_title_attempts = (session._tau_llm_title_attempts or 0) + 1
		if session._tau_llm_title_attempts >= 2 then
			session._tau_llm_title_done = true
		end
		return
	end

	session.name = title
	session._tau_llm_title_done = true
	local saved, save_err = require("tau.session").TauSessionAutosave(session)
	if saved == false then
		session._tau_llm_title_done = false
		vim.notify("Tau session title not saved: " .. tostring(save_err), vim.log.levels.ERROR)
		return
	end
	local ui = require("tau.ui")
	if ui.active then
		ui.active.session = session
	end
	vim.schedule(function()
		require("tau.ui").refresh_winbar()
	end)
	vim.notify("Session title: " .. title, vim.log.levels.INFO)
end

function M.maybe_apply(session)
	if not session then
		return
	end
	local cfg = require("tau.config").get()
	local scfg = cfg.session or {}
	if not scfg.auto_llm_title then
		return
	end
	if session.name and session.name ~= "" then
		return
	end
	if session._tau_llm_title_done then
		return
	end
	if not has_assistant_reply(session.messages) then
		return
	end

	local sid = session.id
	vim.defer_fn(function()
		M._run(sid)
	end, 100)
end

function M.generate_now(opts)
	opts = opts or {}
	local state = require("tau.state")
	local session = state.get_session()
	if not session then
		vim.notify("No active session", vim.log.levels.WARN)
		return
	end
	if not has_assistant_reply(session.messages) then
		vim.notify("Need at least one assistant message to title the session", vim.log.levels.WARN)
		return
	end
	if opts.force then
		session.name = nil
	end
	session._tau_llm_title_done = false
	session._tau_llm_title_attempts = 0
	M._run(session.id)
end

return M
