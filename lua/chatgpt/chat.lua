local Config = require("chatgpt.config")
local Utils = require("chatgpt.utils")
local Spinner = require("chatgpt.spinner")
local Session = require("chatgpt.flows.chat.session")

local Chat = {}
Chat.__index = Chat

QUESTION, ANSWER = 1, 2

function Chat:new(bufnr, winid, on_loading)
  self = setmetatable({}, Chat)

  self.session = Session.latest()

  self.bufnr = bufnr
  self.winid = winid
  self.on_loading = on_loading
  self.selectedIndex = 0
  self.messages = {}
  self.spinner = Spinner:new(function(state)
    vim.schedule(function()
      self:set_lines(-2, -1, false, { "     " .. state .. " " .. Config.options.loading_text })
      on_loading(state)
    end)
  end)
  return self
end

function Chat:on_show(bufnr, winid)
  self.bufnr = bufnr
  self.winid = winid
end

function Chat:close()
  self.spinner:stop()
end

function Chat:welcome()
  if #self.session.conversation > 0 then
    for _, item in ipairs(self.session.conversation) do
      self:_add(item.type, item.text, item.usage)
    end
  else
    local lines = Utils.split_string_by_line(Config.options.welcome_message)
    self:set_lines(0, 0, false, lines)
    for line_num = 0, #lines do
      self:add_highlight("ChatGPTWelcome", line_num, 0, -1)
    end
  end
end

function Chat:new_session()
  vim.api.nvim_buf_clear_namespace(self.bufnr, Config.namespace_id, 0, -1)

  self.session = Session:new()
  self.session:save()

  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:welcome()
end

function Chat:set_session(session)
  vim.api.nvim_buf_clear_namespace(self.bufnr, Config.namespace_id, 0, -1)

  self.session = session

  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:welcome()
end

function Chat:isBusy()
  return self.spinner:is_running()
end

function Chat:add(type, text, usage)
  self.session:add_item({
    type = type,
    text = text,
    usage = usage,
  })
  self:_add(type, text, usage)
end

function Chat:_add(type, text, usage)
  if not self:is_buf_exists() then
    return
  end
  local width = self:get_width() - 10 -- add some space
  local max_width = Config.options.max_line_length
  if width > max_width then
    max_width = width
  end
  text = Utils.wrapText(text, width)

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  local lines = {}
  local nr_of_lines = 0
  for line in string.gmatch(text, "[^\n]+") do
    nr_of_lines = nr_of_lines + 1
    table.insert(lines, line)
  end

  table.insert(self.messages, {
    usage = usage or {},
    type = type,
    text = text,
    lines = lines,
    nr_of_lines = nr_of_lines,
    start_line = start_line,
    end_line = start_line + nr_of_lines - 1,
  })
  self:next()
  self:renderLastMessage()
end

function Chat:addQuestion(text)
  self:add(QUESTION, text)
end

function Chat:addAnswer(text, usage)
  self:add(ANSWER, text, usage)
end

function Chat:next()
  local count = self:count()
  if self.selectedIndex < count then
    self.selectedIndex = self.selectedIndex + 1
  else
    self.selectedIndex = 1
  end
end

function Chat:getSelected()
  return self.messages[self.selectedIndex]
end

function Chat:get_last_answer()
  for i = #self.messages, 1, -1 do
    if self.messages[i].type == ANSWER then
      return self.messages[i]
    end
  end
end

function Chat:renderLastMessage()
  self:stopSpinner()

  local signs = { Config.options.question_sign, Config.options.answer_sign }
  local msg = self:getSelected()

  local lines = {}
  local i = 0
  for w in string.gmatch(msg.text, "[^\r\n]+") do
    local prefix = "   │ "
    if i == 0 then
      prefix = " " .. signs[msg.type] .. " │ "
    end
    table.insert(lines, prefix .. w)
    i = i + 1
  end
  table.insert(lines, "")
  if msg.type == ANSWER then
    table.insert(lines, "")
  end

  local startIdx = self.selectedIndex == 1 and 0 or -2
  self:set_lines(startIdx, -1, false, lines)

  if msg.type == QUESTION then
    for index, _ in ipairs(lines) do
      self:add_highlight("ChatGPTQuestion", msg.start_line + index - 1, 0, -1)
    end
  end

  if self.selectedIndex > 2 then
    self:set_cursor({ msg.end_line - 1, 0 })
  end
end

function Chat:showProgess()
  self.spinner:start()
end

function Chat:stopSpinner()
  self.spinner:stop()
  self.on_loading()
end

function Chat:toString()
  local str = ""
  for _, msg in pairs(self.messages) do
    str = str .. msg.text .. "\n"
  end
  return str
end

function Chat:count()
  local count = 0
  for _ in pairs(self.messages) do
    count = count + 1
  end
  return count
end

function Chat:is_buf_exists()
  return vim.fn.bufexists(self.bufnr) == 1
end

function Chat:set_lines(start_idx, end_idx, strict_indexing, lines)
  if self:is_buf_exists() then
    vim.api.nvim_buf_set_option(self.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(self.bufnr, "modifiable", false)
  end
end

function Chat:add_highlight(hl_group, line, col_start, col_end)
  if self:is_buf_exists() then
    vim.api.nvim_buf_add_highlight(self.bufnr, -1, hl_group, line, col_start, col_end)
  end
end

function Chat:set_cursor(pos)
  if self:is_buf_exists() then
    vim.api.nvim_win_set_cursor(self.winid, pos)
  end
end

function Chat:get_width()
  if self:is_buf_exists() then
    return vim.api.nvim_win_get_width(self.winid)
  end
end

return Chat
