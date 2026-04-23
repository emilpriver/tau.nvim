local M = {}

local GLOBAL_AGENTS_DIR = vim.fn.expand("~/.agents")

local AGENT_FILENAMES = {
	"AGENTS.md",
	"CLAUDE.md",
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
	local claude_parts = {}

	for _, filename in ipairs(AGENT_FILENAMES) do
		if filename == "AGENTS.md" then
			if global[filename] then
				table.insert(agents_parts, global[filename].content)
			end
			if project[filename] then
				for _, item in ipairs(project[filename]) do
					table.insert(agents_parts, item.content)
				end
			end
		elseif filename == "CLAUDE.md" then
			if global[filename] then
				table.insert(claude_parts, global[filename].content)
			end
			if project[filename] then
				for _, item in ipairs(project[filename]) do
					table.insert(claude_parts, item.content)
				end
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
		claude = #claude_parts > 0 and table.concat(claude_parts, "\n\n") or nil,
		system = system,
		append = append,
	}
end

function M.build_system_prompt(cwd, provider_name)
	local ctx = M.load_context(cwd)
	local parts = {}

	if ctx.system then
		return ctx.system
	end

	table.insert(parts, M.default_system_prompt())

	if ctx.agents then
		table.insert(parts, ctx.agents)
	end

	if ctx.claude then
		table.insert(parts, ctx.claude)
	end

	if ctx.append then
		table.insert(parts, ctx.append)
	end

	return table.concat(parts, "\n\n")
end

function M.default_system_prompt()
	return [[
You are a coding agent operating inside Neovim. You help users by reading files, executing commands, editing code, and writing new files.

Available tools:
- read: Read file contents
- write: Write or overwrite a file
- edit: Apply text replacements to a file
- bash: Execute shell commands
]]
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
