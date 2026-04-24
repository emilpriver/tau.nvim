local M = {}

function M.winbar_text(session)
	local cfg = require("tau.config").get()
	local provider_name = session and session.provider or cfg.provider.name or "default"
	local model = session and session.model or cfg.provider.model
	if not model then
		model = require("tau.models").get_active()
	end
	if not model then
		local plugin = require("tau.plugin").get_provider(provider_name)
		if plugin then
			model = plugin.default_model
		end
	end
	if not model then
		local fallback = require("tau.plugin").get_fallback_models(provider_name)
		if fallback and #fallback > 0 then
			model = fallback[1]
		end
	end
	local title = "…"
	if session then
		if session.name and session.name ~= "" then
			title = session.name
		else
			local id = session.id or ""
			if #id > 16 then
				title = id:sub(1, 16) .. "…"
			elseif id ~= "" then
				title = id
			end
		end
	end
	return string.format(" %s · %s | %s ", title, provider_name, model or "default")
end

return M
