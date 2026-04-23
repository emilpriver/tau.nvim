local M = {}

local THINKING_LEVELS = { "off", "minimal", "low", "medium", "high", "xhigh" }
local current_thinking_level = "off"
local current_model = nil
local available_models = {}

local function get_provider()
  return require("tau.config").get().provider.name
end

local function get_config()
  return require("tau.config").get()
end

local function get_fallback_models()
  return require("tau.plugin").get_fallback_models(get_provider())
end

local function resolve_model_list()
  local config = get_config()
  if not config.models then
    return available_models
  end

  local resolved = {}
  for _, entry in ipairs(config.models) do
    local match_str
    if type(entry) == "string" then
      match_str = entry
    else
      match_str = entry.match
    end

    local matches = {}
    for _, model_id in ipairs(available_models) do
      if match_str:lower() == model_id:lower() then
        table.insert(matches, model_id)
      elseif match_str:lower() == "latest" then
        table.insert(matches, model_id)
      else
        local lower_id = model_id:lower()
        local lower_match = match_str:lower()
        if lower_id:find(lower_match, 1, true) then
          table.insert(matches, model_id)
        end
      end
    end

    if type(entry) == "table" and entry.exact then
      for _, model_id in ipairs(available_models) do
        if model_id == match_str then
          table.insert(resolved, model_id)
          break
        end
      end
    elseif type(entry) == "table" and entry.latest then
      if #matches > 0 then
        table.sort(matches)
        table.insert(resolved, matches[#matches])
      end
    else
      vim.list_extend(resolved, matches)
    end
  end

  return resolved
end

function M.refresh()
  local provider = get_provider()
  local ok, models = pcall(require("tau.api").list_models, provider)
  if ok and models and #models > 0 then
    available_models = models
    vim.notify("Loaded " .. #models .. " models from " .. provider, vim.log.levels.INFO)
  else
    local fallback = get_fallback_models()
    available_models = fallback
    if not ok then
      vim.notify(tostring(models), vim.log.levels.WARN)
    end
    vim.notify("Using " .. #fallback .. " fallback models for " .. provider, vim.log.levels.INFO)
  end

  if not current_model or #available_models == 0 then
    current_model = available_models[1]
  end
end

function M.cycle()
  local list = resolve_model_list()
  if #list == 0 then
    list = available_models
  end
  if #list == 0 then
    M.refresh()
    list = available_models
  end
  if #list == 0 then
    vim.notify("No models available", vim.log.levels.WARN)
    return
  end

  local idx = 1
  for i, model_id in ipairs(list) do
    if model_id == current_model then
      idx = i + 1
      break
    end
  end
  if idx > #list then
    idx = 1
  end

  M.set(list[idx])
end

function M.select()
  if #available_models == 0 then
    M.refresh()
  end

  local list = resolve_model_list()
  if #list == 0 then
    list = available_models
  end
  if #list == 0 then
    vim.notify("No models available", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, model_id in ipairs(list) do
    local marker = model_id == current_model and "> " or "  "
    table.insert(items, marker .. model_id)
  end

  vim.ui.select(items, {
    prompt = "Select model",
  }, function(choice, idx)
    if choice then
      local model_id = list[idx]
      M.set(model_id)
    end
  end)
end

function M.select_all()
  if #available_models == 0 then
    M.refresh()
  end
  if #available_models == 0 then
    vim.notify("No models available", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, model_id in ipairs(available_models) do
    local marker = model_id == current_model and "> " or "  "
    table.insert(items, marker .. model_id)
  end

  vim.ui.select(items, {
    prompt = "Select model (all)",
  }, function(choice, idx)
    if choice then
      M.set(available_models[idx])
    end
  end)
end

function M.get_active()
  return current_model
end

function M.set(model_id)
  local provider = get_provider()
  require("tau.config").get().provider.model = model_id
  current_model = model_id
  vim.notify("Model: " .. model_id, vim.log.levels.INFO)
end

function M.cycle_thinking_level()
  local idx = 1
  for i, level in ipairs(THINKING_LEVELS) do
    if level == current_thinking_level then
      idx = i + 1
      break
    end
  end
  if idx > #THINKING_LEVELS then
    idx = 1
  end
  current_thinking_level = THINKING_LEVELS[idx]
  vim.notify("Thinking: " .. current_thinking_level, vim.log.levels.INFO)
end

function M.select_thinking_level()
  vim.ui.select(THINKING_LEVELS, {
    prompt = "Select thinking level",
    default = current_thinking_level,
  }, function(choice)
    if choice then
      current_thinking_level = choice
      vim.notify("Thinking: " .. current_thinking_level, vim.log.levels.INFO)
    end
  end)
end

function M.get_thinking_level()
  return current_thinking_level
end

function M.get_available_models()
  return available_models
end

return M
