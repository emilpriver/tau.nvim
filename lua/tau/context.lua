local M = {}

local DEFAULT_LIMIT = 128000
local COMPACTION_WARN = 0.7
local COMPACTION_AUTO = 0.85
local MESSAGES_TO_KEEP = 6

function M.count_tokens(text)
	if not text or text == "" then
		return 0
	end
	return math.ceil(#text / 4)
end

function M.count_message_tokens(msg)
	local total = 0
	if msg.role then
		total = total + 4
	end
	if type(msg.content) == "string" then
		total = total + M.count_tokens(msg.content)
	elseif type(msg.content) == "table" then
		for _, part in ipairs(msg.content) do
			if type(part) == "string" then
				total = total + M.count_tokens(part)
			elseif part.text then
				total = total + M.count_tokens(part.text)
			elseif part.type == "tool_result" and part.content then
				total = total + M.count_tokens(part.content)
			end
		end
	end
	if msg.tool_calls then
		for _, tc in ipairs(msg.tool_calls) do
			total = total + M.count_tokens(tc["function"] and tc["function"].name or "")
			total = total + M.count_tokens(tc["function"] and tc["function"].arguments or "")
		end
	end
	return total
end

function M.count_messages_tokens(messages)
	local total = 0
	for _, msg in ipairs(messages) do
		total = total + M.count_message_tokens(msg)
	end
	return total
end

function M.get_context_limit(model_id)
	if not model_id then
		return DEFAULT_LIMIT
	end
	return require("tau.plugin").get_model_meta(model_id).context_limit or DEFAULT_LIMIT
end

function M.get_usage_ratio(messages, model_id)
	local tokens = M.count_messages_tokens(messages)
	local limit = M.get_context_limit(model_id)
	return tokens / limit, tokens, limit
end

function M.should_compact(messages, model_id)
	local ratio, tokens, limit = M.get_usage_ratio(messages, model_id)
	return ratio >= COMPACTION_AUTO, tokens, limit, ratio
end

function M.should_warn(messages, model_id)
	local ratio, tokens, limit = M.get_usage_ratio(messages, model_id)
	return ratio >= COMPACTION_WARN and ratio < COMPACTION_AUTO, tokens, limit, ratio
end

function M.compact(messages, instructions, provider_name)
	if #messages <= MESSAGES_TO_KEEP then
		return messages, 0
	end

	local system_msgs = {}
	local compactable = {}
	local recent = {}

	for _, msg in ipairs(messages) do
		if msg.role == "system" then
			table.insert(system_msgs, msg)
		elseif #recent < MESSAGES_TO_KEEP then
			table.insert(recent, msg)
		else
			table.insert(compactable, 1, msg)
		end
	end

	if #compactable == 0 then
		return messages, 0
	end

	local summary = M.summarize(compactable, instructions, provider_name)

	local result = {}
	for _, msg in ipairs(system_msgs) do
		table.insert(result, msg)
	end

	if summary and summary ~= "" then
		table.insert(result, {
			role = "user",
			content = "[Context Summary]\n\n" .. summary,
		})
	end

	for _, msg in ipairs(recent) do
		table.insert(result, msg)
	end

	local old_tokens = M.count_messages_tokens(messages)
	local new_tokens = M.count_messages_tokens(result)

	return result, old_tokens - new_tokens
end

function M.summarize(messages, instructions, provider_name)
	local api = require("tau.api")
	local summary_prompt = M.build_summary_prompt(messages, instructions)

	local summary_messages = {
		{
			role = "system",
			content = "You are a context summarizer. Condense the conversation history into a concise summary that preserves all key decisions, facts, and action items. Be specific about file paths, code changes, and tool results.",
		},
		{ role = "user", content = summary_prompt },
	}

	local ok, result = pcall(api.call, provider_name, summary_messages, {
		max_tokens = 2048,
		thinking_level = "off",
	})

	if ok and result and result.text then
		return vim.trim(result.text)
	end

	return M.fallback_summarize(messages)
end

function M.build_summary_prompt(messages, instructions)
	local parts = {}
	if instructions then
		table.insert(parts, "Original instructions: " .. instructions)
	end

	table.insert(parts, "Summarize this conversation history:")

	for i, msg in ipairs(messages) do
		local role = msg.role or "unknown"
		local content = ""

		if type(msg.content) == "string" then
			content = msg.content
		elseif type(msg.content) == "table" then
			local texts = {}
			for _, part in ipairs(msg.content) do
				if type(part) == "string" then
					table.insert(texts, part)
				elseif part.text then
					table.insert(texts, part.text)
				elseif part.type == "tool_result" then
					table.insert(
						texts,
						"[Tool result: " .. (part.tool_use_id or "?") .. "] " .. tostring(part.content):sub(1, 200)
					)
				end
			end
			content = table.concat(texts, "\n")
		end

		if msg.tool_calls then
			local calls = {}
			for _, tc in ipairs(msg.tool_calls) do
				local name = tc["function"] and tc["function"].name or "?"
				table.insert(calls, name)
			end
			content = content .. "\n[Tool calls: " .. table.concat(calls, ", ") .. "]"
		end

		table.insert(parts, string.format("%d. [%s] %s", i, role, content:sub(1, 500)))
	end

	return table.concat(parts, "\n\n")
end

function M.fallback_summarize(messages)
	local parts = {}
	for _, msg in ipairs(messages) do
		local role = msg.role or "unknown"
		if role == "user" then
			local text = ""
			if type(msg.content) == "string" then
				text = msg.content
			elseif type(msg.content) == "table" and msg.content[1] and msg.content[1].text then
				text = msg.content[1].text
			end
			table.insert(parts, "User: " .. text:sub(1, 200))
		elseif role == "assistant" and msg.tool_calls then
			local calls = {}
			for _, tc in ipairs(msg.tool_calls) do
				table.insert(calls, tc["function"] and tc["function"].name or "?")
			end
			table.insert(parts, "Agent used tools: " .. table.concat(calls, ", "))
		end
	end

	if #parts == 0 then
		return "Previous conversation summarized."
	end

	return table.concat(parts, "\n")
end

return M
