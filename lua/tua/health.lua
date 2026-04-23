local M = {}

local MIN_NVIM_VERSION = "0.10"

local function check_nvim_version()
  local version = vim.version()
  local current = string.format("%d.%d", version.major, version.minor)

  if vim.version.lt(vim.version(), vim.version.parse(MIN_NVIM_VERSION)) then
    vim.health.error(
      string.format("Neovim %s or higher is required (current: %s)", MIN_NVIM_VERSION, current)
    )
    return false
  end

  vim.health.ok(string.format("Neovim %s", current))
  return true
end

local function check_curl()
  local ok = vim.fn.executable("curl") == 1
  if ok then
    vim.health.ok("curl found")
  else
    vim.health.error("curl not found — required for API calls")
  end
  return ok
end

local function check_provider_config()
  local config = require("tua.config").get()
  local provider = config.provider.name

  local env_vars = {
    anthropic = "ANTHROPIC_API_KEY",
    openai = "OPENAI_API_KEY",
    cursor = "CURSOR_API_KEY",
  }

  local auth = require("tua.auth")
  local has_auth_key = auth.has_key(provider)

  if has_auth_key then
    vim.health.ok(string.format("%s credentials found in auth file", provider))
    return true
  end

  local env_var = env_vars[provider]
  if env_var then
    local has_env_key = vim.env[env_var] ~= nil
    if has_env_key then
      vim.health.ok(string.format("%s is set", env_var))
    else
      vim.health.warn(
        string.format("%s is not set and no auth file entry — run :TauLogin %s", env_var, provider)
      )
    end
  else
    vim.health.warn(string.format("Unknown provider: %s", provider))
  end
end

M.run = function(silent)
  if not vim.health then
    if not silent then
      print("Health check requires Neovim 0.10+")
    end
    return
  end

  check_nvim_version()
  check_curl()
  check_provider_config()
end

return M
