local M = {}

local config = require("tau.config")

function M.setup(opts)
	opts = opts or {}
	config.setup(opts)
	require("tau.session_storage").TauEnsureBuiltinRegistered()
	require("tau.plugin").init({ plugins = opts.plugins })
	require("tau.mentions").init({
		mention_plugins = opts.mention_plugins or {},
	})
end

function M.show(opts)
	require("tau.ui").open(opts)
end

function M.toggle(opts)
	require("tau.ui").toggle(opts)
end

function M.close()
	require("tau.ui").close()
end

function M.focus_history()
	require("tau.ui").focus_history()
end

function M.focus_prompt()
	require("tau.ui").focus_prompt()
end

function M.scroll_history(direction, lines)
	require("tau.ui").scroll_history(direction, lines)
end

function M.scroll_history_to_bottom()
	require("tau.ui").scroll_history_to_bottom()
end

function M.stop()
	require("tau.rpc").stop()
end

function M.abort()
	require("tau.rpc").abort()
end

function M.new_session(opts)
	opts = opts or {}
	local state = require("tau.state")
	local agents = require("tau.agents")
	local tauConfig = require("tau.config").get()

	local session = state.create_session({
		cwd = vim.fn.getcwd(),
		provider = tauConfig.provider.name,
		model = tauConfig.provider.model,
	})

	local system_prompt = agents.build_system_prompt(session.cwd, session.provider)
	if system_prompt then
		table.insert(session.messages, {
			role = "system",
			content = system_prompt,
			_hidden = true,
		})
	end

	state.set_session(nil, session)
	require("tau.session").TauSessionAutosave(session)
	local ui = require("tau.ui")
	if ui.active then
		ui.active.tau_tab_id = vim.api.nvim_get_current_tabpage()
		ui.active.session = session
		ui.refresh()
	end
	if not opts.silent then
		vim.notify("New session started", vim.log.levels.INFO)
	end
end

function M.continue_session()
	require("tau.session").load_most_recent(vim.fn.getcwd())
end

function M.resume_session()
	require("tau.session").pick_and_load(vim.fn.getcwd())
end

function M.compact(instructions)
	local state = require("tau.state")
	local context = require("tau.context")
	local session = state.get_session()

	if not session or #session.messages == 0 then
		vim.notify("No active session to compact", vim.log.levels.WARN)
		return
	end

	local provider = session.provider or require("tau.config").get().provider.name
	local before = context.count_messages_tokens(session.messages)

	vim.notify("Compacting session context...", vim.log.levels.INFO)

	local compacted, saved = context.compact(session.messages, instructions, provider)
	session.messages = compacted
	session.compacted_count = (session.compacted_count or 0) + 1
	state.update_session_tokens()
	require("tau.session").TauSessionAutosave(session)

	local after = context.count_messages_tokens(session.messages)
	vim.notify(
		string.format("Compacted: %d → %d tokens (freed %d)", before, after, before - after),
		vim.log.levels.INFO
	)
end

function M.select_model()
	require("tau.models").select(function()
		M.sync_session_model()
	end)
end

function M.sync_session_model()
	local session = require("tau.state").get_session()
	if session then
		session.model = require("tau.models").get_active()
	end
	require("tau.ui").refresh_winbar()
end

function M.cycle_thinking_level()
	require("tau.models").cycle_thinking_level()
end

function M.select_thinking_level()
	require("tau.models").select_thinking_level()
end

function M.get_thinking_level()
	return require("tau.models").get_thinking_level()
end

function M.toggle_thinking()
	local cfg = require("tau.config").get()
	cfg.show_thinking = not cfg.show_thinking
	local status = cfg.show_thinking and "on" or "off"
	vim.notify("Thinking display: " .. status, vim.log.levels.INFO)
	local ui = require("tau.ui")
	if ui.active then
		ui.refresh()
	end
end

function M.get_provider()
	return require("tau.api").get_provider_info()
end

function M.stream(messages, opts)
	local provider = require("tau.config").get().provider.name
	return require("tau.api").stream(provider, messages, opts)
end

function M.call(messages, opts)
	local provider = require("tau.config").get().provider.name
	return require("tau.api").call(provider, messages, opts)
end

function M.refresh_models()
	require("tau.models").refresh()
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

function M.login(provider_name)
	provider_name = trim(provider_name)
	if not provider_name or provider_name == "" then
		vim.notify("missing provider", vim.log.levels.ERROR)
		return
	end

	local auth = require("tau.auth")
	local plugin = require("tau.plugin")

	if not plugin.auth_help or vim.tbl_isempty(plugin.auth_help) then
		vim.notify("No registered providers", vim.log.levels.ERROR)
		return
	end

	local info = plugin.get_auth_help(provider_name)

	if not info then
		local supported = {}
		for name in pairs(plugin.auth_help or {}) do
			table.insert(supported, name)
		end
		vim.notify(
			"Unknown provider: " .. provider_name .. ". Supported: " .. table.concat(supported, ", "),
			vim.log.levels.ERROR
		)
		return
	end

	vim.ui.input({
		prompt = info.prompt .. "\nGenerate a key at: " .. info.key_url .. "\n\nAPI key: ",
	}, function(key)
		if not key or key == "" then
			return
		end
		if auth.set_key(provider_name, key) then
			vim.notify(provider_name .. " credentials saved to " .. auth.get_auth_path(), vim.log.levels.INFO)
		else
			vim.notify("Failed to save credentials", vim.log.levels.ERROR)
		end
	end)
end

function M.logout(provider_name)
	local auth = require("tau.auth")

	if provider_name then
		if auth.remove_key(provider_name) then
			vim.notify(provider_name .. " credentials removed", vim.log.levels.INFO)
		else
			vim.notify("No credentials found for " .. provider_name, vim.log.levels.WARN)
		end
		return
	end

	local providers = auth.list_providers()
	if #providers == 0 then
		vim.notify("No stored credentials", vim.log.levels.INFO)
		return
	end

	vim.ui.select(providers, {
		prompt = "Remove credentials for:",
	}, function(choice)
		if choice then
			auth.remove_key(choice)
			vim.notify(choice .. " credentials removed", vim.log.levels.INFO)
		end
	end)
end

function M.show_agents()
	local agents = require("tau.agents")
	local files = agents.list_loaded_files()

	if #files == 0 then
		vim.notify("No agent files loaded. Create ~/.agents/AGENTS.md or .agents/AGENTS.md", vim.log.levels.INFO)
		return
	end

	local lines = { "Loaded agent files:", "" }
	for _, f in ipairs(files) do
		local scope = f.scope == "global" and "[global]" or "[project]"
		table.insert(lines, string.format("  %s %s — %s", scope, f.name, f.path))
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.list_logins()
	local auth = require("tau.auth")
	local providers = auth.list_providers()
	if #providers == 0 then
		vim.notify("No stored credentials", vim.log.levels.INFO)
		return
	end
	vim.notify("Stored providers: " .. table.concat(providers, ", "), vim.log.levels.INFO)
end

function M.insert_prompt_context(opts)
	return require("tau.mentions").insert_into_prompt(opts or {})
end

function M.send_mention()
	return M.insert_prompt_context({})
end

function M.register_mention_provider(provider)
	require("tau.mentions").register(provider)
end

function M.attach_image(path)
	local att = require("tau.attachments")
	local result, err = att.attach_file(path)
	if not result then
		vim.notify(err, vim.log.levels.ERROR)
		return nil
	end
	return result
end

function M.paste_image()
	error("not implemented — requires img-clip.nvim integration")
end

function M.build_user_message(text, attachments)
	local provider = require("tau.config").get().provider.name
	return require("tau.attachments").build_user_message(text, attachments, provider)
end

function M.attention_count(tab_id)
	return 0
end

function M.attention_total()
	return 0
end

function M.has_attention(tab_id)
	return false
end

function M.changed_files()
	return require("tau.tools").get_changed_files()
end

function M.run_turn(messages, opts)
	local provider = require("tau.config").get().provider.name
	return require("tau.dispatcher").run_turn(provider, messages, opts)
end

function M.run_turn_streaming(messages, opts)
	local provider = require("tau.config").get().provider.name
	return require("tau.dispatcher").run_turn_streaming(provider, messages, opts)
end

function M.get_tool_list()
	return require("tau.tools").get_tool_list()
end

function M.register_provider(plugin_module)
	require("tau.plugin").register_provider(plugin_module)
end

function M.register_session_storage(name, provider)
	require("tau.session_storage").TauRegisterSessionStorage(name, provider)
end

function M.set_session_storage(name)
	return require("tau.session_storage").TauSetSessionStorage(name)
end

function M.get_session_storage()
	return require("tau.session_storage").TauGetSessionStorage()
end

M.TauRegisterSessionStorage = M.register_session_storage
M.TauSetSessionStorage = M.set_session_storage
M.TauGetSessionStorage = M.get_session_storage

function M.end_session()
	require("tau.session").TauSessionEnd()
end

function M.set_session_name(name)
	require("tau.session").TauSessionSetName(name)
end

function M.export_session_html(path)
	require("tau.session").TauSessionExportHtml(path)
end

function M.session_info()
	require("tau.session").TauSessionInfo()
end

function M.generate_session_title(opts)
	require("tau.session_title").generate_now(opts or {})
end

function M.TauSessionTree()
	require("tau.session").TauSessionTree()
end

function M.TauSessionFork(message_index)
	require("tau.session").TauSessionFork(message_index)
end

function M.TauSessionClone()
	require("tau.session").TauSessionClone()
end

function M.get_mention_provider()
	return require("tau.mentions").get_active()
end

-- Queue management functions
function M.queue_push(text, type_)
	require("tau.ui.queue").push(text, type_ or "steer")
end

function M.queue_pop()
	return require("tau.ui.queue").pop()
end

function M.queue_clear()
	require("tau.ui.queue").clear()
end

function M.queue_size()
	return require("tau.ui.queue").size()
end

function M.queue_get_all()
	return require("tau.ui.queue").get_all()
end

function M.queue_get_info()
	return require("tau.ui.queue").get_info()
end

function M.queue_remove(index)
	return require("tau.ui.queue").remove_at(index)
end

function M.queue_move(index, direction)
	local q = require("tau.ui.queue")
	if direction == "up" or direction == -1 then
		q.move_up(index)
	elseif direction == "down" or direction == 1 then
		q.move_down(index)
	end
end

function M.queue_set_busy(busy)
	require("tau.ui.queue").set_busy(busy)
end

function M.open_queue_modal()
	require("tau.ui.queue_modal").open()
end

function M.show_queue()
	M.open_queue_modal()
end

function M.clear_queue()
	M.queue_clear()
end

function M.remove_queued(idx)
	M.queue_remove(idx)
end

return M
