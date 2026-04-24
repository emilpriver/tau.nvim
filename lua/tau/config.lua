local M = {}

local defaults = {
	provider = {
		name = "opencode",
		model = nil,
		base_url = nil,
	},

	models = nil,

	mention_provider = "files",
	mention_plugins = {},

	layout = {
		default = "side",
		side = {
			position = "right",
			width = 80,
			panels = {
				history = { winbar = true },
				prompt = { winbar = true },
				attachments = { winbar = true },
			},
		},
		float = {
			width = 0.6,
			height = 0.8,
			border = "rounded",
		},
	},

	panels = {
		history = { title = "π" },
		prompt = { title = "Prompt" },
		attachments = { title = "attachments" },
	},

	labels = {
		user_message = "",
		agent_response = "󰚩",
		system_error = "󱚟",
		tool = "󰻂",
		tool_success = "",
		tool_failure = "",
		steer_message = "󰾘",
		follow_up_message = "󱇼",
		thinking = "󰟶",
		attachment = "",
		attachments = "",
		error = "󰘨 󱚟 󱔁 ",
	},

	spinner = "robot",

	show_thinking = false,
	expand_startup_details = true,

	dialog = {
		border = "rounded",
		max_width = 0.8,
		max_height = 0.8,
		indicator = "▸",
		keys = {
			confirm = nil,
			cancel = nil,
			next = nil,
			prev = nil,
		},
	},

	zen = {
		width = nil,
		keys = {
			toggle = nil,
			exit = nil,
		},
	},

	statusline = {
		layout = {
			left = { "context", "  ", "attention" },
			right = { "model", "   ", "thinking" },
		},
		components = {
			tokens = { icon = "" },
			cache = { icon = "󰆼" },
			cost = { icon = "" },
			compaction = { icon = false },
			context = { icon = "", warn = 70, error = 90 },
			attention = { icon = "󰵚", counter = false },
			model = { icon = "󰚩" },
			thinking = { icon = "󰟶" },
		},
	},

	verbs = {
		use_defaults = true,
		pairs = {},
	},

	on_widget = nil,

	session = {
		auto_llm_title = true,
		title_max_chars_excerpt = 4000,
		title_max_length = 56,
		title_model = nil,
	},
}

local active = nil

local function deep_merge(a, b)
	local result = vim.deepcopy(a)
	for k, v in pairs(b) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = deep_merge(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

M.setup = function(opts)
	opts = opts or {}
	active = deep_merge(defaults, opts)

	require("tau.health").run(true)

	vim.api.nvim_exec_autocmds("User", { pattern = "AgentSetup", modeline = false })

	return active
end

M.get = function()
	if not active then
		active = vim.deepcopy(defaults)
	end
	return active
end

M.reset = function()
	active = nil
end

return M
