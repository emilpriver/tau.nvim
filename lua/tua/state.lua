local M = {}

M.sessions = {}
M.current_tab = nil
M.active_tab_id = nil

function M.init()
  M.sessions = {}
  M.current_tab = vim.api.nvim_get_current_tabpage()
end

function M.get_session(tab_id)
  tab_id = tab_id or vim.api.nvim_get_current_tabpage()
  return M.sessions[tab_id]
end

function M.set_session(tab_id, session)
  tab_id = tab_id or vim.api.nvim_get_current_tabpage()
  M.sessions[tab_id] = session
end

function M.clear_session(tab_id)
  tab_id = tab_id or vim.api.nvim_get_current_tabpage()
  M.sessions[tab_id] = nil
end

return M
