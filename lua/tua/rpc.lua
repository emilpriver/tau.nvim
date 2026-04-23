local M = {}

function M.start(cwd)
  error("not implemented: rpc.start — Phase 1")
end

function M.stop()
  error("not implemented: rpc.stop — Phase 1")
end

function M.send(command, payload)
  error("not implemented: rpc.send — Phase 1")
end

function M.is_running()
  return false
end

return M
