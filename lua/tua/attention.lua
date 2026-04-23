local M = {}

local queue = {}

function M.push(kind, payload)
  error("not implemented: attention.push — Phase 8")
end

function M.pop()
  error("not implemented: attention.pop — Phase 8")
end

function M.count()
  return 0
end

function M.has_pending()
  return false
end

return M
