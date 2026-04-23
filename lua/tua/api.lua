local M = {}

local sse_parser = require("tua.api.sse")

local PROVIDER_CONFIG = {
  anthropic = {
    api_key_env = "ANTHROPIC_API_KEY",
    base_url = "https://api.anthropic.com",
    chat_endpoint = "/v1/messages",
    models_endpoint = "/v1/models",
    headers = function(api_key)
      return {
        { "-H", "x-api-key: " .. api_key },
        { "-H", "anthropic-version: 2023-06-01" },
        { "-H", "anthropic-beta: extended-thinking-2025-05-14,prompt-caching-2024-07-31" },
      }
    end,
    default_model = "claude-sonnet-4-20250514",
  },
  openai = {
    api_key_env = "OPENAI_API_KEY",
    base_url = "https://api.openai.com",
    chat_endpoint = "/v1/responses",
    models_endpoint = "/v1/models",
    headers = function(api_key)
      return {
        { "-H", "Authorization: Bearer " .. api_key },
      }
    end,
    default_model = "gpt-4.1",
  },
  cursor = {
    api_key_env = "CURSOR_API_KEY",
    base_url = "https://api2.cursor.sh",
    chat_endpoint = "/aiserver.v1.AIServerService/ChatCompletion",
    models_endpoint = nil,
    headers = function(api_key)
      return {
        { "-H", "Authorization: Bearer " .. api_key },
      }
    end,
    default_model = "claude-3.5-sonnet",
  },
}

local function get_provider_config(provider_name)
  local cfg = PROVIDER_CONFIG[provider_name]
  if not cfg then
    error("Unknown provider: " .. provider_name)
  end
  return cfg
end

local function get_api_key(provider_name)
  local auth_key = require("tua.auth").get_key(provider_name)
  if auth_key then
    return auth_key
  end
  local cfg = get_provider_config(provider_name)
  local key = vim.env[cfg.api_key_env]
  if not key then
    error("API key not found for " .. provider_name .. ". Run :TauLogin " .. provider_name .. " or set " .. cfg.api_key_env)
  end
  return key
end

local function get_base_url(provider_name)
  local plugin_config = require("tua.config").get()
  local provider_cfg = get_provider_config(provider_name)
  if plugin_config.provider.base_url then
    return plugin_config.provider.base_url
  end
  return provider_cfg.base_url
end

local function get_model(provider_name)
  local plugin_config = require("tua.config").get()
  if plugin_config.provider.model then
    return plugin_config.provider.model
  end
  local provider_cfg = get_provider_config(provider_name)
  return provider_cfg.default_model
end

function M.stream(provider_name, messages, opts)
  local api_key = get_api_key(provider_name)
  local base_url = get_base_url(provider_name)
  local provider_cfg = get_provider_config(provider_name)

  local on_chunk = opts.on_chunk or function() end
  local on_tool_use = opts.on_tool_use or function() end
  local on_thinking = opts.on_thinking or function() end
  local on_done = opts.on_done or function() end
  local on_error = opts.on_error or function() end

  local body = M.build_request_body(provider_name, messages, opts)
  body.stream = true

  local json_body = vim.json.encode(body)
  local url = base_url .. provider_cfg.chat_endpoint

  local header_args = {}
  for _, h in ipairs(provider_cfg.headers(api_key)) do
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
    buffer = buffer .. raw

    local events = sse_parser.parse(buffer)
    local all_done = false

    for _, event in ipairs(events) do
      if event.data == "[DONE]" or event.event == "message_end" then
        all_done = true
        break
      end

      if event.data and event.data ~= "" then
        local success, parsed = pcall(vim.json.decode, event.data)
        if success and parsed then
          M.handle_stream_event(provider_name, parsed, event, on_chunk, on_tool_use, on_thinking)
        end
      end
    end

    buffer = sse_parser.remaining(buffer)

    if all_done then
      on_done()
    end
  end

  local handle = vim.system(curl_cmd, { text = true, stdout = process_chunk }, function(result)
    if result.code ~= 0 and result.stderr and result.stderr ~= "" then
      on_error(result.stderr)
    end
    on_done()
  end)

  return handle
end

function M.call(provider_name, messages, opts)
  local api_key = get_api_key(provider_name)
  local base_url = get_base_url(provider_name)
  local provider_cfg = get_provider_config(provider_name)

  local body = M.build_request_body(provider_name, messages, opts)
  local json_body = vim.json.encode(body)
  local url = base_url .. provider_cfg.chat_endpoint

  local header_args = {}
  for _, h in ipairs(provider_cfg.headers(api_key)) do
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

  return M.parse_response(provider_name, response)
end

function M.build_request_body(provider_name, messages, opts)
  local model = get_model(provider_name)

  if provider_name == "anthropic" then
    return M.build_anthropic_body(model, messages, opts)
  elseif provider_name == "openai" then
    return M.build_openai_responses_body(model, messages, opts)
  else
    return M.build_openai_chat_body(model, messages, opts)
  end
end

function M.build_anthropic_body(model, messages, opts)
  local system_msg = nil
  local anthropic_messages = {}

  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      system_msg = msg.content
    else
      table.insert(anthropic_messages, msg)
    end
  end

  local body = {
    model = model,
    messages = anthropic_messages,
    max_tokens = opts.max_tokens or 8192,
  }

  if system_msg then
    body.system = system_msg
  end

  if opts.tools and #opts.tools > 0 then
    body.tools = M.format_anthropic_tools(opts.tools)
  end

  if opts.thinking_level and opts.thinking_level ~= "off" then
    body.thinking = {
      type = "enabled",
      budget_tokens = M.thinking_budget(opts.thinking_level),
    }
  end

  return body
end

local function to_text(content)
  if type(content) == "string" then
    return content
  end
  if type(content) == "table" then
    local parts = {}
    for _, item in ipairs(content) do
      if item.type == "text" or item.type == "input_text" or item.type == "output_text" then
        table.insert(parts, item.text)
      end
    end
    return table.concat(parts, "\n")
  end
  return ""
end

function M.build_openai_responses_body(model, messages, opts)
  local instructions = nil
  local input = {}

  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      if instructions then
        instructions = instructions .. "\n\n" .. msg.content
      else
        instructions = msg.content
      end
    elseif msg.role == "user" then
      table.insert(input, {
        type = "message",
        role = "user",
        content = { { type = "input_text", text = to_text(msg.content) } },
      })
    elseif msg.role == "assistant" then
      if msg.tool_calls then
        for _, tc in ipairs(msg.tool_calls) do
          local call_id = tc.id or tc.call_id
          local args = tc["function"].arguments
          if type(args) == "table" then
            args = vim.json.encode(args)
          end
          table.insert(input, {
            type = "function_call",
            call_id = call_id,
            name = tc["function"].name,
            arguments = args or "{}",
          })
        end
      elseif msg.content and msg.content ~= "" then
        table.insert(input, {
          type = "message",
          role = "assistant",
          content = { { type = "output_text", text = to_text(msg.content) } },
        })
      end
    elseif msg.role == "tool" then
      table.insert(input, {
        type = "function_call_output",
        call_id = msg.tool_call_id,
        output = to_text(msg.content),
      })
    end
  end

  local body = {
    model = model,
    input = input,
    max_output_tokens = opts.max_output_tokens or opts.max_tokens or 4096,
  }

  if instructions then
    body.instructions = instructions
  end

  if opts.tools and #opts.tools > 0 then
    body.tools = M.format_openai_responses_tools(opts.tools)
  end

  if opts.thinking_level and opts.thinking_level ~= "off" then
    body.reasoning = { effort = opts.thinking_level }
  end

  return body
end

function M.build_openai_chat_body(model, messages, opts)
  local body = {
    model = model,
    messages = messages,
    max_tokens = opts.max_tokens or 4096,
  }

  if opts.tools and #opts.tools > 0 then
    body.tools = M.format_openai_chat_tools(opts.tools)
  end

  if opts.thinking_level and opts.thinking_level ~= "off" then
    body.reasoning_effort = opts.thinking_level
  end

  return body
end

function M.format_anthropic_tools(tools)
  local formatted = {}
  for _, tool in ipairs(tools) do
    table.insert(formatted, {
      name = tool.name,
      description = tool.description,
      input_schema = tool.parameters,
    })
  end
  return formatted
end

function M.format_openai_chat_tools(tools)
  local formatted = {}
  for _, tool in ipairs(tools) do
    table.insert(formatted, {
      type = "function",
      ["function"] = {
        name = tool.name,
        description = tool.description,
        parameters = tool.parameters,
      },
    })
  end
  return formatted
end

function M.format_openai_responses_tools(tools)
  local formatted = {}
  for _, tool in ipairs(tools) do
    table.insert(formatted, {
      type = "function",
      name = tool.name,
      description = tool.description,
      parameters = tool.parameters,
    })
  end
  return formatted
end

function M.thinking_budget(level)
  local budgets = {
    minimal = 1024,
    low = 2048,
    medium = 4096,
    high = 8192,
    xhigh = 16384,
  }
  return budgets[level] or 4096
end

function M.handle_stream_event(provider_name, data, raw_event, on_chunk, on_tool_use, on_thinking)
  if provider_name == "anthropic" then
    M.handle_anthropic_event(data, on_chunk, on_tool_use, on_thinking)
  elseif provider_name == "openai" then
    M.handle_openai_responses_event(data, raw_event, on_chunk, on_tool_use, on_thinking)
  else
    M.handle_openai_chat_event(data, on_chunk, on_tool_use, on_thinking)
  end
end

function M.handle_anthropic_event(data, on_chunk, on_tool_use, on_thinking)
  local type = data.type

  if type == "content_block_start" then
    local block = data.content_block
    if block and block.type == "text" then
      on_chunk("")
    elseif block and block.type == "thinking" then
      on_thinking("")
    elseif block and block.type == "tool_use" then
      on_tool_use(block.name, block.input, block.id)
    end
  elseif type == "content_block_delta" then
    local delta = data.delta
    if delta and delta.type == "text_delta" then
      on_chunk(delta.text)
    elseif delta and delta.type == "thinking_delta" then
      on_thinking(delta.thinking)
    elseif delta and delta.type == "input_json_delta" then
      on_tool_use(nil, delta.partial_json, nil)
    end
  end
end

function M.handle_openai_responses_event(data, raw_event, on_chunk, on_tool_use, on_thinking)
  local event_type = raw_event.event

  if event_type == "response.output_text.delta" then
    local delta = data.delta
    if delta then
      on_chunk(delta)
    end
  elseif event_type == "response.output_item.added" then
    local item = data.item
    if item and item.type == "function_call" then
      on_tool_use(item.name, "", item.call_id)
    elseif item and item.type == "reasoning" then
      on_thinking("")
    end
  elseif event_type == "response.function_call_arguments.delta" then
    local delta = data.delta
    if delta then
      on_tool_use(nil, delta, nil)
    end
  elseif event_type == "response.output_text.done" then
  elseif event_type == "response.function_call_arguments.done" then
  elseif event_type == "response.completed" then
  elseif event_type == "response.failed" then
  end
end

function M.handle_openai_chat_event(data, on_chunk, on_tool_use, on_thinking)
  local choices = data.choices
  if not choices or #choices == 0 then
    return
  end

  local delta = choices[1].delta
  if not delta then
    return
  end

  if delta.content then
    on_chunk(delta.content)
  end

  if delta.reasoning_content then
    on_thinking(delta.reasoning_content)
  end

  if delta.tool_calls and #delta.tool_calls > 0 then
    local tc = delta.tool_calls[1]
    if tc["function"] then
      on_tool_use(tc["function"].name, tc["function"].arguments, tc.id)
    end
  end
end

function M.parse_response(provider_name, response)
  if provider_name == "anthropic" then
    return M.parse_anthropic_response(response)
  elseif provider_name == "openai" then
    return M.parse_openai_responses_response(response)
  else
    return M.parse_openai_chat_response(response)
  end
end

function M.parse_anthropic_response(response)
  local text = ""
  local thinking = ""
  local tool_uses = {}

  for _, block in ipairs(response.content or {}) do
    if block.type == "text" then
      text = text .. block.text
    elseif block.type == "thinking" then
      thinking = thinking .. block.thinking
    elseif block.type == "tool_use" then
      table.insert(tool_uses, {
        id = block.id,
        name = block.name,
        input = block.input,
      })
    end
  end

  return {
    text = text,
    thinking = thinking,
    tool_uses = tool_uses,
    usage = response.usage,
  }
end

function M.parse_openai_responses_response(response)
  local text = ""
  local thinking = ""
  local tool_uses = {}

  for _, item in ipairs(response.output or {}) do
    if item.type == "message" then
      for _, content in ipairs(item.content or {}) do
        if content.type == "output_text" then
          text = text .. content.text
        end
      end
    elseif item.type == "reasoning" then
      local summary = item.summary
      if summary then
        thinking = thinking .. summary
      end
      for _, content in ipairs(item.content or {}) do
        if content.text then
          thinking = thinking .. content.text
        end
      end
    elseif item.type == "function_call" then
      local args = item.arguments
      local input = {}
      if args and args ~= "" then
        local success, parsed = pcall(vim.json.decode, args)
        if success then
          input = parsed
        end
      end
      table.insert(tool_uses, {
        id = item.call_id,
        name = item.name,
        input = input,
      })
    end
  end

  return {
    text = text,
    thinking = thinking,
    tool_uses = tool_uses,
    usage = response.usage,
  }
end

function M.parse_openai_chat_response(response)
  local choice = response.choices and response.choices[1]
  if not choice then
    return { text = "", thinking = "", tool_uses = {}, usage = response.usage }
  end

  local message = choice.message
  local text = message.content or ""
  local thinking = ""
  local tool_uses = {}

  if message.reasoning then
    thinking = message.reasoning
  end

  if message.tool_calls then
    for _, tc in ipairs(message.tool_calls) do
      local args = tc["function"].arguments
      local input = {}
      if args and args ~= "" then
        local success, parsed = pcall(vim.json.decode, args)
        if success then
          input = parsed
        end
      end
      table.insert(tool_uses, {
        id = tc.id,
        name = tc["function"].name,
        input = input,
      })
    end
  end

  return {
    text = text,
    thinking = thinking,
    tool_uses = tool_uses,
    usage = response.usage,
  }
end

function M.list_models(provider_name)
  if provider_name == "cursor" then
    return {
      "claude-3.5-sonnet",
      "claude-3-opus",
      "claude-3.5-haiku",
      "gpt-4o",
      "gpt-4o-mini",
      "cursor-fast",
      "cursor-small",
    }
  end

  local api_key = get_api_key(provider_name)
  local base_url = get_base_url(provider_name)
  local provider_cfg = get_provider_config(provider_name)

  if not provider_cfg.models_endpoint then
    return {}
  end

  local url = base_url .. provider_cfg.models_endpoint

  local header_args = {}
  for _, h in ipairs(provider_cfg.headers(api_key)) do
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
    local id = m.id
    if provider_name == "anthropic" and m.type == "model" then
      table.insert(models, id)
    elseif provider_name ~= "anthropic" then
      table.insert(models, id)
    end
  end
  return models
end

function M.count_tokens(text)
  if not text or text == "" then
    return 0
  end
  return math.ceil(#text / 4)
end

function M.get_provider_info()
  local plugin_config = require("tua.config").get()
  return plugin_config.provider
end

return M
