local M = {}

function M.create(role, content, opts)
	opts = opts or {}
	local msg = {
		role = role,
		content = content,
		timestamp = vim.fn.localtime(),
	}
	if opts.tool_calls then
		msg.tool_calls = opts.tool_calls
	end
	if opts.tool_call_id then
		msg.tool_call_id = opts.tool_call_id
	end
	if opts.name then
		msg.name = opts.name
	end
	if opts.attachments then
		msg.attachments = opts.attachments
	end
	return msg
end

function M.user(text, attachments)
	return M.create("user", text, { attachments = attachments })
end

function M.system(text)
	return M.create("system", text)
end

function M.assistant(text, tool_calls)
	return M.create("assistant", text, { tool_calls = tool_calls })
end

function M.tool(tool_call_id, content, name)
	return M.create("tool", content, { tool_call_id = tool_call_id, name = name })
end

function M.add(history, msg)
	table.insert(history, msg)
	return history
end

function M.last(history, role)
	for i = #history, 1, -1 do
		if not role or history[i].role == role then
			return history[i], i
		end
	end
	return nil, nil
end

function M.filter(history, role)
	local result = {}
	for _, msg in ipairs(history) do
		if not role or msg.role == role then
			table.insert(result, msg)
		end
	end
	return result
end

function M.trim_to(history, max_messages)
	if #history <= max_messages then
		return vim.deepcopy(history)
	end
	local result = {}
	for i = #history - max_messages + 1, #history do
		table.insert(result, vim.deepcopy(history[i]))
	end
	return result
end

function M.serialize(history)
	return vim.json.encode(history)
end

function M.deserialize(str)
	local ok, result = pcall(vim.json.decode, str)
	if ok then
		return result
	end
	return {}
end

return M
