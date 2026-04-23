local M = {}

local plugins = require("tau.plugin")

local function get_api_key(provider_name)
	local auth_key = require("tau.auth").get_key(provider_name)
	if auth_key then
		return auth_key
	end
	local plugin = plugins.get_provider(provider_name)
	if not plugin then
		error("Unknown provider: " .. provider_name)
	end
	local key = vim.env[plugin.api_key_env]
	if not key then
		error(
			"API key not found for "
				.. provider_name
				.. ". Run :TauLogin "
				.. provider_name
				.. " or set "
				.. plugin.api_key_env
		)
	end
	return key
end

local function get_base_url(provider_name)
	local plugin = plugins.get_provider(provider_name)
	local plugin_config = require("tau.config").get()
	return plugin_config.provider.base_url or plugin.base_url
end

local function get_model(provider_name)
	local plugin = plugins.get_provider(provider_name)
	local plugin_config = require("tau.config").get()
	return plugin_config.provider.model or plugin.default_model
end

function M.stream(provider_name, messages, opts)
	local plugin = plugins.get_provider(provider_name)
	if not plugin then
		error("Unknown provider: " .. provider_name)
	end

	local api_key = get_api_key(provider_name)
	local base_url = get_base_url(provider_name)
	local model = get_model(provider_name)

	return plugin.stream(api_key, base_url, model, messages, opts)
end

function M.call(provider_name, messages, opts)
	local plugin = plugins.get_provider(provider_name)
	if not plugin then
		error("Unknown provider: " .. provider_name)
	end

	local api_key = get_api_key(provider_name)
	local base_url = get_base_url(provider_name)
	local model = get_model(provider_name)

	return plugin.call(api_key, base_url, model, messages, opts)
end

function M.list_models(provider_name)
	local plugin = plugins.get_provider(provider_name)
	if not plugin then
		return {}
	end

	local api_key = get_api_key(provider_name)
	local base_url = get_base_url(provider_name)

	return plugin.list_models(api_key, base_url)
end

function M.count_tokens(text)
	if not text or text == "" then
		return 0
	end
	return math.ceil(#text / 4)
end

function M.get_provider_info()
	local plugin_config = require("tau.config").get()
	return plugin_config.provider
end

return M
