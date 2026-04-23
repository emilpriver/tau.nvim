local M = {}

local defaults = {
  provider = {
    name = "anthropic",
    model = nil,
    base_url = nil,
  },

  models = nil,

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
    prompt = { title = "󰫽󰫿󰫼󰫺󰫽󰬁" },
    attachments = { title = "󰫮󰬁󰬁󰫮󰫰󰫵󰫺󰫲󰫻󰬁󰬀" },
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

  diff = {
    context = {
      base = nil,
      step = 5,
    },
    keys = {
      accept = "<Leader>da",
      reject = "<Leader>dr",
      expand_context = "<Leader>de",
      shrink_context = "<Leader>ds",
    },
  },

  attention = {
    auto_open_on_prompt_focus = true,
    notify_on_completion = true,
  },

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

  require("tua.health").run(true)

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
