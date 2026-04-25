local M = {}

M.is_busy = false

local function context_session()
	return require("tau.state").get_context_session()
end

local function ensure_queue(session)
	if not session then
		return nil
	end
	if type(session.queue) ~= "table" then
		session.queue = {}
	end
	if session._queue_next_id == nil then
		local max_n = 0
		for _, item in ipairs(session.queue) do
			local n = tonumber(tostring(item.id or ""):match("^q_(%d+)$"))
			if n and n > max_n then
				max_n = n
			end
		end
		session._queue_next_id = math.max(max_n + 1, 1)
	end
	return session
end

function M.push(text, type, opts)
	opts = opts or {}
	local s = ensure_queue(context_session())
	if not s then
		return nil
	end
	type = type or "steer"
	local item = {
		id = opts.id or ("q_" .. s._queue_next_id),
		text = text,
		type = type,
		timestamp = vim.fn.localtime(),
		source = opts.source or "prompt",
		attachments = opts.attachments or nil,
	}
	s._queue_next_id = s._queue_next_id + 1
	table.insert(s.queue, item)
	return item
end

function M.pop()
	local s = ensure_queue(context_session())
	if not s or #s.queue == 0 then
		return nil
	end
	return table.remove(s.queue, 1)
end

function M.peek()
	local s = ensure_queue(context_session())
	if not s or #s.queue == 0 then
		return nil
	end
	return s.queue[1]
end

function M.get_all()
	local s = ensure_queue(context_session())
	if not s then
		return {}
	end
	return vim.deepcopy(s.queue)
end

function M.get_info()
	local s = ensure_queue(context_session())
	if not s then
		return { size = 0, busy = M.is_busy, types = {} }
	end
	local types = {}
	for _, item in ipairs(s.queue) do
		types[item.type] = (types[item.type] or 0) + 1
	end
	return {
		size = #s.queue,
		busy = M.is_busy,
		types = types,
	}
end

function M.remove_at(index)
	local s = ensure_queue(context_session())
	if not s or index < 1 or index > #s.queue then
		return nil
	end
	return table.remove(s.queue, index)
end

function M.update_at(index, new_text)
	local s = ensure_queue(context_session())
	if not s or index < 1 or index > #s.queue then
		return false
	end
	s.queue[index].text = new_text
	s.queue[index].timestamp = vim.fn.localtime()
	return true
end

function M.move_up(index)
	local s = ensure_queue(context_session())
	if not s or index < 2 or index > #s.queue then
		return false
	end
	s.queue[index], s.queue[index - 1] = s.queue[index - 1], s.queue[index]
	return true
end

function M.move_down(index)
	local s = ensure_queue(context_session())
	if not s or index < 1 or index >= #s.queue then
		return false
	end
	s.queue[index], s.queue[index + 1] = s.queue[index + 1], s.queue[index]
	return true
end

function M.clear()
	local s = ensure_queue(context_session())
	if not s then
		return
	end
	s.queue = {}
	s._queue_next_id = 1
end

function M.size()
	local s = ensure_queue(context_session())
	if not s then
		return 0
	end
	return #s.queue
end

function M.set_busy(busy)
	M.is_busy = busy
end

function M.get_busy()
	return M.is_busy
end

function M.flush_to_messages(messages, opts)
	if type(opts) == "boolean" then
		opts = { clear_queue = opts }
	else
		opts = opts or {}
	end
	local clear_queue = opts.clear_queue ~= false
	local s = ensure_queue(context_session())
	if not s then
		return {}
	end
	local flushed = {}
	while #s.queue > 0 do
		local msg = table.remove(s.queue, 1)
		if msg then
			table.insert(messages, {
				role = "user",
				content = msg.text,
				_queued = true,
				_queue_type = msg.type,
				timestamp = msg.timestamp,
			})
			table.insert(flushed, msg)
		end
	end
	if not clear_queue then
		for _, item in ipairs(flushed) do
			table.insert(s.queue, item)
		end
	end
	return flushed
end

function M.render_status()
	local info = M.get_info()
	if info.size == 0 then
		return ""
	end
	return string.format("%d queued", info.size)
end

function M.sync_to_session(session)
	ensure_queue(session)
end

function M.update(index, new_text)
	return M.update_at(index, new_text)
end

function M.move(from, to)
	if to == from + 1 then
		return M.move_down(from)
	elseif to == from - 1 then
		return M.move_up(from)
	end
	return false
end

return M
