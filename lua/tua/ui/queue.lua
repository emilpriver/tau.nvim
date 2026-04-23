local M = {}

M.queue = {}
M.is_busy = false

function M.push(text, type)
  type = type or "steer"
  table.insert(M.queue, {
    text = text,
    type = type,
    timestamp = vim.fn.localtime(),
  })
end

function M.pop()
  if #M.queue == 0 then
    return nil
  end
  return table.remove(M.queue, 1)
end

function M.peek()
  return M.queue[1]
end

function M.clear()
  M.queue = {}
end

function M.size()
  return #M.queue
end

function M.set_busy(busy)
  M.is_busy = is_busy
end

function M.is_busy()
  return M.is_busy
end

function M.flush_to_messages(messages)
  local flushed = {}
  while #M.queue > 0 do
    local msg = M.pop()
    if msg then
      table.insert(messages, {
        role = "user",
        content = msg.text,
        _queued = true,
        _queue_type = msg.type,
      })
      table.insert(flushed, msg)
    end
  end
  return flushed
end

return M
