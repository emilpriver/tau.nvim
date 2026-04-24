local M = {}
local mentions = require("tau.mentions")

function M.completefunc(findstart, base)
	return mentions.completefunc(findstart, base)
end

function M.expand_mentions(text)
	return mentions.expand(text)
end

function M.validate_mentions(text)
	return mentions.validate(text)
end

function M.send_mention_for_buffer()
	return mentions.insert_from_editor({})
end

return M
