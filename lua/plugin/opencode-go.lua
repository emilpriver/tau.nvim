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
		max_completion_tokens = opts.max_tokens or 4096,
	}
	if opts.stream then
		body.stream = true
		body.stream_options = { include_usage = true }
	end
	if opts.tools and #opts.tools > 0 then
		body.tools = M.format_tools(opts.tools)
	end
	if opts.thinking_level and opts.thinking_level ~= "off" then
		body.reasoning_effort = opts.thinking_level
	end
	return body
end

local function handle_stream_event(data, callbacks)
	local choices = data.choices
	if not choices or #choices == 0 then
		return
	end
	local delta = choices[1].delta
	if not delta then
		return
	end
	if delta.content then
		callbacks.on_chunk(delta.content)
	end
	local reasoning = delta.reasoning_content or delta.reasoning or delta.reasoning_text
	if reasoning then
		callbacks.on_thinking(reasoning)
	end
	if delta.tool_calls and #delta.tool_calls > 0 then
		local tc = delta.tool_calls[1]
		if tc and tc["function"] then
			callbacks.on_tool_use(tc["function"].name, tc["function"].arguments, tc.id)
		end
	end
end

local function parse_response(response)
	local choice = response.choices and response.choices[1]
	if not choice then
		return { text = "", thinking = "", tool_uses = {}, usage = response.usage }
	end
	local message = choice.message
	local text = message.content or ""
	local thinking = message.reasoning or ""
	local tool_uses = {}
	if message.tool_calls then
		for _, tc in ipairs(message.tool_calls) do
			local args = tc["function"] and tc["function"].arguments or "{}"
			local input = {}
			if args and args ~= "" then
				local ok, parsed = pcall(vim.json.decode, args)
				if ok then
					input = parsed
				end
			end
			table.insert(tool_uses, {
				id = tc.id,
				name = tc["function"] and tc["function"].name or "",
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

	local header_args = {}
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(header_args, h)
	end

	vim.list_extend(header_args, {
		{ "-H", "content-type: application/json" },
		{ "-d", json_body },
	})

	local curl_cmd = { "curl", url, "--no-buffer", "-s" }
	vim.list_extend(curl_cmd, header_args)

	local buffer = ""

	local function process_chunk(raw)
		if not raw or raw == "" then
			return
		end
		buffer = buffer .. raw

		local events = sse_parser.parse(buffer)
		local all_done = false

		for _, event in ipairs(events) do
			if event.data == "[DONE]" then
				all_done = true
				break
			end

			if event.data and event.data ~= "" then
				local success, parsed = pcall(vim.json.decode, event.data)
				if success and parsed then
					handle_stream_event(parsed, {
						on_chunk = on_chunk,
						on_thinking = on_thinking,
						on_tool_use = on_tool_use,
					})
				end
			end
		end

		buffer = sse_parser.remaining(buffer)

		if all_done then
			vim.schedule(on_done)
		end
	end

	local handle = vim.system(curl_cmd, { text = true, stdout = process_chunk }, function(result)
		if result.code ~= 0 and result.stderr and result.stderr ~= "" then
			vim.schedule(function()
				on_error(result.stderr)
			end)
		end
		vim.schedule(on_done)
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

	local header_args = {}
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(header_args, h)
	end

	vim.list_extend(header_args, {
		{ "-H", "content-type: application/json" },
		{ "-d", json_body },
	})

	local curl_cmd = { "curl", url, "-s" }
	vim.list_extend(curl_cmd, header_args)

	local result = vim.system(curl_cmd, { text = true }):wait()

	if result.code ~= 0 then
		error("API error: " .. (result.stderr or "unknown"))
	end

	local success, response = pcall(vim.json.decode, result.stdout)
	if not success then
		error("Failed to parse API response: " .. result.stdout)
	end

	return parse_response(response)
end

function M.list_models(api_key, base_url)
	if not M.models_endpoint then
		return {}
	end

	local url = base_url .. M.models_endpoint

	local header_args = {}
	for _, h in ipairs(build_headers(api_key)) do
		vim.list_extend(header_args, h)
	end

	local curl_cmd = { "curl", url, "-s" }
	vim.list_extend(curl_cmd, header_args)

	local result = vim.system(curl_cmd, { text = true }):wait()

	if result.code ~= 0 then
		return {}
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
