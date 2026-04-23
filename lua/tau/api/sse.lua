local M = {}

local function split_lines(raw)
	local lines = vim.split(raw, "\n")
	for i, line in ipairs(lines) do
		if line:sub(-1) == "\r" then
			lines[i] = line:sub(1, -2)
		end
	end
	return lines
end

function M.parse(raw)
	local events = {}
	local lines = split_lines(raw)
	local event = nil
	local data = nil

	for _, line in ipairs(lines) do
		if line == "" then
			if data then
				table.insert(events, { event = event, data = data })
				event = nil
				data = nil
			end
		elseif line:sub(1, 7) == "event: " then
			event = line:sub(8)
		elseif line:sub(1, 6) == "data: " then
			local chunk = line:sub(7)
			if data then
				data = data .. chunk
			else
				data = chunk
			end
		elseif line:sub(1, 1) == ":" then
			-- comment line, skip
		end
	end

	return events
end

function M.remaining(raw)
	local lines = split_lines(raw)
	local last_blank = nil

	for i = #lines, 1, -1 do
		if lines[i] == "" then
			last_blank = i
			break
		end
	end

	if last_blank and last_blank < #lines then
		local remainder = table.concat(lines, "\n", last_blank + 1)
		return remainder
	end

	local last_complete_event = nil
	local i = 1
	while i <= #lines do
		if lines[i] == "" then
			last_complete_event = i
		end
		i = i + 1
	end

	if last_complete_event then
		return table.concat(lines, "\n", last_complete_event + 1)
	end

	local last_data_line = nil
	for i = #lines, 1, -1 do
		if lines[i]:sub(1, 6) == "data: " or lines[i]:sub(1, 7) == "event: " then
			last_data_line = i
			break
		end
	end

	if last_data_line and last_data_line < #lines then
		return table.concat(lines, "\n", last_data_line)
	end

	return raw
end

return M
