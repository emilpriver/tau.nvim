local M = {}

local tools = require("tua.tools")
local api = require("tua.api")

local MAX_TOOL_ITERATIONS = 20

function M.run_turn(provider_name, messages, opts)
	opts = opts or {}
	local on_tool_start = opts.on_tool_start or function() end
	local on_tool_result = opts.on_tool_result or function() end
	local on_text = opts.on_text or function() end
	local on_thinking = opts.on_thinking or function() end

	local current_messages = vim.deepcopy(messages)
	local iteration = 0

	while iteration < MAX_TOOL_ITERATIONS do
		iteration = iteration + 1

		local context = require("tua.context")
		local model = opts.model or require("tua.config").get().provider.model

		local should_warn, tokens, limit, ratio = context.should_warn(current_messages, model)
		if should_warn then
			vim.notify(
				string.format("Context at %.0f%% (%d / %d tokens)", ratio * 100, tokens, limit),
				vim.log.levels.WARN
			)
		end

		local should_compact = context.should_compact(current_messages, model)
		if should_compact then
			vim.notify("Auto-compacting context...", vim.log.levels.INFO)
			local compacted, saved = context.compact(current_messages, opts.instructions, provider_name)
			current_messages = compacted
			vim.notify(string.format("Compacted: freed %d tokens", saved), vim.log.levels.INFO)
		end

		local result = api.call(provider_name, current_messages, {
			tools = tools.get_tool_list(),
			thinking_level = opts.thinking_level,
			max_tokens = opts.max_tokens,
		})

		local has_tool_calls = #result.tool_uses > 0

		if result.text and result.text ~= "" then
			on_text(result.text)
		end

		if result.thinking and result.thinking ~= "" then
			on_thinking(result.thinking)
		end

		if not has_tool_calls then
			table.insert(current_messages, {
				role = "assistant",
				content = result.text,
			})
			return {
				text = result.text,
				thinking = result.thinking,
				tool_iterations = iteration - 1,
				messages = current_messages,
				usage = result.usage,
			}
		end

		local assistant_msg = {
			role = "assistant",
			content = result.text ~= "" and result.text or nil,
			tool_calls = {},
		}
		for _, tool_use in ipairs(result.tool_uses) do
			table.insert(assistant_msg.tool_calls, {
				id = tool_use.id,
				["function"] = {
					name = tool_use.name,
					arguments = vim.json.encode(tool_use.input),
				},
			})
		end
		table.insert(current_messages, assistant_msg)

		for _, tool_use in ipairs(result.tool_uses) do
			on_tool_start(tool_use.name, tool_use.input, tool_use.id)

			local tool_result = tools.execute(tool_use.name, tool_use.input)

			local is_error = tool_result.error ~= nil
			local content = is_error and tool_result.error or tool_result.text

			on_tool_result(tool_use.id, tool_use.name, tool_result, is_error)

			local result_msg = {
				role = "tool",
				tool_call_id = tool_use.id,
				content = content,
			}

			if provider_name == "anthropic" then
				result_msg = {
					role = "user",
					content = {
						{
							type = "tool_result",
							tool_use_id = tool_use.id,
							content = content,
							is_error = is_error,
						},
					},
				}
			end

			table.insert(current_messages, result_msg)
		end
	end

	vim.notify("Max tool iterations (" .. MAX_TOOL_ITERATIONS .. ") reached. Stopping.", vim.log.levels.WARN)

	return {
		text = "Max tool iterations reached",
		tool_iterations = iteration,
		messages = current_messages,
	}
end

function M.run_turn_streaming(provider_name, messages, opts)
	opts = opts or {}
	local on_tool_start = opts.on_tool_start or function() end
	local on_tool_result = opts.on_tool_result or function() end
	local on_text = opts.on_text or function() end
	local on_thinking = opts.on_thinking or function() end
	local on_done = opts.on_done or function() end

	local current_messages = vim.deepcopy(messages)
	local iteration = 0

	local function do_turn()
		iteration = iteration + 1

		local context = require("tua.context")
		local model = opts.model or require("tua.config").get().provider.model

		local should_warn, tokens, limit, ratio = context.should_warn(current_messages, model)
		if should_warn then
			vim.notify(
				string.format("Context at %.0f%% (%d / %d tokens)", ratio * 100, tokens, limit),
				vim.log.levels.WARN
			)
		end

		local should_compact = context.should_compact(current_messages, model)
		if should_compact then
			vim.notify("Auto-compacting context...", vim.log.levels.INFO)
			local compacted, saved = context.compact(current_messages, opts.instructions, provider_name)
			current_messages = compacted
			vim.notify(string.format("Compacted: freed %d tokens", saved), vim.log.levels.INFO)
		end

		local tool_calls = {}
		local tool_inputs = {}
		local text_response = ""
		local thinking_response = ""

		local function on_chunk(text)
			text_response = text_response .. text
			on_text(text)
		end

		local function on_think(text)
			thinking_response = thinking_response .. text
			on_thinking(text)
		end

		local function on_tool(name, input, id)
			if id then
				if not tool_calls[id] then
					tool_calls[id] = { name = name, input_str = "", id = id }
					tool_inputs[id] = name
				end
				if input and type(input) == "string" then
					tool_calls[id].input_str = tool_calls[id].input_str .. input
				end
			elseif name then
				local new_id = "tool_call_" .. #tool_calls + 1
				tool_calls[new_id] = { name = name, input_str = "", id = new_id }
				if type(input) == "string" then
					tool_calls[new_id].input_str = tool_calls[new_id].input_str .. input
				end
			end
		end

		local done = false

		local function on_stream_done()
			if not done then
				done = true

				for id, tc in pairs(tool_calls) do
					local parsed_input = {}
					if tc.input_str and tc.input_str ~= "" then
						local ok, parsed = pcall(vim.json.decode, tc.input_str)
						if ok then
							parsed_input = parsed
						end
					end
					on_tool_start(tc.name, parsed_input, id)

					local result = tools.execute(tc.name, parsed_input)
					local is_error = result.error ~= nil
					local content = is_error and result.error or result.text

					on_tool_result(id, tc.name, result, is_error)

					local result_msg
					if provider_name == "anthropic" then
						result_msg = {
							role = "user",
							content = {
								{
									type = "tool_result",
									tool_use_id = id,
									content = content,
									is_error = is_error,
								},
							},
						}
					else
						result_msg = {
							role = "tool",
							tool_call_id = id,
							content = content,
						}
					end

					local tc = tool_calls[id]
					local assistant_msg = {
						role = "assistant",
						tool_calls = {
							{
								id = id,
								call_id = id,
								["function"] = {
									name = tc.name,
									arguments = tc.input_str,
								},
							},
						},
					}
					if text_response ~= "" then
						assistant_msg.content = text_response
					end
					if thinking_response ~= "" then
						assistant_msg.reasoning = thinking_response
					end
					table.insert(current_messages, assistant_msg)
					table.insert(current_messages, result_msg)
				end

				if #tool_calls > 0 then
					vim.schedule(do_turn)
				else
					on_done()
				end
			end
		end

		api.stream(provider_name, current_messages, {
			tools = tools.get_tool_list(),
			thinking_level = opts.thinking_level,
			max_tokens = opts.max_tokens,
			on_chunk = on_chunk,
			on_thinking = on_think,
			on_tool_use = on_tool,
			on_done = on_stream_done,
			on_error = function(err)
				vim.notify("Stream error: " .. err, vim.log.levels.ERROR)
				on_done()
			end,
		})
	end

	vim.schedule(do_turn)
end

return M
