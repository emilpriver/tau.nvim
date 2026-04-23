local M = {}

M.providers = {}
M.models = {}
M.fallback_models = {}
M.auth_help = {}

function M.register_provider(plugin)
	if not plugin or not plugin.name then
		error("Provider plugin must export a 'name' field")
	end
	M.providers[plugin.name] = plugin
	if type(plugin.register) == "function" then
		plugin.register(M)
	end
end

function M.register_model(model_id, meta)
	M.models[model_id] = vim.tbl_deep_extend("force", { context_limit = 128000 }, meta or {})
end

function M.register_fallback(provider_name, ...)
	M.fallback_models[provider_name] = { ... }
end

function M.register_auth_help(provider_name, name, key_url, prompt)
	M.auth_help[provider_name] = { name = name, key_url = key_url, prompt = prompt }
end

function M.get_provider(name)
	return M.providers[name]
end

function M.get_model_meta(model_id)
	return M.models[model_id] or { context_limit = 128000 }
end

function M.get_fallback_models(provider_name)
	return M.fallback_models[provider_name] or {}
end

function M.get_auth_help(provider_name)
	return M.auth_help[provider_name]
end

function M.load_plugins(paths)
	for _, mod in ipairs(paths or {}) do
		local ok, plugin = pcall(require, mod)
		if ok and plugin and plugin.setup then
			plugin.setup(M)
		else
			vim.notify("Failed to load plugin: " .. mod, vim.log.levels.WARN)
		end
	end
end

function M.init(opts)
	opts = opts or {}
	M.load_plugins(opts.plugins)
end

return M
