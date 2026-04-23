local M = {}

local IMAGE_EXTENSIONS = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  bmp = true,
  tiff = true,
}

local MIME_TYPES = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  bmp = "image/bmp",
  tiff = "image/tiff",
}

function M.is_image(path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  return IMAGE_EXTENSIONS[ext] == true
end

function M.get_mime_type(path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  return MIME_TYPES[ext] or "image/png"
end

function M.read_file_base64(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, "File not readable: " .. path
  end

  local result = vim.system({ "base64", "-i", path }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, "Failed to encode image: " .. (result.stderr or "unknown error")
  end

  return vim.trim(result.stdout), nil
end

function M.attach_file(path)
  if not M.is_image(path) then
    return nil, "Not an image file: " .. path
  end

  local base64, err = M.read_file_base64(path)
  if not base64 then
    return nil, err
  end

  return {
    path = path,
    mime_type = M.get_mime_type(path),
    base64 = base64,
  }
end

function M.format_for_provider(attachments, provider_name)
  if not attachments or #attachments == 0 then
    return nil
  end
  local plugin = require("tau.plugin").get_provider(provider_name)
  if not plugin or not plugin.format_attachments then
    return nil
  end
  return plugin.format_attachments(attachments)
end

function M.build_user_message(text, attachments, provider_name)
  local plugin = require("tau.plugin").get_provider(provider_name)
  if not plugin or not plugin.build_user_message then
    if text and text ~= "" then
      return { role = "user", content = text }
    end
    return nil
  end
  return plugin.build_user_message(text, attachments)
end

return M
