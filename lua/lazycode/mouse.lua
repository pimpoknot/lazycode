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
    vim.lsp.buf.definition({ reuse_win = true })
  end,
  hover = function()
    local diags = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
    if #diags > 0 then
      vim.diagnostic.open_float({ scope = "line", focus = false })
    else
      vim.lsp.buf.hover()
    end
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
  claude = function()
    require("lazycode").send_to_claude()
  end,
}

local items = {
  { "Cut", "cut", "Ctrl+X" },
  { "Copy", "copy", "Ctrl+C" },
  { "Paste", "paste", "Ctrl+V" },
  { "Select\\ All", "all", "Ctrl+A" },
  { "-sep1-" },
  { "Go\\ to\\ Definition", "definition", "F12" },
  { "Show\\ Problem\\ /\\ Hover", "hover", "Ctrl+K Ctrl+I" },
  { "References", "references", "Shift+F12" },
  { "Rename", "rename", "F2" },
  { "Code\\ Actions", "action", "Ctrl+." },
  { "-sep2-" },
  { "Ask\\ Claude\\ Code", "claude", "Ctrl+Alt+S" },
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
  elseif ft == "lazycode_diag_hover" then
    return line == vim.api.nvim_buf_line_count(buf) and "pointer" or "default"
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

--- Sends a notification to the LazyCode window, when one is attached.
local function notify(method, ...)
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local info = ui.chan and vim.api.nvim_get_chan_info(ui.chan)
    if info and info.client and info.client.name == "lazycode-app" then
      vim.rpcnotify(ui.chan, method, ...)
    end
  end
end

local diag_win, diag_buf, diag_target
local diag_timer = vim.uv.new_timer()
local diag_ns = vim.api.nvim_create_namespace("lazycode_diag_hover")

local function close_diag_hover()
  if diag_win and vim.api.nvim_win_is_valid(diag_win) then
    pcall(vim.api.nvim_win_close, diag_win, true)
  end
  diag_win, diag_target = nil, nil
end

local SEV_HL = {
  [vim.diagnostic.severity.ERROR] = { " ", "DiagnosticError" },
  [vim.diagnostic.severity.WARN] = { " ", "DiagnosticWarn" },
  [vim.diagnostic.severity.INFO] = { " ", "DiagnosticInfo" },
  [vim.diagnostic.severity.HINT] = { " ", "DiagnosticHint" },
}

local function show_diag_at(row, col)
  if vim.fn.pumvisible() == 1 then
    return
  end
  local win = win_at(row, col)
  if not win or (diag_win and win == diag_win) then
    return
  end
  local cfg = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if cfg.relative ~= "" or vim.bo[buf].buftype ~= "" then
    return close_diag_hover()
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return
  end
  local lnum = vim.fn.line("w0", win) + row - (info.winrow - 1 + info.winbar) - 1
  local bcol = col - (info.wincol - 1 + info.textoff)
  if lnum < 0 or bcol < 0 then
    return close_diag_hover()
  end
  local hits = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { lnum = lnum })) do
    local ec = (d.end_col and d.end_col > d.col) and d.end_col or (d.col + 4)
    if bcol >= math.max(0, d.col - 1) and bcol <= ec + 1 then
      hits[#hits + 1] = d
    end
  end
  if #hits == 0 then
    return close_diag_hover()
  end
  local key = ("%d:%d:%d"):format(buf, lnum, hits[1].col)
  if diag_target == key and diag_win and vim.api.nvim_win_is_valid(diag_win) then
    return
  end
  close_diag_hover()
  diag_target = key
  local lines, marks = {}, {}
  local max_w = 28
  for _, d in ipairs(hits) do
    local sev = SEV_HL[d.severity] or SEV_HL[vim.diagnostic.severity.INFO]
    local first = true
    for msg_line in (d.message or ""):gmatch("[^\n]+") do
      local prefix = first and sev[1] or "  "
      local text = prefix .. msg_line .. (first and d.source and (" [" .. d.source .. "]") or "")
      lines[#lines + 1] = text
      marks[#marks + 1] = { #lines - 1, 0, #prefix, sev[2] }
      max_w = math.max(max_w, math.min(76, vim.fn.strdisplaywidth(text) + 2))
      first = false
    end
  end
  local action_line = "󰌶 Quick Fix...  (Ctrl+.)"
  lines[#lines + 1] = action_line
  marks[#marks + 1] = { #lines - 1, 0, #action_line, "Function" }
  if not (diag_buf and vim.api.nvim_buf_is_valid(diag_buf)) then
    diag_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[diag_buf].buftype = "nofile"
    vim.bo[diag_buf].filetype = "lazycode_diag_hover"
    vim.bo[diag_buf].bufhidden = "hide"
  end
  vim.bo[diag_buf].modifiable = true
  vim.api.nvim_buf_set_lines(diag_buf, 0, -1, false, lines)
  vim.bo[diag_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(diag_buf, diag_ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(diag_buf, diag_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  local height = math.min(10, #lines)
  local open_row = (row + height + 3 < vim.o.lines) and (row + 1) or math.max(1, row - height - 2)
  local open_col = math.max(4, math.min(col, vim.o.columns - max_w - 4))
  diag_win = vim.api.nvim_open_win(diag_buf, false, {
    relative = "editor",
    row = open_row,
    col = open_col,
    width = max_w,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    noautocmd = true,
    zindex = 60,
  })
  vim.wo[diag_win].wrap = true
  local target_win, target_lnum, target_col = win, lnum + 1, hits[1].col
  vim.keymap.set({ "n", "i" }, "<LeftRelease>", function()
    close_diag_hover()
    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
      pcall(vim.api.nvim_win_set_cursor, target_win, { target_lnum, target_col })
      vim.schedule(function()
        vim.lsp.buf.code_action()
      end)
    end
  end, { buffer = diag_buf, silent = true, nowait = true })
end

--- Called by the window on every cell the mouse enters. It arrives as a notification, so an
--- open :popup menu delays it instead of blocking the window, and mouse moves never become keys.
function M.hover(row, col)
  local over_popup = diag_win and vim.api.nvim_win_is_valid(diag_win) and win_at(row, col) == diag_win
  if not over_popup then
    if diag_win and vim.api.nvim_win_is_valid(diag_win) then
      local cfg = vim.api.nvim_win_get_config(diag_win)
      local near = math.abs(row - cfg.row) <= cfg.height + 2 and col >= cfg.col - 2 and col <= cfg.col + cfg.width + 2
      if not near then
        close_diag_hover()
      end
    end
    if diag_timer then
      diag_timer:stop()
      diag_timer:start(
        350,
        0,
        vim.schedule_wrap(function()
          show_diag_at(row, col)
        end)
      )
    end
  end
  local shape = M.shape_at(row, col)
  if shape == M.shape then
    return
  end
  M.shape = shape
  notify("lazycode_cursor", shape)
end

--- Tells the window which text areas scrolled. Neovim sends it no `grid_scroll` while a
--- floating window (like the Explorer) is open, so the window animates from these instead.
local function scrolled()
  for id, change in pairs(vim.v.event) do
    local win = tonumber(id)
    if
      win
      and change.topline ~= 0
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ""
    then
      local info = vim.fn.getwininfo(win)[1]
      local top, left = info.winrow - 1 + info.winbar, info.wincol - 1 + info.textoff
      notify("lazycode_scroll", top, top + info.height, left, info.wincol - 1 + info.width, change.topline)
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd(
    "WinScrolled",
    { group = vim.api.nvim_create_augroup("lazycode_scroll", {}), callback = scrolled }
  )
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
