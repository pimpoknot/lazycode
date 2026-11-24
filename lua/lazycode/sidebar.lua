-- Activity bar and the single side panel: Explorer, Search, lazygit and Extensions.
local M = { width = 46, active = nil, last = "explorer", changes = 0 }

local BAR_WIDTH = 4
local bar_buf, bar_win, lg
local ns = vim.api.nvim_create_namespace("lazycode_bar")
-- Icons sit in columns 2-3 of 4 (the window draws them two cells wide), 3 rows apart, and each
-- answers clicks on its own row and the rows around it. The git badge sits right below its icon.
-- The terminal and Reload are not side panels.
local items = {
  { id = "explorer", icon = "󰉋", row = 2 },
  { id = "search", icon = "󰍉", row = 5 },
  { id = "git", icon = "󰊢", row = 8 },
  { id = "terminal", icon = "󰆍", row = 11, panel = false },
  { id = "extensions", icon = "󰐱", row = 14 },
  { id = "reload", icon = "󰑓", row = 17, panel = false },
}
local BADGE = 9
local SEARCH = "lazycode_search"

--- The bar item for a buffer line of the bar, if any.
function M.item_at(line)
  for _, item in ipairs(items) do
    if math.abs(line - item.row) <= 1 then
      return item
    end
  end
end

local function pickers(source)
  return Snacks.picker.get({ source = source })
end

local function no_folder()
  return require("lazycode.project").folder == nil
end

local function terminal_open()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      vim.api.nvim_win_get_config(win).relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
    then
      return true
    end
  end
  return false
end

local function visible(id)
  if id == "terminal" then
    return terminal_open()
  elseif id == "extensions" then
    return #pickers("lazycode_extensions") > 0
  elseif id == "reload" then
    return require("lazycode.extensions").pending()
  end
  if no_folder() then
    return require("lazycode.welcome").side_visible(id)
  end
  if id == "git" then
    return lg ~= nil and lg:win_valid()
  elseif id == "search" then
    return package.loaded["grug-far"] ~= nil and require("grug-far").is_instance_open(SEARCH)
  end
  return #pickers("explorer") > 0
end

local function hide(id)
  if id == "extensions" then
    for _, picker in ipairs(pickers("lazycode_extensions")) do
      picker:close()
    end
    return
  end
  if no_folder() then
    return require("lazycode.welcome").close_side()
  end
  if id == "git" then
    if lg and lg:win_valid() then
      lg:hide()
    end
    return
  elseif id == "search" then
    return package.loaded["grug-far"] and require("grug-far").hide_instance(SEARCH)
  end
  for _, picker in ipairs(pickers("explorer")) do
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
    lines[BADGE] = " " .. (M.changes > 99 and "99" or tostring(M.changes))
  end
  vim.bo[bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, lines)
  vim.bo[bar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(bar_buf, ns, 0, -1)
  for _, item in ipairs(items) do
    local hl = visible(item.id) and (item.id == "reload" and "DiagnosticWarn" or "Function") or "Comment"
    vim.api.nvim_buf_set_extmark(bar_buf, ns, item.row - 1, 0, { end_col = #lines[item.row], hl_group = hl })
  end
  if M.changes > 0 then
    vim.api.nvim_buf_set_extmark(bar_buf, ns, BADGE - 1, 0, { end_col = #lines[BADGE], hl_group = "DiagnosticWarn" })
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
  local item = M.item_at(vim.fn.getmousepos().line)
  vim.cmd.wincmd("p")
  if not item then
    return
  elseif item.id == "terminal" then
    require("lazycode.terminal").toggle()
  elseif item.id == "reload" then
    require("lazycode.project").reload()
  else
    M.toggle(item.id)
  end
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
  if id == "extensions" then
    require("lazycode.extensions").open()
  elseif no_folder() then
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
    -- A fixed panel like VS Code's Search view, instead of a floating picker.
    local far = require("grug-far")
    if far.has_instance(SEARCH) then
      far.open_instance(SEARCH)
    else
      far.open({
        instanceName = SEARCH,
        staticTitle = "Search",
        windowCreationCommand = "topleft vertical " .. M.width .. "split",
      })
    end
    vim.wo.winfixwidth = true
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
      if item.id ~= id and item.panel ~= false and visible(item.id) then
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
  for _, source in ipairs({ "explorer", "lazycode_extensions" }) do
    for _, picker in ipairs(pickers(source)) do
      picker:close()
    end
  end
  if package.loaded["grug-far"] then
    pcall(require("grug-far").kill_instance, SEARCH)
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
  map("<C-S-x>", function()
    M.toggle("extensions")
  end, "Extensions")

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
  -- Like VS Code, one click on a search result opens it. Other lines keep the normal click.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "grug-far",
    callback = function(ev)
      vim.keymap.set({ "n", "i" }, "<LeftRelease>", function()
        local far = require("grug-far").get_instance(ev.buf)
        if far then
          far:goto_location()
        end
      end, { buffer = ev.buf, silent = true })
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
          if item.panel ~= false and visible(item.id) then
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
