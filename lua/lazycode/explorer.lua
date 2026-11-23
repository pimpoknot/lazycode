-- VS Code style Explorer: context menu, file operations and hidden cursor.
local M = { clip = nil, empty = false }

local uv = vim.uv
local MENU = "]LazyCodeExplorer"
local HIDDEN_CURSOR = "a:LazyCodeHiddenCursor"
local default_cursor

local function picker()
  return Snacks.picker.get({ source = "explorer" })[1]
end

local function tree()
  return require("snacks.explorer.tree")
end

local function actions()
  return require("snacks.explorer.actions")
end

local function normalize(path)
  return vim.fs.normalize(path)
end

local function current_item(p)
  if M.empty then
    return nil
  end
  return p:current()
end

local function target_dir(p)
  local item = current_item(p)
  if not item then
    return normalize(p:cwd())
  end
  local path = Snacks.picker.util.path(item)
  return item.dir and path or vim.fs.dirname(path)
end

local function selected_paths(p)
  if M.empty then
    return {}
  end
  return vim.tbl_map(Snacks.picker.util.path, p:selected({ fallback = true }))
end

local function refresh(p, dir, target)
  tree():refresh(dir)
  tree():open(dir)
  actions().update(p, { target = target or dir, refresh = true })
end

local function warn(message)
  Snacks.notify.warn(message, { title = "Explorer" })
end

-- Accepts "a/b.txt" like VS Code, but never leaves the target folder.
local function valid_name(value)
  value = value and vim.trim(value) or ""
  if value == "" or value:sub(1, 1) == "/" then
    return nil
  end
  for part in value:gmatch("[^/]+") do
    if part == "." or part == ".." then
      warn("Invalid name: `" .. value .. "`")
      return nil
    end
  end
  return value
end

local function open_in_editor(p, path)
  if vim.api.nvim_win_is_valid(p.main) then
    vim.api.nvim_set_current_win(p.main)
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function create(kind)
  local p = picker()
  if not p then
    return
  end
  local dir = target_dir(p)
  Snacks.input({ prompt = kind == "file" and "New File" or "New Folder" }, function(value)
    local name = valid_name(value)
    if not name then
      return
    end
    local is_dir = kind == "folder" or name:sub(-1) == "/"
    local path = normalize(dir .. "/" .. name)
    if uv.fs_lstat(path) then
      return warn("Already exists: `" .. vim.fn.fnamemodify(path, ":~:.") .. "`")
    end
    if is_dir then
      vim.fn.mkdir(path, "p")
    else
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      local fd, err = uv.fs_open(path, "wx", 420)
      if not fd then
        return warn("Could not create file: " .. tostring(err))
      end
      uv.fs_close(fd)
    end
    refresh(p, vim.fs.dirname(path), path)
    if not is_dir then
      open_in_editor(p, path)
    end
  end)
end

local function rename()
  local p = picker()
  local item = p and current_item(p)
  if not item then
    return
  end
  local from = Snacks.picker.util.path(item)
  local base = vim.fs.basename(from)
  Snacks.input({ prompt = "Rename", default = base }, function(value)
    local name = valid_name(value)
    if not name or name == base then
      return
    end
    local to = normalize(vim.fs.dirname(from) .. "/" .. name)
    if uv.fs_lstat(to) then
      return warn("Already exists: `" .. vim.fn.fnamemodify(to, ":~:.") .. "`")
    end
    Snacks.rename.rename_file({
      from = from,
      to = to,
      on_rename = function()
        tree():refresh(vim.fs.dirname(from))
        refresh(p, vim.fs.dirname(to), to)
      end,
    })
  end)
end

local function set_clip(cut)
  local p = picker()
  if not p then
    return
  end
  local paths = selected_paths(p)
  if #paths > 0 then
    M.clip = { paths = paths, cut = cut }
    p.list:set_selected()
  end
end

-- "a.txt" -> "a copy.txt" -> "a copy 2.txt"
local function unique_copy(dir, name)
  local to = dir .. "/" .. name
  if not uv.fs_lstat(to) then
    return to
  end
  local stem, ext = name:match("^(.+)(%.[^.]+)$")
  stem, ext = stem or name, ext or ""
  local n = 1
  while true do
    local suffix = n == 1 and " copy" or (" copy %d"):format(n)
    to = dir .. "/" .. stem .. suffix .. ext
    if not uv.fs_lstat(to) then
      return to
    end
    n = n + 1
  end
end

local function inside(path, parent)
  return path == parent or path:sub(1, #parent + 1) == parent .. "/"
end

local function paste()
  local p = picker()
  if not (p and M.clip) then
    return
  end
  local dir = target_dir(p)
  local last
  for _, from in ipairs(M.clip.paths) do
    local name = vim.fs.basename(from)
    if not uv.fs_lstat(from) then
      warn("No longer exists: `" .. name .. "`")
    elseif inside(dir, from) then
      warn("Cannot paste `" .. name .. "` into itself")
    elseif M.clip.cut then
      local to = dir .. "/" .. name
      if to ~= from and uv.fs_lstat(to) then
        warn("Already exists: `" .. name .. "`")
      elseif to ~= from then
        Snacks.rename.rename_file({
          from = from,
          to = to,
          on_rename = function()
            tree():refresh(vim.fs.dirname(from))
            refresh(p, dir, to)
          end,
        })
        last = to
      end
    else
      last = unique_copy(dir, name)
      Snacks.picker.util.copy_path(from, last)
    end
  end
  if M.clip.cut then
    M.clip = nil
  end
  refresh(p, dir, last)
end

local ONE_ESC = { win = { input = { keys = { ["<Esc>"] = { "cancel", mode = { "n", "i" } } } } } }

local function forget(path)
  if vim.fn.bufexists(path) == 1 then
    Snacks.bufdelete({ file = path, force = true })
  end
  tree():refresh(vim.fs.dirname(path))
end

-- Like VS Code: when there is no trash here, ask before deleting for good.
local function delete_permanently(p, paths)
  local what = #paths == 1 and vim.fs.basename(paths[1]) or (#paths .. " items")
  vim.ui.select({ "Cancel", "Delete Permanently" }, {
    prompt = "No trash here. Permanently delete " .. what .. "?",
    snacks = ONE_ESC,
  }, function(_, idx)
    if idx ~= 2 then
      return
    end
    for _, path in ipairs(paths) do
      if vim.fn.delete(path, "rf") == 0 then
        forget(path)
      else
        Snacks.notify.error("Failed to delete `" .. path .. "`")
      end
    end
    actions().update(p, { refresh = true })
  end)
end

local function delete()
  local p = picker()
  if not p then
    return
  end
  local paths = selected_paths(p)
  if #paths == 0 then
    return
  end
  local what = #paths == 1 and vim.fs.basename(paths[1]) or (#paths .. " items")
  vim.ui.select({ "Cancel", "Move to Trash" }, {
    prompt = "Delete " .. what .. "?",
    snacks = ONE_ESC,
  }, function(_, idx)
    if idx ~= 2 then
      return
    end
    -- Snacks deletes for good when no trash tool exists, so ask first.
    local has_trash = false
    for _, cmd in ipairs(actions().get_trash_cmds(paths[1])) do
      has_trash = has_trash or vim.fn.executable(cmd[1]) == 1
    end
    if not has_trash then
      return vim.schedule(function()
        delete_permanently(p, paths)
      end)
    end
    local failed = {}
    for _, path in ipairs(paths) do
      if actions().trash(path) then
        forget(path)
      else
        failed[#failed + 1] = path
      end
    end
    p.list:set_selected()
    actions().update(p, { refresh = true })
    if #failed > 0 then
      vim.schedule(function()
        delete_permanently(p, failed)
      end)
    end
  end)
end

local function copy_path(relative)
  local p = picker()
  local item = p and current_item(p)
  local path = item and Snacks.picker.util.path(item) or (p and normalize(p:cwd()))
  if not path then
    return
  end
  if relative then
    path = vim.fs.relpath(normalize(p:cwd()), path) or path
  end
  vim.fn.setreg("+", path)
end

M.commands = {
  new_file = function()
    create("file")
  end,
  new_folder = function()
    create("folder")
  end,
  terminal = function()
    local p = picker()
    if p then
      require("lazycode.terminal").toggle({ cwd = target_dir(p) })
    end
  end,
  reveal = function()
    local p = picker()
    if p then
      vim.ui.open(target_dir(p))
    end
  end,
  cut = function()
    set_clip(true)
  end,
  copy = function()
    set_clip(false)
  end,
  paste = paste,
  copy_path = function()
    copy_path(false)
  end,
  copy_relative = function()
    copy_path(true)
  end,
  rename = rename,
  delete = delete,
}

-- Menu entry point: acts on the clicked item (or the empty area).
function M.run(name)
  M.commands[name]()
  M.empty = false
end

-- Keyboard entry point: always acts on the current item.
function M.key(name)
  M.empty = false
  M.commands[name]()
end

local entries = {
  { "New File", "new_file" },
  { "New Folder", "new_folder" },
  { "Open in Terminal", "terminal" },
  { "Reveal in File Manager", "reveal" },
  { "-" },
  { "Cut", "cut", "Ctrl+X", item = true },
  { "Copy", "copy", "Ctrl+C", item = true },
  { "Paste", "paste", "Ctrl+V" },
  { "-", item = true },
  { "Copy Path", "copy_path" },
  { "Copy Relative Path", "copy_relative" },
  { "-", item = true },
  { "Rename", "rename", "F2", item = true },
  { "Delete", "delete", "Del", item = true },
}

local function build_menu(has_item)
  pcall(vim.cmd, "silent! aunmenu " .. MENU)
  local sep = 0
  for _, entry in ipairs(entries) do
    if has_item or not entry.item then
      if entry[1] == "-" then
        sep = sep + 1
        vim.cmd(("anoremenu %s.-sep%d- <Nop>"):format(MENU, sep))
      else
        local label = entry[1]:gsub(" ", "\\ ")
        if entry[3] then
          label = label .. "<Tab>" .. entry[3]
        end
        local rhs = ("<Cmd>lua require('lazycode.explorer').run('%s')<CR>"):format(entry[2])
        for _, cmd in ipairs({ "nnoremenu", "inoremenu" }) do
          vim.cmd(("%s <silent> %s.%s %s"):format(cmd, MENU, label, rhs))
        end
      end
    end
  end
  if not M.clip then
    for _, cmd in ipairs({ "nmenu", "imenu" }) do
      vim.cmd(("%s disable %s.Paste"):format(cmd, MENU))
    end
  end
end

function M.context()
  local p = picker()
  local pos = vim.fn.getmousepos()
  if not p or pos.winid ~= p.list.win.win then
    return
  end
  vim.api.nvim_set_current_win(pos.winid)
  local idx = p.list:row2idx(pos.winrow)
  local item = p.list:get(idx)
  M.empty = item == nil
  if item then
    p.list:move(idx, true)
  end
  build_menu(item ~= nil)
  -- :popup cannot run inside a mapping that came from Insert mode.
  if vim.fn.mode() == "i" then
    vim.cmd.stopinsert()
  end
  if M.menu_pending then
    return
  end
  M.menu_pending = true
  vim.defer_fn(function()
    M.menu_pending = false
    if vim.api.nvim_get_current_win() == pos.winid and vim.fn.pumvisible() == 0 then
      -- Timers keep running while the menu is open; a second :popup would be refused.
      pcall(vim.cmd, "popup! " .. MENU)
    end
  end, 15)
end

local function over_explorer()
  local p = picker()
  return p ~= nil and vim.fn.getmousepos().winid == p.list.win.win
end

local function sync_cursor()
  local ft = vim.bo.filetype
  local hide = (ft == "snacks_picker_list" or ft == "lazycode_bar" or ft == "lazycode_side" or ft == "lazycode_welcome")
    and vim.fn.getcmdtype() == ""
  local want = hide and HIDDEN_CURSOR or default_cursor
  if vim.o.guicursor ~= want then
    vim.o.guicursor = want
  end
end

local function set_highlights()
  vim.api.nvim_set_hl(0, "LazyCodeHiddenCursor", { blend = 100, nocombine = true })
end

function M.setup()
  default_cursor = vim.o.guicursor
  set_highlights()

  -- The menu opens on release, so the release event cannot close it.
  local rhs = "<Cmd>lua require('lazycode.explorer').context()<CR>"
  local term_rhs = "<Cmd>lua require('lazycode.terminal').context()<CR>"
  local pressed = false
  local function on_press()
    pressed = over_explorer() and "explorer" or false
    -- Programs running in the terminal (htop, vim) keep their own mouse handling.
    local terminal = require("lazycode.terminal")
    if not pressed and terminal.over() and (vim.fn.mode() ~= "t" or terminal.at_prompt()) then
      pressed = "terminal"
    end
    return pressed and "<Ignore>" or "<RightMouse>"
  end
  local function on_release(prefix)
    return function()
      local was = pressed
      pressed = false
      if was == "explorer" and over_explorer() then
        return prefix .. rhs
      elseif was == "terminal" then
        return (vim.fn.mode() == "t" and "<C-\\><C-n>" or "") .. term_rhs
      end
      return was and "<Ignore>" or "<RightRelease>"
    end
  end
  local opts = { expr = true, silent = true, replace_keycodes = true }
  vim.keymap.set({ "n", "i", "x", "s", "t" }, "<RightMouse>", on_press, opts)
  vim.keymap.set({ "n", "i", "x", "s" }, "<RightRelease>", on_release(""), opts)
  vim.keymap.set("t", "<RightRelease>", on_release("<C-\\><C-n>"), opts)

  local group = vim.api.nvim_create_augroup("lazycode_explorer", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "FileType", "CmdlineEnter", "CmdlineLeave" }, {
    group = group,
    callback = function()
      vim.schedule(sync_cursor)
    end,
  })
  -- Without this, the first letters typed into name prompts are lost.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "snacks_input",
    callback = function()
      vim.schedule(function()
        if vim.bo.filetype == "snacks_input" and vim.api.nvim_get_mode().mode == "n" then
          vim.api.nvim_feedkeys(vim.keycode("<Cmd>startinsert!<CR>"), "n", false)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      vim.o.guicursor = default_cursor
    end,
  })
  -- Pickers can switch windows without firing autocmds.
  local timer = assert(uv.new_timer())
  timer:start(150, 150, vim.schedule_wrap(sync_cursor))
  sync_cursor()
end

return M
