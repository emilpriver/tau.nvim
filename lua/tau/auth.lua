local M = {}

local auth_path = vim.fn.stdpath("data") .. "/tau/auth.json"

local function ensure_dir()
	local dir = vim.fn.fnamemodify(auth_path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		local ok = vim.fn.mkdir(dir, "p", 448)
		if ok ~= 1 then
			vim.notify("Failed to create auth directory: " .. dir, vim.log.levels.ERROR)
			return false
		end
	end
	return true
end

local function load()
	if vim.fn.filereadable(auth_path) == 0 then
		return {}
	end
	local f = io.open(auth_path, "r")
	if not f then
		return {}
	end
	local content = f:read("*all")
	f:close()
	local success, data = pcall(vim.json.decode, content)
	if not success then
		vim.notify("Failed to parse auth file: " .. data, vim.log.levels.WARN)
		return {}
	end
	return data or {}
end

local function save(data)
	if not ensure_dir() then
		return false
	end
	local content = vim.json.encode(data)
	local f, err = io.open(auth_path, "w")
	if not f then
		vim.notify(
			"Failed to write auth file: " .. auth_path .. " (" .. (err or "unknown error") .. ")",
			vim.log.levels.ERROR
		)
		return false
	end
	f:write(content)
	f:close()

	vim.uv.fs_chmod(auth_path, 384)
	return true
end

local function resolve_key(value)
	if not value or value == "" then
		return nil
	end

	if value:sub(1, 1) == "!" then
		local cmd = value:sub(2)
		local result = vim.fn.system(cmd)
		if vim.v.shell_error ~= 0 then
			return nil
		end
		return vim.trim(result)
	end

	if value:match("^[A-Z][A-Z0-9_]+$") and not value:match("sk%-") then
		local env_val = vim.env[value]
		if env_val then
			return env_val
		end
	end

	return value
end

function M.get_key(provider_name)
	local data = load()
	local entry = data[provider_name]
	if entry then
		if type(entry) == "table" and entry.type == "api_key" then
			return resolve_key(entry.key)
		elseif type(entry) == "string" then
			return resolve_key(entry)
		end
	end
	return nil
end

function M.set_key(provider_name, key)
	local data = load()
	data[provider_name] = { type = "api_key", key = key }
	return save(data)
end

function M.remove_key(provider_name)
	local data = load()
	if data[provider_name] then
		data[provider_name] = nil
		return save(data)
	end
	return false
end

function M.list_providers()
	local data = load()
	local providers = {}
	for k in pairs(data) do
		table.insert(providers, k)
	end
	table.sort(providers)
	return providers
end

function M.has_key(provider_name)
	return M.get_key(provider_name) ~= nil
end

function M.get_auth_path()
	return auth_path
end

return M
