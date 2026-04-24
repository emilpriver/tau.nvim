local M = {}

function M.stop()
	require("tau.dispatcher").stop()
end

function M.abort()
	require("tau.dispatcher").stop()
end

return M
