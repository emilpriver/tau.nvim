local M = {}

local tools = require("tau.tools")
local api = require("tau.api")

local MAX_TOOL_ITERATIONS = 20

local active_stream_handle = nil
local cancelled = false

local function count_tool_calls(tool_calls)
	local count = 0
	for _ in pairs(tool_calls) do
		count = count + 1
	end
	return count
end

function M.stop()
	cancelled = true
	if active_stream_handle and active_stream_handle.kill then
		pcall(function()
			active_stream_handle:kill(9)
		end)
	end
	active_stream_handle = nil
end

function M.is_running()
	return active_stream_handle ~= nil
end

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

		local context = require("tau.context")
		local model = opts.model or require("tau.config").get().provider.model

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

		local ok, result = pcall(api.call, provider_name, current_messages, {
			tools = tools.get_tool_list(),
			thinking_level = opts.thinking_level,
			max_tokens = opts.max_tokens,
		})

		if not ok then
			vim.notify(tostring(result), vim.log.levels.ERROR)
			return {
				text = tostring(result),
				tool_iterations = iteration - 1,
				messages = current_messages,
			}
		end

		local has_tool_calls = #result.tool_uses > 0

		if result.text and result.text ~= "" then
			on_text(result.text)
		end

		if result.thinking and result.thinking ~= "" then
			on_thinking(result.thinking)
		end

		if not has_tool_calls then
			local msg = {
				role = "assistant",
				content = result.text or "",
			}
			if opts.thinking_level and opts.thinking_level ~= "off" then
				msg.reasoning_content = (result.thinking and result.thinking ~= "") and result.thinking or ""
			elseif result.thinking and result.thinking ~= "" then
				msg.reasoning_content = result.thinking
			end
			table.insert(current_messages, msg)
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
			content = result.text ~= "" and result.text or "",
			tool_calls = {},
		}
		if opts.thinking_level and opts.thinking_level ~= "off" then
			assistant_msg.reasoning_content = (result.thinking and result.thinking ~= "") and result.thinking or ""
		elseif result.thinking and result.thinking ~= "" then
			assistant_msg.reasoning_content = result.thinking
		end
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

			table.insert(current_messages, {
				role = "tool",
				tool_call_id = tool_use.id,
				content = content,
			})
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
	local on_error = opts.on_error or function(err)
		vim.notify(err, vim.log.levels.ERROR)
	end

	local iteration = 0

	local function do_turn()
		iteration = iteration + 1

		local context = require("tau.context")
		local model = opts.model or require("tau.config").get().provider.model

		local should_warn, tokens, limit, ratio = context.should_warn(messages, model)
		if should_warn then
			vim.notify(
				string.format("Context at %.0f%% (%d / %d tokens)", ratio * 100, tokens, limit),
				vim.log.levels.WARN
			)
		end

		local should_compact = context.should_compact(messages, model)
		if should_compact then
			vim.notify("Auto-compacting context...", vim.log.levels.INFO)
			local compacted, saved = context.compact(messages, opts.instructions, provider_name)
			messages = compacted
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
				local new_id = "tool_call_" .. count_tool_calls(tool_calls) + 1
				tool_calls[new_id] = { name = name, input_str = "", id = new_id }
				if type(input) == "string" then
					tool_calls[new_id].input_str = tool_calls[new_id].input_str .. input
				end
			end
		end

		local done = false

		local function on_stream_done()
			if done then
				return
			end
			done = true

			local assistant_msg = {
				role = "assistant",
				content = text_response ~= "" and text_response or "",
			}
			if opts.thinking_level and opts.thinking_level ~= "off" then
				assistant_msg.reasoning_content = thinking_response ~= "" and thinking_response or ""
			elseif thinking_response ~= "" then
				assistant_msg.reasoning_content = thinking_response
			end
			if count_tool_calls(tool_calls) > 0 then
				assistant_msg.tool_calls = {}
				for id, tc in pairs(tool_calls) do
					table.insert(assistant_msg.tool_calls, {
						id = id,
						["function"] = {
							name = tc.name,
							arguments = tc.input_str,
						},
					})
				end
			end
			table.insert(messages, assistant_msg)

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

				table.insert(messages, {
					role = "tool",
					tool_call_id = id,
					content = content,
				})
			end

			if count_tool_calls(tool_calls) > 0 then
				vim.schedule(do_turn)
			else
				on_done()
			end
		end

		cancelled = false
		local stream_ok, stream_err = pcall(api.stream, provider_name, messages, {
			tools = tools.get_tool_list(),
			thinking_level = opts.thinking_level,
			max_tokens = opts.max_tokens,
			on_chunk = function(text)
				if cancelled then
					return
				end
				on_chunk(text)
			end,
			on_thinking = function(text)
				if cancelled then
					return
				end
				on_think(text)
			end,
			on_tool_use = function(name, args, id)
				if cancelled then
					return
				end
				on_tool(name, args, id)
			end,
			on_done = function()
				active_stream_handle = nil
				if cancelled then
					return
				end
				on_stream_done()
			end,
			on_error = function(err)
				active_stream_handle = nil
				if cancelled then
					return
				end
				vim.schedule(function()
					on_error(err)
				end)
			end,
		})

		if stream_ok then
			active_stream_handle = stream_err
		else
			vim.schedule(function()
				on_error(tostring(stream_err))
			end)
			on_done()
		end
	end

	vim.schedule(do_turn)
end

return M
