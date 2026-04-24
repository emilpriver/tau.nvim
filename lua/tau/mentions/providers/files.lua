local M = {}

local MAX_PATH_COMPLETIONS = 500

local function normalize_base(base)
	base = base or ""
	base = vim.trim(base)
	base = base:gsub("^%./", "")
	base = base:gsub("^@", "")
	return base
end

local function rel_matches(rel, base)
	if base == "" then
		return true
	end
	if #base <= #rel and rel:sub(1, #base) == base then
		return true
	end
	if rel:find("/" .. base, 1, true) then
		return true
	end
	local tail = vim.fn.fnamemodify(rel, ":t")
	return #base <= #tail and tail:sub(1, #base) == base
end

local function gather_path_matches(base)
	local cwd = vim.fn.getcwd()
	base = normalize_base(base)
	local rel_dir = "."
	if base:find("/") then
		rel_dir = vim.fn.fnamemodify(base, ":h")
		if rel_dir == "." or rel_dir == "" then
			rel_dir = "."
		end
	end
	local globpat = (rel_dir == ".") and "**/*" or (rel_dir .. "/**/*")
	local paths = vim.fn.globpath(cwd, globpat, false, true)
	if type(paths) ~= "table" then
		paths = {}
	end

	local files = {}
	local dirs = {}
	for _, f in ipairs(paths) do
		if vim.fn.isdirectory(f) == 1 then
			local rel = vim.fn.fnamemodify(f, ":.")
			if rel ~= "." and rel ~= ".." and rel_matches(rel, base) then
				table.insert(dirs, rel .. "/")
			end
		elseif vim.fn.filereadable(f) == 1 then
			local rel = vim.fn.fnamemodify(f, ":.")
			if rel_matches(rel, base) then
				table.insert(files, rel)
			end
		end
	end

	table.sort(files)
	table.sort(dirs)
	local out_files = {}
	local out_dirs = {}
	for _, r in ipairs(files) do
		if #out_files + #out_dirs >= MAX_PATH_COMPLETIONS then
			break
		end
		table.insert(out_files, r)
	end
	for _, r in ipairs(dirs) do
		if #out_files + #out_dirs >= MAX_PATH_COMPLETIONS then
			break
		end
		table.insert(out_dirs, r)
	end
	return out_files, out_dirs
end

local function resolve_cwd(path, ctx)
	local cwd = (ctx and ctx.cwd) or vim.fn.getcwd()
	if vim.fn.has("win32") == 1 and path:match("^%a:/") then
		return path
	end
	if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then
		return vim.fn.fnamemodify(path, ":p")
	end
	return cwd .. "/" .. path
end

local function path_for_bracket(rel)
	if vim.fn.has("win32") == 1 and rel:match("^%a:/") then
		return rel
	end
	if rel:sub(1, 1) == "/" or rel:sub(1, 2) == "./" or rel:sub(1, 3) == "../" then
		return rel
	end
	return "./" .. rel
end

function M.expand(text, ctx)
	local cwd = (ctx and ctx.cwd) or vim.fn.getcwd()
	local result = text

	result = result:gsub("@([%w%_%-%./]+)/ ", function(path)
		return "[directory: " .. path .. "/] "
	end)

	result = result:gsub("@([%w%_%-%./]+)", function(path)
		local full_path = resolve_cwd(path, ctx)
		if vim.fn.filereadable(full_path) == 1 then
			local bufnr = vim.fn.bufnr(full_path)
			if bufnr ~= -1 then
				local line = vim.api.nvim_win_get_cursor(0)[1]
				return string.format("[file: %s, line: %d]", path, line)
			end
			return "[file: " .. path .. "]"
		elseif vim.fn.isdirectory(full_path) == 1 then
			return "[directory: " .. path .. "]"
		end
		return "@" .. path
	end)

	return result
end

function M.validate(text, ctx)
	local cwd = (ctx and ctx.cwd) or vim.fn.getcwd()
	local invalid = {}
	for mention in text:gmatch("%[file: ([^%]]+)%]") do
		local path = mention:gsub(", line: %d+", ""):gsub(", lines: %d+%-%d+", "")
		local full = resolve_cwd(path, { cwd = cwd })
		if vim.fn.filereadable(full) ~= 1 and vim.fn.isdirectory(full) ~= 1 then
			table.insert(invalid, path)
		end
	end
	for mention in text:gmatch("%[directory: ([^%]]+)%]") do
		local path = vim.trim(mention):gsub("/$", "")
		local full = resolve_cwd(path, { cwd = cwd })
		if vim.fn.isdirectory(full) ~= 1 then
			table.insert(invalid, path)
		end
	end
	return invalid
end

function M.insert_from_editor(opts, ctx)
	opts = opts or {}
	local buf = opts.bufnr or vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		vim.notify("No file for buffer", vim.log.levels.WARN)
		return nil
	end

	local rel = vim.fn.fnamemodify(name, ":.")
	local line1 = opts.line1
	local line2 = opts.line2

	if line1 == nil or line2 == nil then
		local mode = vim.fn.mode(1)
		local vis = mode:sub(1, 1)
		if vis == "v" or vis == "V" or vis == "\022" then
			line1 = vim.fn.line("v")
			line2 = vim.fn.line(".")
			if line1 > line2 then
				line1, line2 = line2, line1
			end
		else
			line1 = vim.fn.line(".")
			line2 = line1
		end
	end

	if line1 == line2 then
		return "[file: " .. rel .. ", line: " .. line1 .. "]"
	end
	return "[file: " .. rel .. ", lines: " .. line1 .. "-" .. line2 .. "]"
end

function M.complete_at(findstart, base, ctx)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local col0 = vim.api.nvim_win_get_cursor(0)[2]
		local col1 = col0 + 1

		for i = col1, 1, -1 do
			local ch = line:sub(i, i)
			if ch == "@" then
				return i - 1
			end
			if ch == " " or ch == "\t" then
				return -2
			end
		end
		return -2
	end

	local results = {}
	local files, dirs = gather_path_matches(base)
	for _, f in ipairs(files) do
		local p = path_for_bracket(f)
		table.insert(results, {
			word = "[file: " .. p .. "]",
			abbr = f,
			menu = "[file]",
		})
	end
	for _, d in ipairs(dirs) do
		local dpath = d:gsub("/$", "")
		local p = path_for_bracket(dpath)
		table.insert(results, {
			word = "[directory: " .. p .. "]",
			abbr = d,
			menu = "[dir]",
		})
	end

	return results
end

function M.create()
	return {
		name = "files",
		priority = 0,
		expand = M.expand,
		validate = M.validate,
		insert_from_editor = M.insert_from_editor,
		complete_at = M.complete_at,
	}
end

return M
