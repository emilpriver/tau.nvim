local M = {}

local GLOBAL_AGENTS_DIR = vim.fn.expand("~/.agents")

local AGENT_FILENAMES = {
	"AGENTS.md",
}

local SYSTEM_FILENAMES = {
	"SYSTEM.md",
	"APPEND_SYSTEM.md",
}

local function file_exists(path)
	return vim.fn.filereadable(path) == 1
end

local function dir_exists(path)
	return vim.fn.isdirectory(path) == 1
end

local function read_file(path)
	if not file_exists(path) then
		return nil
	end
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

local function walk_parents(start_dir)
	local dirs = {}
	local current = vim.fn.resolve(start_dir)

	while current and current ~= "/" and current ~= "" do
		table.insert(dirs, 1, current)
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	return dirs
end

function M.load_global()
	local result = {}

	if not dir_exists(GLOBAL_AGENTS_DIR) then
		return result
	end

	for _, filename in ipairs(AGENT_FILENAMES) do
		local path = GLOBAL_AGENTS_DIR .. "/" .. filename
		local content = read_file(path)
		if content then
			result[filename] = {
				path = path,
				content = content,
			}
		end
	end

	for _, filename in ipairs(SYSTEM_FILENAMES) do
		local path = GLOBAL_AGENTS_DIR .. "/" .. filename
		local content = read_file(path)
		if content then
			result[filename] = {
				path = path,
				content = content,
			}
		end
	end

	return result
end

function M.load_project(cwd)
	cwd = cwd or vim.fn.getcwd()
	local result = {}

	local parent_dirs = walk_parents(cwd)

	for _, dir in ipairs(parent_dirs) do
		local agents_dir = dir .. "/.agents"
		if dir_exists(agents_dir) then
			for _, filename in ipairs(AGENT_FILENAMES) do
				local path = agents_dir .. "/" .. filename
				local content = read_file(path)
				if content then
					result[filename] = result[filename] or {}
					table.insert(result[filename], {
						path = path,
						content = content,
						dir = dir,
					})
				end
			end

			for _, filename in ipairs(SYSTEM_FILENAMES) do
				local path = agents_dir .. "/" .. filename
				local content = read_file(path)
				if content then
					result[filename] = result[filename] or {}
					table.insert(result[filename], {
						path = path,
						content = content,
						dir = dir,
					})
				end
			end
		end
	end

	return result
end

function M.load_context(cwd)
	cwd = cwd or vim.fn.getcwd()
	local global = M.load_global()
	local project = M.load_project(cwd)

	local agents_parts = {}

	for _, filename in ipairs(AGENT_FILENAMES) do
		if global[filename] then
			table.insert(agents_parts, global[filename].content)
		end
		if project[filename] then
			for _, item in ipairs(project[filename]) do
				table.insert(agents_parts, item.content)
			end
		end
	end

	local system = nil
	local append = nil

	if global["SYSTEM.md"] then
		system = global["SYSTEM.md"].content
	end
	if project["SYSTEM.md"] then
		for _, item in ipairs(project["SYSTEM.md"]) do
			system = item.content
		end
	end

	local append_parts = {}
	if global["APPEND_SYSTEM.md"] then
		table.insert(append_parts, global["APPEND_SYSTEM.md"].content)
	end
	if project["APPEND_SYSTEM.md"] then
		for _, item in ipairs(project["APPEND_SYSTEM.md"]) do
			table.insert(append_parts, item.content)
		end
	end
	if #append_parts > 0 then
		append = table.concat(append_parts, "\n\n")
	end

	return {
		global = global,
		project = project,
		agents = #agents_parts > 0 and table.concat(agents_parts, "\n\n") or nil,
		system = system,
		append = append,
	}
end

function M.list_context_sources(cwd)
	cwd = cwd or vim.fn.getcwd()
	local global = M.load_global()
	local project = M.load_project(cwd)
	local agents = {}
	local system = {}
	local append = {}

	for _, filename in ipairs(AGENT_FILENAMES) do
		if global[filename] then
			table.insert(agents, { name = filename, path = global[filename].path })
		end
		if project[filename] then
			for _, item in ipairs(project[filename]) do
				table.insert(agents, { name = filename, path = item.path })
			end
		end
	end

	if global["SYSTEM.md"] then
		table.insert(system, { name = "SYSTEM.md", path = global["SYSTEM.md"].path })
	end
	if project["SYSTEM.md"] then
		for _, item in ipairs(project["SYSTEM.md"]) do
			table.insert(system, { name = "SYSTEM.md", path = item.path })
		end
	end

	if global["APPEND_SYSTEM.md"] then
		table.insert(append, { name = "APPEND_SYSTEM.md", path = global["APPEND_SYSTEM.md"].path })
	end
	if project["APPEND_SYSTEM.md"] then
		for _, item in ipairs(project["APPEND_SYSTEM.md"]) do
			table.insert(append, { name = "APPEND_SYSTEM.md", path = item.path })
		end
	end

	return { agents = agents, system = system, append = append }
end

function M.build_system_prompt(cwd, provider_name)
	local ctx = M.load_context(cwd)
	local parts = {}

	if ctx.system then
		return ctx.system
	end

	if ctx.agents then
		table.insert(parts, ctx.agents)
	end

	if ctx.append then
		table.insert(parts, ctx.append)
	end

	if #parts == 0 then
		return nil
	end

	return table.concat(parts, "\n\n")
end

function M.list_loaded_files(cwd)
	cwd = cwd or vim.fn.getcwd()
	local ctx = M.load_context(cwd)
	local files = {}

	for name, item in pairs(ctx.global) do
		table.insert(files, {
			name = name,
			path = item.path,
			scope = "global",
		})
	end

	for name, items in pairs(ctx.project) do
		for _, item in ipairs(items) do
			table.insert(files, {
				name = name,
				path = item.path,
				scope = "project",
				dir = item.dir,
			})
		end
	end

	return files
end

return M
