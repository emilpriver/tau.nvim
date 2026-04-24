if vim.g.tau_loaded then
	return
end
vim.g.tau_loaded = true

local cmd = vim.api.nvim_create_user_command

cmd("Tau", function(opts)
	local args = {}
	for part in opts.args:gmatch("%S+") do
		local key, value = part:match("^(%w+)=([^%s]+)$")
		if key and value then
			args[key] = value
		end
	end
	require("tau").show(args)
end, { nargs = "*", desc = "Open the tau chat (e.g. Tau layout=side)" })

cmd("TauToggle", function()
	require("tau").toggle()
end, { nargs = 0, desc = "Toggle the tau chat" })

cmd("TauStop", function()
	require("tau").stop()
end, { nargs = 0, desc = "Stop the tau session" })

cmd("TauAbort", function()
	require("tau").abort()
end, { nargs = 0, desc = "Abort the current tau turn" })

cmd("TauNew", function()
	require("tau").new_session()
end, { nargs = 0, desc = "Start a new tau session" })

cmd("TauContinue", function()
	require("tau").continue_session()
end, { nargs = 0, desc = "Continue the most recent session" })

cmd("TauResume", function()
	require("tau").resume_session()
end, { nargs = 0, desc = "Resume a past session" })

cmd("TauCompact", function(opts)
	require("tau").compact(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Manually compact the session context" })

cmd("TauModel", function()
	require("tau").select_model()
end, { nargs = 0, desc = "Select a model" })

cmd("TauCycleModel", function()
	require("tau").cycle_model()
end, { nargs = 0, desc = "Cycle to the next model" })

cmd("TauCheckHealth", function()
	require("tau.health").run()
end, { nargs = 0, desc = "Run tau health checks" })

cmd("TauCycleThinking", function()
	require("tau").cycle_thinking_level()
end, { nargs = 0, desc = "Cycle thinking level" })

cmd("TauSelectThinking", function()
	require("tau").select_thinking_level()
end, { nargs = 0, desc = "Select thinking level" })

cmd("TauLayout", function(opts)
	require("tau.ui").toggle({ layout = opts.args ~= "" and opts.args or nil })
end, { nargs = "?", desc = "Toggle chat layout (side/float)" })

cmd("TauToggleLayout", function()
	require("tau").toggle()
end, { nargs = 0, desc = "Toggle chat layout without losing state" })

cmd("TauClose", function()
	require("tau").close()
end, { nargs = 0, desc = "Close the tau chat and history" })

cmd("TauToggleChat", function()
	require("tau").toggle()
end, { nargs = 0, desc = "Toggle chat visibility" })

cmd("TauToggleThinking", function()
	require("tau").toggle_thinking()
end, { nargs = 0, desc = "Toggle thinking visibility" })

cmd("TauRefreshModels", function()
	require("tau").refresh_models()
end, { nargs = 0, desc = "Refresh available models" })

cmd("TauLogin", function(opts)
	require("tau").login(opts.args ~= "" and opts.args or nil)
end, {
	nargs = "?",
	desc = "Login to a provider",
	complete = function()
		local names = {}
		for name in pairs(require("tau.plugin").providers) do
			table.insert(names, name)
		end
		table.sort(names)
		return names
	end,
})

cmd("TauLogout", function(opts)
	require("tau").logout(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Remove stored credentials" })

cmd("TauListLogins", function()
	require("tau").list_logins()
end, { nargs = 0, desc = "List stored provider logins" })

cmd("TauZen", function()
	require("tau.ui.zen").toggle()
end, { nargs = 0, desc = "Toggle zen mode" })

cmd("TauSendMention", function()
	require("tau").send_mention()
end, { nargs = 0, desc = "Insert @mention for current buffer/selection" })

cmd("TauAgents", function()
	require("tau").show_agents()
end, { nargs = 0, desc = "Show loaded agent context files" })
