-- Welcome tab and the "No Folder Opened" side panel.
local M = { side_win = nil, side_id = nil }

local project = require("lazycode.project")
local platform = require("lazycode.platform")
local ns = vim.api.nvim_create_namespace("lazycode_welcome")
local SIDE_WIDTH = 46
local buf, side_buf
local actions, side_actions = {}, {}

local LOGO = {
  "██╗      █████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ██████╗ ███████╗",
  "██║     ██╔══██╗╚══███╔╝╚██╗ ██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝",
  "██║     ███████║  ███╔╝  ╚████╔╝ ██║     ██║   ██║██║  ██║█████╗  ",
  "██║     ██╔══██║ ███╔╝    ╚██╔╝  ██║     ██║   ██║██║  ██║██╔══╝  ",
  "███████╗██║  ██║███████╗   ██║   ╚██████╗╚██████╔╝██████╔╝███████╗",
  "╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝",
}

local START = {
  {
    icon = "󰝒",
    label = "New File...",
    key = "n",
    shortcut = "Ctrl+N",
    run = function()
      project.new_file()
    end,
  },
  {
    icon = "󰈔",
    label = "Open File...",
    key = "o",
    shortcut = "Ctrl+O",
    run = function()
      project.open_file()
    end,
  },
  {
    icon = "󰝰",
    label = "Open Folder...",
    key = "f",
    shortcut = "Ctrl+K Ctrl+O",
    run = function()
      project.pick_folder()
    end,
  },
  {
    icon = "󰊢",
    label = "Clone Git Repository...",
    key = "c",
    run = function()
      project.clone()
    end,
  },
}

local SIDE_TEXT = {
  explorer = { "You have not yet opened a folder." },
  search = { "Open a folder to search across its files." },
  git = { "Open a folder with a Git repository to use source control." },
}
local SIDE_TITLE = { explorer = "No Folder Opened", search = "Search", git = "Source Control" }

local function set_highlights()
  local fn = vim.api.nvim_get_hl(0, { name = "Function", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "LazyCodeButton", { fg = normal.bg or 0x1a1b26, bg = fn.fg or 0x7aa2f7, bold = true })
  vim.api.nvim_set_hl(0, "LazyCodeLogo", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "LazyCodeHeading", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "LazyCodeLink", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "LazyCodeMuted", { link = "Comment", default = true })
end

--- Writes rows of { text, highlight } chunks into a read-only buffer.
local function paint(target, rows)
  local lines, marks = {}, {}
  for r, row in ipairs(rows) do
    local text = ""
    for _, chunk in ipairs(row) do
      if chunk[2] then
        marks[#marks + 1] = { r - 1, #text, #text + #chunk[1], chunk[2] }
      end
      text = text .. chunk[1]
    end
    lines[r] = text
  end
  vim.bo[target].modifiable = true
  vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
  vim.bo[target].modifiable = false
  vim.bo[target].modified = false
  vim.api.nvim_buf_clear_namespace(target, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(target, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

local function shown_in(target)
  return target and vim.api.nvim_buf_is_valid(target) and vim.fn.bufwinid(target) or -1
end

function M.render()
  local win = shown_in(buf)
  if win == -1 then
    return
  end
  local width, height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
  local wide = width >= #LOGO[1] / 3 + 6 and vim.fn.strdisplaywidth(LOGO[1]) + 4 <= width
  local content = wide and vim.fn.strdisplaywidth(LOGO[1]) or math.min(44, width - 4)
  local pad = string.rep(" ", math.max(2, math.floor((width - content) / 2)))
  local rows = {}
  actions = {}
  if wide then
    for _, line in ipairs(LOGO) do
      rows[#rows + 1] = { { pad }, { line, "LazyCodeLogo" } }
    end
  else
    rows[#rows + 1] = { { pad }, { "LazyCode", "LazyCodeLogo" } }
  end
  rows[#rows + 1] = {}
  rows[#rows + 1] = { { pad }, { "Start", "LazyCodeHeading" } }
  for _, item in ipairs(START) do
    local row = { { pad }, { item.icon .. "  ", "LazyCodeLink" }, { item.label, "LazyCodeLink" } }
    if item.shortcut and content >= 44 then
      local used = vim.fn.strdisplaywidth(item.label) + 3
      local shortcut = platform.label(item.shortcut)
      row[#row + 1] = { string.rep(" ", math.max(2, 42 - used)) }
      row[#row + 1] = { shortcut, "LazyCodeMuted" }
    end
    rows[#rows + 1] = row
    actions[#rows] = item.run
  end
  local recent = project.recent()
  if #recent > 0 then
    rows[#rows + 1] = {}
    rows[#rows + 1] = { { pad }, { "Recent", "LazyCodeHeading" } }
    for i, path in ipairs(recent) do
      local name = vim.fs.basename(path)
      if name == "" then
        name = path
      end
      local parent = vim.fn.fnamemodify(vim.fs.dirname(path), ":~")
      local room = math.max(8, content - vim.fn.strdisplaywidth(name) - 4)
      if vim.fn.strdisplaywidth(parent) > room then
        parent = vim.fn.strcharpart(parent, 0, room - 1) .. "…"
      end
      rows[#rows + 1] = { { pad }, { name, "LazyCodeLink" }, { "   " }, { parent, "LazyCodeMuted" } }
      actions[#rows] = function()
        project.open_folder(path)
      end
      if i >= 8 then
        break
      end
    end
  end
  local top = math.max(1, math.floor((height - #rows) / 2) - 1)
  local spaced, moved = {}, {}
  for _ = 1, top do
    spaced[#spaced + 1] = {}
  end
  for r, row in ipairs(rows) do
    spaced[#spaced + 1] = row
    if actions[r] then
      moved[#spaced] = actions[r]
    end
  end
  actions = moved
  paint(buf, spaced)
end

local function wrap(text, width)
  local lines, current = {}, ""
  for word in text:gmatch("%S+") do
    if current ~= "" and vim.fn.strdisplaywidth(current .. " " .. word) > width then
      lines[#lines + 1] = current
      current = word
    else
      current = current == "" and word or current .. " " .. word
    end
  end
  if current ~= "" then
    lines[#lines + 1] = current
  end
  return lines
end

function M.render_side()
  if not (M.side_win and vim.api.nvim_win_is_valid(M.side_win)) then
    return
  end
  local width = vim.api.nvim_win_get_width(M.side_win)
  local inner = math.max(12, width - 4)
  local rows = { {}, { { "  " }, { "▾ " .. SIDE_TITLE[M.side_id], "LazyCodeHeading" } }, {} }
  side_actions = {}
  local function paragraph(text)
    for _, line in ipairs(wrap(text, inner)) do
      rows[#rows + 1] = { { "  " }, { line, "LazyCodeMuted" } }
    end
    rows[#rows + 1] = {}
  end
  local function button(label, run)
    local gap = math.max(0, inner - vim.fn.strdisplaywidth(label))
    local left = math.floor(gap / 2)
    rows[#rows + 1] = { { "  " }, { string.rep(" ", left) .. label .. string.rep(" ", gap - left), "LazyCodeButton" } }
    side_actions[#rows] = run
    rows[#rows + 1] = {}
  end
  for _, text in ipairs(SIDE_TEXT[M.side_id]) do
    paragraph(text)
  end
  button("Open Folder", project.pick_folder)
  if M.side_id ~= "search" then
    paragraph("You can clone a repository locally.")
    button("Clone Repository", project.clone)
  end
  paint(side_buf, rows)
end

--- True when a line of the Welcome tab or its side panel runs something on click.
function M.clickable(buffer, line)
  return (buffer == buf and actions[line] or buffer == side_buf and side_actions[line]) ~= nil
end

local function click(get)
  return function()
    local pos = vim.fn.getmousepos()
    local run = pos.winid == vim.api.nvim_get_current_win() and get()[pos.line]
    if run then
      vim.schedule(run)
    end
  end
end

local function activate(get)
  return function()
    local run = get()[vim.api.nvim_win_get_cursor(0)[1]]
    if run then
      run()
    end
  end
end

local function create_buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(true, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "lazycode_welcome"
  vim.api.nvim_buf_set_name(buf, "Welcome")
  vim.b[buf].snacks_main = true
  vim.b[buf].completion = false
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set(
    { "n", "i" },
    "<LeftRelease>",
    click(function()
      return actions
    end),
    opts
  )
  vim.keymap.set(
    "n",
    "<CR>",
    activate(function()
      return actions
    end),
    opts
  )
  for _, item in ipairs(START) do
    vim.keymap.set("n", item.key, item.run, opts)
  end
  return buf
end

--- The editor area: never the activity bar, a side panel, a picker or a terminal.
local function main_window()
  local fallback
  local current = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.insert(wins, 1, current)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_get_config(win).relative == "" and not vim.w[win].snacks_layout then
      local b = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[b].filetype
      if b == buf or vim.bo[b].buftype == "" then
        return win
      end
      if
        not fallback
        and ft ~= "lazycode_bar"
        and ft ~= "lazycode_side"
        and ft ~= "snacks_layout_box"
        and vim.bo[b].buftype ~= "terminal"
      then
        fallback = win
      end
    end
  end
  return fallback or current
end

function M.focus_main()
  local win = main_window()
  vim.api.nvim_set_current_win(win)
  return win
end

function M.show()
  local win = M.focus_main()
  local previous = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_win_set_buf(win, create_buffer())
  -- Remove the empty "[No Name]" tab Neovim starts with.
  if
    previous ~= buf
    and vim.api.nvim_buf_is_valid(previous)
    and vim.api.nvim_buf_get_name(previous) == ""
    and vim.bo[previous].buftype == ""
    and not vim.bo[previous].modified
    and vim.api.nvim_buf_line_count(previous) == 1
    and vim.api.nvim_buf_get_lines(previous, 0, 1, false)[1] == ""
  then
    pcall(vim.api.nvim_buf_delete, previous, { force = true })
  end
  for option, value in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    cursorline = false,
    list = false,
    wrap = false,
    statuscolumn = "",
  }) do
    vim.wo[win][0][option] = value
  end
  M.render()
end

--- After closing the last file, go back to the Welcome tab.
function M.show_if_empty()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and (b == buf or vim.api.nvim_buf_get_name(b) ~= "" or vim.bo[b].modified) then
      return
    end
  end
  M.show()
end

function M.side_visible(id)
  return M.side_win ~= nil and vim.api.nvim_win_is_valid(M.side_win) and (id == nil or M.side_id == id)
end

function M.open_side(id)
  if not (side_buf and vim.api.nvim_buf_is_valid(side_buf)) then
    side_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[side_buf].filetype = "lazycode_side"
    vim.bo[side_buf].bufhidden = "hide"
    local opts = { buffer = side_buf, silent = true, nowait = true }
    vim.keymap.set(
      { "n", "i" },
      "<LeftRelease>",
      click(function()
        return side_actions
      end),
      opts
    )
    vim.keymap.set(
      "n",
      "<CR>",
      activate(function()
        return side_actions
      end),
      opts
    )
  end
  if not M.side_visible() then
    M.side_win =
      vim.api.nvim_open_win(side_buf, false, { split = "left", win = -1, width = SIDE_WIDTH, style = "minimal" })
    vim.wo[M.side_win].winfixwidth = true
    vim.wo[M.side_win].winfixbuf = true
  end
  M.side_id = id
  M.render_side()
end

function M.close_side()
  if M.side_visible() then
    pcall(vim.api.nvim_win_close, M.side_win, true)
  end
  M.side_win, M.side_id = nil, nil
end

function M.fix_layout()
  if M.side_visible() then
    if vim.api.nvim_win_get_width(M.side_win) ~= SIDE_WIDTH then
      vim.api.nvim_win_set_width(M.side_win, SIDE_WIDTH)
    end
    M.render_side()
  end
  M.render()
end

function M.setup()
  set_highlights()
  local group = vim.api.nvim_create_augroup("lazycode_welcome", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      vim.schedule(M.fix_layout)
    end,
  })
end

return M
