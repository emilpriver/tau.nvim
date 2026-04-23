if vim.g.tua_loaded then
	return
end
vim.g.tua_loaded = true

local cmd = vim.api.nvim_create_user_command

cmd("Tau", function()
	require("tua").show()
end, { nargs = 0, desc = "Open the tua chat" })

cmd("TauToggle", function()
	require("tua").toggle()
end, { nargs = 0, desc = "Toggle the tua chat" })

cmd("TauStop", function()
	require("tua").stop()
end, { nargs = 0, desc = "Stop the tua session" })

cmd("TauAbort", function()
	require("tua").abort()
end, { nargs = 0, desc = "Abort the current tua turn" })

cmd("TauNew", function()
	require("tua").new_session()
end, { nargs = 0, desc = "Start a new tua session" })

cmd("TauContinue", function()
	require("tua").continue_session()
end, { nargs = 0, desc = "Continue the most recent session" })

cmd("TauResume", function()
	require("tua").resume_session()
end, { nargs = 0, desc = "Resume a past session" })

cmd("TauCompact", function(opts)
	require("tua").compact(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Manually compact the session context" })

cmd("TauModel", function()
	require("tua").select_model()
end, { nargs = 0, desc = "Select a model" })

cmd("TauCycleModel", function()
	require("tua").cycle_model()
end, { nargs = 0, desc = "Cycle to the next model" })

cmd("TauCheckHealth", function()
	require("tua.health").run()
end, { nargs = 0, desc = "Run tua health checks" })

cmd("TauCycleThinking", function()
	require("tua").cycle_thinking_level()
end, { nargs = 0, desc = "Cycle thinking level" })

cmd("TauSelectThinking", function()
	require("tua").select_thinking_level()
end, { nargs = 0, desc = "Select thinking level" })

cmd("TauLayout", function(opts)
	require("tua.ui").toggle({ layout = opts.args ~= "" and opts.args or nil })
end, { nargs = "?", desc = "Toggle chat layout (side/float)" })

cmd("TauToggleLayout", function()
	require("tua").toggle()
end, { nargs = 0, desc = "Toggle chat layout without losing state" })

cmd("TauToggleChat", function()
	require("tua").toggle()
end, { nargs = 0, desc = "Toggle chat visibility" })

cmd("TauToggleThinking", function()
	require("tua").toggle_thinking()
end, { nargs = 0, desc = "Toggle thinking visibility" })

cmd("TauRefreshModels", function()
	require("tua").refresh_models()
end, { nargs = 0, desc = "Refresh available models" })

cmd("TauLogin", function(opts)
	require("tua").login(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Login to a provider", complete = function() return { "anthropic", "openai", "cursor" } end })

cmd("TauLogout", function(opts)
	require("tua").logout(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Remove stored credentials" })

cmd("TauListLogins", function()
	require("tua").list_logins()
end, { nargs = 0, desc = "List stored provider logins" })

cmd("TauZen", function()
	require("tua.ui.zen").toggle()
end, { nargs = 0, desc = "Toggle zen mode" })

cmd("TauSendMention", function()
	require("tua").send_mention()
end, { nargs = 0, desc = "Insert @mention for current buffer/selection" })

cmd("TauAgents", function()
	require("tua").show_agents()
end, { nargs = 0, desc = "Show loaded agent context files" })
