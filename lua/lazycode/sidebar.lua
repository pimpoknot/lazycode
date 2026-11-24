-- Activity bar and the single side panel: Explorer, Search and lazygit.
local M = { width = 46, active = nil, last = "explorer", changes = 0 }

local BAR_WIDTH = 4
local bar_buf, bar_win, lg
local ns = vim.api.nvim_create_namespace("lazycode_bar")
local items = {
  { id = "explorer", icon = "󰉋", row = 2 },
  { id = "search", icon = "󰍉", row = 4 },
  { id = "git", icon = "󰊢", row = 6 },
}

local function pickers(source)
  return Snacks.picker.get({ source = source })
end

local function no_folder()
  return require("lazycode.project").folder == nil
end

local function visible(id)
  if no_folder() then
    return require("lazycode.welcome").side_visible(id)
  end
  if id == "git" then
    return lg ~= nil and lg:win_valid()
  end
  return #pickers(id == "search" and "grep" or "explorer") > 0
end

local function hide(id)
  if no_folder() then
    return require("lazycode.welcome").close_side()
  end
  if id == "git" then
    if lg and lg:win_valid() then
      lg:hide()
    end
    return
  end
  for _, picker in ipairs(pickers(id == "search" and "grep" or "explorer")) do
    picker:close()
  end
end

function M.render()
  if not (bar_buf and vim.api.nvim_buf_is_valid(bar_buf)) then
    return
  end
  local lines = {}
  for i = 1, math.max(vim.o.lines - 3, 8) do
    lines[i] = ""
  end
  for _, item in ipairs(items) do
    lines[item.row] = " " .. item.icon
  end
  if M.changes > 0 then
    lines[7] = " " .. (M.changes > 99 and "99" or tostring(M.changes))
  end
  vim.bo[bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, lines)
  vim.bo[bar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(bar_buf, ns, 0, -1)
  for _, item in ipairs(items) do
    local hl = visible(item.id) and "Function" or "Comment"
    vim.api.nvim_buf_set_extmark(bar_buf, ns, item.row - 1, 0, { end_col = #lines[item.row], hl_group = hl })
  end
  if M.changes > 0 then
    vim.api.nvim_buf_set_extmark(bar_buf, ns, 6, 0, { end_col = #lines[7], hl_group = "DiagnosticWarn" })
  end
end

function M.refresh_git()
  if no_folder() then
    M.changes = 0
    return M.render()
  end
  vim.system({ "git", "status", "--porcelain" }, { text = true, cwd = vim.uv.cwd() }, function(out)
    local count = 0
    if out.code == 0 then
      for _ in (out.stdout or ""):gmatch("[^\n]+") do
        count = count + 1
      end
    end
    vim.schedule(function()
      M.changes = count
      M.render()
    end)
  end)
end

local function click()
  local pos = vim.fn.getmousepos()
  for _, item in ipairs(items) do
    if pos.line == item.row or (item.id == "git" and pos.line == 7) then
      M.toggle(item.id)
      return
    end
  end
  vim.cmd.wincmd("p")
end

local function ensure_bar()
  if bar_win and vim.api.nvim_win_is_valid(bar_win) then
    return
  end
  if not (bar_buf and vim.api.nvim_buf_is_valid(bar_buf)) then
    bar_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[bar_buf].filetype = "lazycode_bar"
    vim.bo[bar_buf].bufhidden = "hide"
    vim.keymap.set({ "n", "i" }, "<LeftRelease>", click, { buffer = bar_buf, silent = true })
  end
  bar_win = vim.api.nvim_open_win(bar_buf, false, { split = "left", win = -1, width = BAR_WIDTH, style = "minimal" })
  vim.wo[bar_win].winfixwidth = true
  vim.wo[bar_win].winfixbuf = true
  M.render()
end

local function fix_layout()
  if not (bar_win and vim.api.nvim_win_is_valid(bar_win)) then
    return
  end
  if vim.api.nvim_win_get_position(bar_win)[2] ~= 0 then
    vim.api.nvim_win_call(bar_win, function()
      vim.cmd.wincmd("H")
    end)
  end
  if vim.api.nvim_win_get_width(bar_win) ~= BAR_WIDTH then
    vim.api.nvim_win_set_width(bar_win, BAR_WIDTH)
  end
  require("lazycode.welcome").fix_layout()
  M.render()
end

local function show(id, opts)
  if no_folder() then
    require("lazycode.welcome").open_side(id)
  elseif id == "explorer" then
    -- Opening a folder (`nvim .`) already creates the Explorer; calling it again would close it.
    local existing = pickers("explorer")[1]
    if not existing then
      Snacks.explorer(opts)
    elseif not (opts and opts.enter == false) then
      existing:focus()
    end
  elseif id == "search" then
    Snacks.picker.grep({
      auto_close = false,
      jump = { close = false },
      layout = { preset = "sidebar", preview = false },
    })
  elseif lg and lg:buf_valid() then
    lg:show()
    lg:focus()
    vim.cmd.startinsert()
  else
    lg = Snacks.lazygit({
      cwd = LazyVim.root.git(),
      -- Covers the editor but not the activity bar, so lazygit has room for its diff on the right.
      win = {
        position = "float",
        backdrop = false,
        border = "none",
        enter = true,
        row = 1,
        col = BAR_WIDTH + 1,
        width = function()
          return vim.o.columns - BAR_WIDTH - 1
        end,
        height = function()
          return vim.o.lines - vim.o.cmdheight - 2
        end,
      },
    })
    vim.schedule(function()
      if lg and lg:win_valid() and vim.api.nvim_get_current_win() == lg.win then
        vim.cmd.startinsert()
      end
    end)
  end
end

function M.toggle(id, opts)
  ensure_bar()
  if M.active == id and visible(id) then
    hide(id)
    M.active = nil
  else
    for _, item in ipairs(items) do
      if item.id ~= id and visible(item.id) then
        hide(item.id)
      end
    end
    show(id, opts)
    M.active, M.last = id, id
  end
  vim.schedule(fix_layout)
end

--- Closes every panel and the lazygit process, before switching folders.
function M.reset()
  require("lazycode.welcome").close_side()
  for _, source in ipairs({ "explorer", "grep" }) do
    for _, picker in ipairs(pickers(source)) do
      picker:close()
    end
  end
  if lg then
    pcall(function()
      lg:close()
    end)
    lg = nil
  end
  M.active = nil
end

function M.toggle_sidebar()
  if M.active and visible(M.active) then
    M.toggle(M.active)
  else
    M.toggle(M.last)
  end
end

function M.setup()
  -- Snacks keeps its WinResized handler after closing a picker, and rendering then fails on the nil picker.
  local List = require("snacks.picker.core.list")
  local render = List.render
  List.render = function(self)
    if self.picker then
      return render(self)
    end
  end

  local map = function(lhs, fn, desc)
    require("lazycode.platform").map({ "n", "i", "x", "s", "t" }, lhs, fn, { silent = true, desc = desc })
  end
  map("<C-b>", M.toggle_sidebar, "Toggle Sidebar")
  map("<C-S-e>", function()
    M.toggle("explorer")
  end, "Explorer")
  map("<C-S-f>", function()
    M.toggle("search")
  end, "Search in Files")
  map("<C-S-g>", function()
    M.toggle("git")
  end, "Source Control (lazygit)")

  local group = vim.api.nvim_create_augroup("lazycode_sidebar", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "DirChanged", "TermLeave" }, {
    group = group,
    callback = M.refresh_git,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinNew", "WinClosed" }, {
    group = group,
    callback = function()
      vim.schedule(fix_layout)
    end,
  })
  -- When the last editor window closes, quit instead of leaving the bar alone.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local editors = 0
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
          editors = editors + 1
        end
      end
      if editors <= 1 then
        for _, item in ipairs(items) do
          if visible(item.id) then
            hide(item.id)
          end
        end
        if bar_win and vim.api.nvim_win_is_valid(bar_win) then
          pcall(vim.api.nvim_win_close, bar_win, true)
        end
      end
    end,
  })

  if #vim.api.nvim_list_uis() > 0 then
    if vim.fn.argc() == 0 then
      require("lazycode.welcome").show()
    end
    -- Like VS Code, initial focus is on the editor, not the Explorer.
    M.toggle("explorer", { enter = false })
  end
  M.refresh_git()
end

return M
