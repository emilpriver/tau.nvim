local M = {}

local config = require("tua.config")

M.setup = config.setup

function M.show(opts)
  require("tua.ui").open(opts)
end

function M.toggle(opts)
  require("tua.ui").toggle(opts)
end

function M.stop()
  require("tua.rpc").stop()
end

function M.abort()
  require("tua.rpc").abort()
end

function M.new_session()
  require("tua.session").new_session(vim.fn.getcwd())
end

function M.continue_session()
  require("tua.session").load_most_recent(vim.fn.getcwd())
end

function M.resume_session()
  require("tua.session").list_sessions(vim.fn.getcwd())
end

function M.compact(instructions)
  require("tua.rpc").send("compact", { instructions = instructions })
end

function M.select_model()
  require("tua.models").select()
end

function M.cycle_model()
  require("tua.models").cycle()
end

function M.focus_history()
  error("not implemented — Phase 4")
end

function M.focus_prompt()
  error("not implemented — Phase 4")
end

function M.focus_attachments()
  error("not implemented — Phase 4")
end

function M.scroll_history(direction, lines)
  error("not implemented — Phase 4")
end

function M.toggle_thinking()
  error("not implemented — Phase 4")
end

function M.cycle_thinking_level()
  require("tua.models").cycle_thinking_level()
end

function M.select_thinking_level()
  require("tua.models").select_thinking_level()
end

function M.get_thinking_level()
  return require("tua.models").get_thinking_level()
end

function M.get_provider()
  return require("tua.api").get_provider_info()
end

function M.stream(messages, opts)
  local provider = require("tua.config").get().provider.name
  return require("tua.api").stream(provider, messages, opts)
end

function M.call(messages, opts)
  local provider = require("tua.config").get().provider.name
  return require("tua.api").call(provider, messages, opts)
end

function M.refresh_models()
  require("tua.models").refresh()
end

function M.login(provider_name)
  local auth = require("tua.auth")
  local info = auth.PROVIDER_HELP[provider_name]

  if not info then
    vim.notify("Unknown provider: " .. provider_name .. ". Supported: " .. table.concat(vim.tbl_keys(auth.PROVIDER_HELP), ", "), vim.log.levels.ERROR)
    return
  end

  vim.ui.input({
    prompt = info.prompt .. "\nGenerate a key at: " .. info.key_url .. "\n\nAPI key: ",
  }, function(key)
    if not key or key == "" then
      return
    end
    if auth.set_key(provider_name, key) then
      vim.notify(provider_name .. " credentials saved to " .. auth.get_auth_path(), vim.log.levels.INFO)
    else
      vim.notify("Failed to save credentials", vim.log.levels.ERROR)
    end
  end)
end

function M.logout(provider_name)
  local auth = require("tua.auth")

  if provider_name then
    if auth.remove_key(provider_name) then
      vim.notify(provider_name .. " credentials removed", vim.log.levels.INFO)
    else
      vim.notify("No credentials found for " .. provider_name, vim.log.levels.WARN)
    end
    return
  end

  local providers = auth.list_providers()
  if #providers == 0 then
    vim.notify("No stored credentials", vim.log.levels.INFO)
    return
  end

  vim.ui.select(providers, {
    prompt = "Remove credentials for:",
  }, function(choice)
    if choice then
      auth.remove_key(choice)
      vim.notify(choice .. " credentials removed", vim.log.levels.INFO)
    end
  end)
end

function M.show_agents()
  local agents = require("tua.agents")
  local files = agents.list_loaded_files()

  if #files == 0 then
    vim.notify("No agent files loaded. Create ~/.agents/AGENTS.md or .agents/AGENTS.md", vim.log.levels.INFO)
    return
  end

  local lines = { "Loaded agent files:", "" }
  for _, f in ipairs(files) do
    local scope = f.scope == "global" and "[global]" or "[project]"
    table.insert(lines, string.format("  %s %s — %s", scope, f.name, f.path))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end
  local auth = require("tua.auth")
  local providers = auth.list_providers()
  if #providers == 0 then
    vim.notify("No stored credentials", vim.log.levels.INFO)
    return
  end
  vim.notify("Stored providers: " .. table.concat(providers, ", "), vim.log.levels.INFO)
end

function M.send_mention(args, opts)
  error("not implemented — Phase 5")
end

function M.attach_image(path)
  error("not implemented — Phase 4")
end

function M.paste_image()
  error("not implemented — Phase 4")
end

function M.invoke(command)
  error("not implemented — Phase 9")
end

function M.attention()
  error("not implemented — Phase 8")
end

function M.attention_count(tab_id)
  return 0
end

function M.attention_total()
  return 0
end

function M.has_attention(tab_id)
  return false
end

function M.changed_files()
  return require("tua.tools").get_changed_files()
end

function M.run_turn(messages, opts)
  local provider = require("tua.config").get().provider.name
  return require("tua.dispatcher").run_turn(provider, messages, opts)
end

function M.run_turn_streaming(messages, opts)
  local provider = require("tua.config").get().provider.name
  return require("tua.dispatcher").run_turn_streaming(provider, messages, opts)
end

function M.get_tool_list()
  return require("tua.tools").get_tool_list()
end

return M
