-- Context menu and mouse actions.
local M = {}

function M.goto_definition()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return
  end
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, math.max(pos.column - 1, 0) })
  vim.lsp.buf.definition()
end

local function keys(value)
  vim.api.nvim_feedkeys(vim.keycode(value), "m", false)
end

M.actions = {
  cut = function()
    keys("<C-x>")
  end,
  copy = function()
    keys("<C-c>")
  end,
  paste = function()
    keys("<C-v>")
  end,
  all = function()
    keys("<C-a>")
  end,
  definition = function()
    vim.lsp.buf.definition()
  end,
  references = function()
    Snacks.picker.lsp_references()
  end,
  rename = function()
    vim.lsp.buf.rename()
  end,
  action = function()
    vim.lsp.buf.code_action()
  end,
  format = function()
    LazyVim.format({ force = true })
  end,
  comment = function()
    keys("<C-/>")
  end,
}

local items = {
  { "Cut", "cut", "Ctrl+X" },
  { "Copy", "copy", "Ctrl+C" },
  { "Paste", "paste", "Ctrl+V" },
  { "Select\\ All", "all", "Ctrl+A" },
  { "-sep1-" },
  { "Go\\ to\\ Definition", "definition", "F12" },
  { "References", "references", "Shift+F12" },
  { "Rename", "rename", "F2" },
  { "Code\\ Actions", "action", "Ctrl+." },
  { "-sep2-" },
  { "Format", "format", "Shift+Alt+F" },
  { "Comment", "comment", "Ctrl+/" },
}

function M.setup()
  pcall(vim.api.nvim_del_augroup_by_name, "nvim.popupmenu")
  pcall(vim.cmd, "silent! aunmenu PopUp")
  for i, item in ipairs(items) do
    if item[2] then
      local label = ("PopUp.%s<Tab>%s"):format(item[1], item[3]:gsub(" ", "\\ "))
      local rhs = ("<Cmd>lua require('lazycode.mouse').actions.%s()<CR>"):format(item[2])
      for _, cmd in ipairs({ "nnoremenu", "inoremenu", "xnoremenu", "snoremenu" }) do
        vim.cmd(("%s <silent> %d %s %s"):format(cmd, i * 10, label, rhs))
      end
    else
      vim.cmd(("anoremenu %d PopUp.%s <Nop>"):format(i * 10, item[1]))
    end
  end
end

return M
