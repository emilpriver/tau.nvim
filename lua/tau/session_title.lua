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

local function first_line(s)
	if not s or s == "" then
		return ""
	end
	local line = s:match("^[^\r\n]+") or s
	return line
end

local function looks_like_meta_title(s)
	if not s or s == "" then
		return true
	end
	local t = s:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if t == "" then
		return true
	end
	if #s > 90 then
		return true
	end
	local at_start = {
		"the user wants",
		"the user is",
		"the user has",
		"the user asked",
		"the user is asking",
		"user wants me to",
		"output a short",
		"output a title",
		"here is a",
		"here is the",
		"here is:",
		"here are",
		"here are:",
		"here's a",
		"here's the",
		"i will ",
		"i should ",
		"we should ",
		"as an ai,",
		"as a language model,",
		"based on the",
		"appropriate title",
		"possible title",
		"possible title:",
		"suggested title",
		"this chat session",
		"this conversation",
	}
	for _, p in ipairs(at_start) do
		if t:sub(1, #p) == p then
			return true
		end
	end
	if t:find("title for this chat", 1, true) or t:find("short title for this", 1, true) then
		return true
	end
	return false
end

local function strip_title_artifacts(s)
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("^[Tt]itle%s*:%s*", "")
	s = s:gsub("^[Tt]he%s+title%s+is%s*:%s*", "")
	s = s:gsub("^[Hh]ere%s+is%s*:%s*", "")
	s = s:gsub("^[Hh]ere%s+is%s+", "")
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function fallback_title_from_messages(msgs, max_len)
	for _, m in ipairs(msgs or {}) do
		if m.role == "user" then
			local t = message_text(m.content)
			t = first_line(t)
			t = t:gsub("^%s+", ""):gsub("%s+$", "")
			if t == "" then
			else
				t = t:gsub("%s+", " ")
				if #t > max_len then
					t = t:sub(1, max_len)
				end
				return t:gsub("^%s+", ""):gsub("%s+$", "")
			end
		end
	end
	return "Chat"
end

local function sanitize_title(s, max_len)
	if not s then
		return ""
	end
	s = first_line(s)
	s = strip_title_artifacts(s)
	s = s:gsub("^[\"']", ""):gsub("[\"']$", "")
	s = s:gsub("[\r\n]+", " ")
	s = s:gsub("%s+", " ")
	if #s > max_len then
		s = s:sub(1, max_len)
	end
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function first_non_empty_string(a, b)
	if type(a) == "string" and a:find("%S") then
		return a
	end
	if type(b) == "string" and b:find("%S") then
		return b
	end
	return ""
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

local function table_to_plain_text(t)
	if type(t) == "string" then
		return t
	end
	if type(t) ~= "table" then
		return ""
	end
	if type(t.text) == "string" and t.text ~= "" and t[1] == nil then
		return t.text
	end
	local out = {}
	for i = 1, #t do
		local p = t[i]
		if type(p) == "string" and p ~= "" then
			table.insert(out, p)
		elseif type(p) == "table" and type(p.text) == "string" and p.text ~= "" then
			table.insert(out, p.text)
		end
	end
	if #out == 0 then
		for _, p in pairs(t) do
			if type(p) == "table" and type(p.text) == "string" and p.text ~= "" then
				table.insert(out, p.text)
			end
		end
	end
	if #out > 0 then
		return table.concat(out, "")
	end
	if type(t.text) == "string" and t.text ~= "" then
		return t.text
	end
	return ""
end

local function lmm_string_from_result(r)
	if not r or type(r) ~= "table" then
		return ""
	end
	local t = r.text
	if type(t) == "string" and t:find("%S") then
		return t
	end
	if type(t) == "table" then
		local s = table_to_plain_text(t)
		if s:find("%S") then
			return s
		end
	end
	if type(r.thinking) == "string" and r.thinking:find("%S") then
		return r.thinking
	end
	return ""
end

local function persist_session_name(session, title, with_notify, err_note)
	session.name = title
	session._tau_llm_title_done = true
	local saved, save_err = require("tau.session").TauSessionAutosave(session)
	if saved == false then
		session._tau_llm_title_done = false
		session.name = nil
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
	if with_notify then
		if err_note then
			vim.notify("Session title: " .. title .. " (" .. err_note .. ")", vim.log.levels.INFO)
		else
			vim.notify("Session title: " .. title, vim.log.levels.INFO)
		end
	end
end

function M._run(expected_session_id, tab_id)
	local state = require("tau.state")
	local session = state.get_session(tab_id)
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

	local max_len = scfg.title_max_length or 56
	local fb = function()
		return fallback_title_from_messages(session.messages, max_len)
	end

	local excerpt = excerpt_from_messages(session.messages, scfg.title_max_chars_excerpt)
	if excerpt == "" then
		persist_session_name(session, fb(), true, nil)
		return
	end

	local provider = session.provider or cfg.provider.name
	local sys = table.concat({
		"Return only a short title for a chat tab, on one line, no other text.",
		"2-6 words. Mirror the user topic (e.g. the phrase they used) or a short label (Greetings, Code review, Email draft).",
		"Forbidden: preambles, I will, the user, here is, explaining the task, quotes, or colons in the output.",
	}, " ")
	local user = table.concat({
		"Pick a display title for this session.",
		"",
		excerpt,
	}, "\n")
	local messages = {
		{ role = "system", content = sys },
		{ role = "user", content = user },
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
		persist_session_name(session, fb(), true, "LLM call failed; used first line")
		return
	end

	local raw_model = lmm_string_from_result(result)
	local line1 = first_line(raw_model)
	local cand = sanitize_title(line1, 200)
	local title
	if line1 ~= "" and not looks_like_meta_title(cand) then
		title = sanitize_title(line1, max_len)
		if title ~= "" and not looks_like_meta_title(title) then
			persist_session_name(session, title, true, nil)
			return
		end
	end
	persist_session_name(session, fb(), true, nil)
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
	local tab_id = vim.api.nvim_get_current_tabpage()
	vim.defer_fn(function()
		M._run(sid, tab_id)
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
	M._run(session.id, vim.api.nvim_get_current_tabpage())
end

return M
