local M = {}

M.name = "opencode"
M.api_key_env = "OPENCODE_API_KEY"
M.base_url = "https://opencode.ai/zen/go/v1"
M.default_model = "kimi-k2.5"
M.models_endpoint = "/models"

local sse_parser = require("tau.api.sse")

function M.register(registry)
	registry.register_model("kimi-k2.5", { context_limit = 262144 })
	registry.register_model("kimi-k2.6", { context_limit = 262144 })
	registry.register_model("glm-5", { context_limit = 204800 })
	registry.register_model("glm-5.1", { context_limit = 204800 })
	registry.register_model("mimo-v2-omni", { context_limit = 262144 })
	registry.register_model("mimo-v2-pro", { context_limit = 1048576 })

	registry.register_fallback("opencode", "kimi-k2.5", "kimi-k2.6", "glm-5", "glm-5.1", "mimo-v2-omni", "mimo-v2-pro")

	registry.register_auth_help("opencode", "Opencode", "https://opencode.ai/settings", "Enter your Opencode API key")
end

local function build_headers(api_key)
	return {
		{ "-H", "Authorization: Bearer " .. api_key },
	}
end

local function build_body(model, messages, opts)
	local body = {
		model = model,
		messages = messages,
		max_tokens = opts.max_tokens or 4096,
	}
	if opts.stream then
		body.stream = true
	end
	if opts.tools and #opts.tools > 0 then
		body.tools = M.format_tools(opts.tools)
	end
	if opts.thinking_level and opts.thinking_level ~= "off" then
		body.reasoning_effort = opts.thinking_level
	end
	return body
end

local function get_string(val)
	if val == nil or val == vim.NIL then
		return nil
	end
	if type(val) == "string" then
		return val
	end
	return nil
end

local function extract_error(parsed)
	if not parsed or not parsed.error then
		return nil
	end
	local err = parsed.error
	if type(err) ~= "table" then
		return tostring(err)
	end
	if err.metadata and err.metadata.raw then
		local ok, raw = pcall(vim.json.decode, err.metadata.raw)
		if ok and raw and raw.error then
			return raw.error.message or vim.json.encode(raw.error)
		end
		return err.metadata.raw
	end
	return err.message or err.code or vim.json.encode(err)
end

local function handle_stream_event(data, callbacks, tool_calls_acc)
	local choices = data.choices
	if not choices or #choices == 0 then
		return
	end
	local delta = choices[1].delta
	if not delta then
		return
	end
	local content = get_string(delta.content)
	if content then
		callbacks.on_chunk(content)
	end
	local reasoning = get_string(delta.reasoning_content) or get_string(delta.reasoning) or get_string(delta.reasoning_text)
	if reasoning then
		callbacks.on_thinking(reasoning)
	end
	if type(delta.tool_calls) == "table" and #delta.tool_calls > 0 then
		for _, tc in ipairs(delta.tool_calls) do
			if tc and type(tc) == "table" and tc["function"] and type(tc["function"]) == "table" then
				local idx = tc.index or 1
				if not tool_calls_acc[idx] then
					tool_calls_acc[idx] = { name = nil, args = "", id = nil }
				end
				local entry = tool_calls_acc[idx]
				local name = get_string(tc["function"].name)
				local args = get_string(tc["function"].arguments)
				local id = get_string(tc.id)
				if name then
					entry.name = name
				end
				if id then
					entry.id = id
				elseif not entry.id then
					entry.id = "tc_" .. idx
				end
				local args_delta = args or ""
				if args then
					entry.args = entry.args .. args
				end
				if entry.name and entry.id then
					callbacks.on_tool_use(entry.name, args_delta, entry.id)
				end
			end
		end
	end
end

local function parse_response(response)
	local choice = response.choices and response.choices[1]
	if not choice then
		return { text = "", thinking = "", tool_uses = {}, usage = response.usage }
	end
	local message = choice.message
	local text = get_string(message.content) or ""
	local thinking = get_string(message.reasoning) or ""
	local tool_uses = {}
	if message.tool_calls then
		for _, tc in ipairs(message.tool_calls) do
			local args = tc["function"] and get_string(tc["function"].arguments) or "{}"
			local input = {}
			if args and args ~= "" then
				local ok, parsed = pcall(vim.json.decode, args)
				if ok then
					input = parsed
				end
			end
			table.insert(tool_uses, {
				id = get_string(tc.id),
				name = tc["function"] and get_string(tc["function"].name) or "",
				input = input,
			})
		end
	end
	return { text = text, thinking = thinking, tool_uses = tool_uses, usage = response.usage }
end

function M.stream(api_key, base_url, model, messages, opts)
	local on_chunk = opts.on_chunk or function() end
	local on_tool_use = opts.on_tool_use or function() end
	local on_thinking = opts.on_thinking or function() end
	local on_done = opts.on_done or function() end
	local on_error = opts.on_error or function() end

	local body = build_body(model, messages, {
		stream = true,
		tools = opts.tools,
		thinking_level = opts.thinking_level,
		max_tokens = opts.max_tokens,
	})

	local json_body = vim.json.encode(body)
	local url = base_url .. (M.chat_endpoint or "/chat/completions")

	local curl_cmd = { "curl", url, "--no-buffer", "-s", "-S" }
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(curl_cmd, h)
	end
	vim.list_extend(curl_cmd, { "-H", "content-type: application/json" })
	vim.list_extend(curl_cmd, { "-d", json_body })

	local buffer = ""
	local event_count = 0
	local stderr_lines = {}
	local tool_calls_acc = {}

	local done_called = false

	local function process_chunk(err, raw)
		if err then
			table.insert(stderr_lines, tostring(err))
			return
		end
		if not raw then
			return
		end
		buffer = buffer .. raw

		local events = sse_parser.parse(buffer)
		local all_done = false

		for _, event in ipairs(events) do
			event_count = event_count + 1
			if event.data == "[DONE]" then
				all_done = true
				break
			end

			if event.data and event.data ~= "" then
				local success, parsed = pcall(vim.json.decode, event.data)
				if success and parsed then
					handle_stream_event(parsed, {
						on_chunk = function(text)
							vim.schedule(function()
								on_chunk(text)
							end)
						end,
						on_thinking = function(text)
							vim.schedule(function()
								on_thinking(text)
							end)
						end,
						on_tool_use = function(name, args, id)
							vim.schedule(function()
								on_tool_use(name, args, id)
							end)
						end,
					}, tool_calls_acc)
				end
			end
		end

		buffer = sse_parser.remaining(buffer)

		if all_done and not done_called then
			done_called = true
			vim.schedule(on_done)
		end
	end

	local stderr_handler = function(err, data)
		if data and data ~= "" then
			table.insert(stderr_lines, data)
		end
	end

	local handle = vim.system(curl_cmd, { text = true, stdout = process_chunk, stderr = stderr_handler }, function(result)
		if result.code ~= 0 then
			local err_msg = table.concat(stderr_lines, "\n")
			if result.stdout and result.stdout ~= "" then
				err_msg = err_msg .. "\n" .. result.stdout
			end
			if err_msg == "" then
				err_msg = "HTTP request failed (code " .. result.code .. ")"
			end
			vim.schedule(function()
				on_error(err_msg)
			end)
			if not done_called then
				done_called = true
				vim.schedule(on_done)
			end
			return
		end

		if event_count == 0 and buffer ~= "" then
			-- No SSE events parsed -- likely a non-streaming or error response
			local ok, parsed = pcall(vim.json.decode, buffer)
			if ok and parsed then
				if parsed.error then
					local err_msg = extract_error(parsed) or buffer
					vim.schedule(function()
						on_error(err_msg)
					end)
					if not done_called then
						done_called = true
						vim.schedule(on_done)
					end
					return
				end
				-- Non-streaming response parsed as JSON -- try to emit it
				local text = parsed.choices and parsed.choices[1] and parsed.choices[1].message and parsed.choices[1].message.content or ""
				if text ~= "" then
					vim.schedule(function()
						on_chunk(text)
					end)
				end
			end
		end

		if not done_called then
			done_called = true
			vim.schedule(on_done)
		end
	end)

	return handle
end

function M.call(api_key, base_url, model, messages, opts)
	local body = build_body(model, messages, {
		stream = false,
		tools = opts.tools,
		thinking_level = opts.thinking_level,
		max_tokens = opts.max_tokens,
	})

	local json_body = vim.json.encode(body)
	local url = base_url .. (M.chat_endpoint or "/chat/completions")

	local curl_cmd = { "curl", url, "-s", "-S" }
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(curl_cmd, h)
	end
	vim.list_extend(curl_cmd, { "-H", "content-type: application/json" })
	vim.list_extend(curl_cmd, { "-d", json_body })

	local result = vim.system(curl_cmd, { text = true }):wait()

	if result.code ~= 0 then
		local err = result.stderr or "unknown"
		if result.stdout and result.stdout ~= "" then
			err = err .. "\n" .. result.stdout
		end
		error(err)
	end

	local success, response = pcall(vim.json.decode, result.stdout)
	if not success then
		error(result.stdout)
	end

	if response.error then
		local err = extract_error(response) or result.stdout
		error(err)
	end

	return parse_response(response)
end

function M.list_models(api_key, base_url)
	if not M.models_endpoint then
		return {}
	end

	local url = base_url .. M.models_endpoint

	local curl_cmd = { "curl", url, "-s", "-S" }
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(curl_cmd, h)
	end

	local result = vim.system(curl_cmd, { text = true }):wait()

	if result.code ~= 0 then
		return {}
	end

	if result.stdout and result.stdout ~= "" then
		local ok, parsed = pcall(vim.json.decode, result.stdout)
		if ok and parsed and parsed.error then
			return {}
		end
	end

	local success, response = pcall(vim.json.decode, result.stdout)
	if not success then
		return {}
	end

	local models = {}
	for _, m in ipairs(response.data or {}) do
		if m.id then
			table.insert(models, m.id)
		end
	end
	return models
end

function M.format_tools(tools)
	local formatted = {}
	for _, tool in ipairs(tools) do
		table.insert(formatted, {
			type = "function",
			["function"] = {
				name = tool.name,
				description = tool.description,
				parameters = tool.parameters,
				strict = false,
			},
		})
	end
	return formatted
end

function M.format_attachments(attachments)
	local result = {}
	for _, att in ipairs(attachments) do
		local url = string.format("data:%s;base64,%s", att.mime_type, att.base64)
		table.insert(result, {
			type = "image_url",
			image_url = { url = url },
		})
	end
	return result
end

function M.build_user_message(text, attachments)
	local content = {}
	if text and text ~= "" then
		table.insert(content, { type = "text", text = text })
	end
	if attachments and #attachments > 0 then
		vim.list_extend(content, M.format_attachments(attachments))
	end
	if #content == 0 then
		return nil
	end
	if #content == 1 then
		return { role = "user", content = text }
	end
	return { role = "user", content = content }
end

function M.setup(registry)
	if M.register then
		M.register(registry)
	end
	registry.register_provider(M)
end

return M
