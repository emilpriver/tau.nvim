local M = {}

M.frames = {
  dots = { ".", "..", "...", "....", ".....", "....", "...", ".." },
  line = { "-", "\\", "|", "/" },
  pulse = { "(*)", "(-)", "(+)", "(x)" },
  moon = { "(", "((", "(((", "((((", "(((((", "((((", "(((", "((" },
  arrow = { "<", "^", ">", "v" },
  bounce = { "(o    )", "( o   )", "(  o  )", "(   o )", "(  o  )", "( o   )" },
  robot = { "[R]", "[o]", "[b]", "[o]" },
}

function M.get(name)
  return M.frames[name] or M.frames.dots
end

function M.start(opts)
  opts = opts or {}
  local name = opts.spinner or "dots"
  local interval = opts.interval or 80
  local frames = M.get(name)
  local frame_idx = 1

  local timer = vim.uv.new_timer()
  local callback = opts.on_update

  timer:start(interval, interval, vim.schedule_wrap(function()
    if not callback then
      timer:stop()
      timer:close()
      return
    end
    callback(frames[frame_idx])
    frame_idx = frame_idx + 1
    if frame_idx > #frames then
      frame_idx = 1
    end
  end))

  return {
    timer = timer,
    stop = function()
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  }
end

return M
