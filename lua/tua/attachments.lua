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

function M.to_anthropic_content(attachment)
  return {
    type = "image",
    source = {
      type = "base64",
      media_type = attachment.mime_type,
      data = attachment.base64,
    },
  }
end

function M.to_openai_content(attachment)
  local url = string.format("data:%s;base64,%s", attachment.mime_type, attachment.base64)
  return {
    type = "input_image",
    image_url = url,
  }
end

function M.to_openai_chat_content(attachment)
  local url = string.format("data:%s;base64,%s", attachment.mime_type, attachment.base64)
  return {
    type = "image_url",
    image_url = { url = url },
  }
end

function M.format_for_provider(attachments, provider_name)
  if not attachments or #attachments == 0 then
    return nil
  end

  local result = {}
  for _, att in ipairs(attachments) do
    if provider_name == "anthropic" then
      table.insert(result, M.to_anthropic_content(att))
    elseif provider_name == "openai" then
      table.insert(result, M.to_openai_content(att))
    else
      table.insert(result, M.to_openai_chat_content(att))
    end
  end
  return result
end

function M.build_user_message(text, attachments, provider_name)
  local content = {}

  if text and text ~= "" then
    if provider_name == "anthropic" then
      table.insert(content, { type = "text", text = text })
    elseif provider_name == "openai" then
      table.insert(content, { type = "input_text", text = text })
    else
      table.insert(content, { type = "text", text = text })
    end
  end

  local image_content = M.format_for_provider(attachments, provider_name)
  if image_content then
    vim.list_extend(content, image_content)
  end

  if #content == 0 then
    return nil
  end

  if #content == 1 and provider_name ~= "anthropic" and provider_name ~= "openai" then
    return { role = "user", content = text }
  end

  return { role = "user", content = content }
end

return M
