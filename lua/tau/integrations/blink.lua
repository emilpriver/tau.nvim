local ok, complete_func = pcall(require, "blink.cmp.sources.complete_func")
if not ok then
	return {
		new = function()
			error("tau.integrations.blink requires blink.cmp")
		end,
	}
end

local M = {}

function M.new(opts, config)
	config = vim.tbl_deep_extend("force", {}, config or {})
	config.opts = vim.tbl_deep_extend("force", {
		complete_func = function()
			if vim.bo.filetype ~= "tau-prompt" then
				return nil
			end
			return "v:lua.__tau_completefunc"
		end,
	}, config.opts or {}, opts or {})
	return complete_func.new(nil, config)
end

return M
