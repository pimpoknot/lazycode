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

-- Places where a click does something show a hand pointer, like links in VS Code.
-- Lists where every row with text is clickable: Explorer, Extensions.
local LISTS = { snacks_picker_list = true }
-- Text fields that are not normal files.
local FIELDS = { snacks_picker_input = true, snacks_input = true, ["grug-far"] = true }
M.shape = "default"

--- The topmost window at a zero-based screen cell.
local function win_at(row, col)
  local found, top = nil, -1
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local pos, cfg = vim.fn.win_screenpos(win), vim.api.nvim_win_get_config(win)
    local r, c = pos[1] - 1, pos[2] - 1
    local z = cfg.relative == "" and 0 or (cfg.zindex or 50)
    local inside = row >= r and row < r + vim.api.nvim_win_get_height(win)
    if inside and col >= c and col < c + vim.api.nvim_win_get_width(win) and z > top then
      found, top = win, z
    end
  end
  return found
end

--- Zero-based column of the last visible character between two screen columns, or -1.
local function text_end(row, from, to)
  for col = to - 1, from, -1 do
    local ch = vim.fn.screenstring(row + 1, col + 1)
    if ch ~= "" and ch ~= " " then
      return col
    end
  end
  return -1
end

local function fixed(win)
  return win and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "lazycode_bar"
end

--- pointer over things a click opens, text over editable text, resize over panel borders.
function M.shape_at(row, col)
  local win = win_at(row, col)
  if not win then
    if row == 0 then -- tab bar
      return text_end(0, 0, vim.o.columns) >= col and "pointer" or "default"
    end
    local left, right = win_at(row, col - 1), win_at(row, col + 1)
    if left and right and left ~= right and not fixed(left) and not fixed(right) then
      return "ew-resize"
    end
    local up, down = win_at(row - 1, col), win_at(row + 1, col)
    return (up and down and up ~= down) and "ns-resize" or "default"
  end
  local buf, top = vim.api.nvim_win_get_buf(win), vim.fn.win_screenpos(win)
  local line = vim.fn.line("w0", win) + row - (top[1] - 1)
  local ft, bt = vim.bo[buf].filetype, vim.bo[buf].buftype
  if ft == "lazycode_bar" then
    return require("lazycode.sidebar").item_at(line) and "pointer" or "default"
  elseif ft == "lazycode_welcome" or ft == "lazycode_side" then
    return require("lazycode.welcome").clickable(buf, line) and "pointer" or "default"
  elseif LISTS[ft] then
    local left = top[2] - 1
    return text_end(row, left, left + vim.api.nvim_win_get_width(win)) >= col and "pointer" or "default"
  elseif FIELDS[ft] or bt == "" or bt == "terminal" then
    return "text"
  end
  return "default"
end

--- Called by the window on every cell the mouse enters. It arrives as a notification, so an
--- open :popup menu delays it instead of blocking the window, and mouse moves never become keys.
function M.hover(row, col)
  local shape = M.shape_at(row, col)
  if shape == M.shape then
    return
  end
  M.shape = shape
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local info = ui.chan and vim.api.nvim_get_chan_info(ui.chan)
    if info and info.client and info.client.name == "lazycode-app" then
      vim.rpcnotify(ui.chan, "lazycode_cursor", shape)
    end
  end
end

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
