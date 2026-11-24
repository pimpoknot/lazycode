-- Project state: open folder, recent folders, file/folder choosers and git clone.
local M = { folder = nil }

local uv = vim.uv
local MAX_RECENT = 8
local platform = require("lazycode.platform")

local function recent_path()
  return vim.fn.stdpath("state") .. "/lazycode_recent.json"
end

local function normalize(path)
  local full = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return #full > 1 and full:gsub("/$", "") or full
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "LazyCode" })
end

function M.recent()
  local fd = io.open(recent_path(), "r")
  if not fd then
    return {}
  end
  local raw = fd:read("*a")
  fd:close()
  local ok, list = pcall(vim.json.decode, raw)
  if not ok or type(list) ~= "table" then
    return {}
  end
  return vim.tbl_filter(function(path)
    return type(path) == "string" and vim.fn.isdirectory(path) == 1
  end, list)
end

function M.remember(path)
  local list = { path }
  for _, item in ipairs(M.recent()) do
    if item ~= path and #list < MAX_RECENT then
      list[#list + 1] = item
    end
  end
  vim.fn.mkdir(vim.fs.dirname(recent_path()), "p")
  local fd = io.open(recent_path(), "w")
  if fd then
    fd:write(vim.json.encode(list))
    fd:close()
  end
end

--- The launcher says how it was started: "welcome" (no folder) or "folder".
function M.init()
  local start = vim.env.LAZYCODE_START
  vim.env.LAZYCODE_START = nil
  if start == "welcome" then
    M.folder = nil
  else
    M.folder = normalize(uv.cwd())
    if start == "folder" then
      M.remember(M.folder)
    end
  end
end

local function native_command(kind)
  if platform.mac then
    local what = kind == "folder" and "choose folder" or "choose file"
    return { "osascript", "-e", "POSIX path of (" .. what .. ")" }
  end
  if vim.fn.executable("zenity") == 1 then
    local cmd = { "zenity", "--file-selection" }
    if kind == "folder" then
      cmd[#cmd + 1] = "--directory"
    end
    return cmd
  end
  if vim.fn.executable("kdialog") == 1 then
    return {
      "kdialog",
      kind == "folder" and "--getexistingdirectory" or "--getopenfilename",
      M.folder or uv.os_homedir(),
    }
  end
end

local function browse(kind, dir, done)
  local function entries()
    local dirs, files = {}, {}
    local ok = pcall(function()
      for name, entry in vim.fs.dir(dir) do
        local path = dir == "/" and "/" .. name or dir .. "/" .. name
        local is_dir = entry == "directory" or (entry == "link" and vim.fn.isdirectory(path) == 1)
        if is_dir then
          dirs[#dirs + 1] = { text = name, path = path, is_dir = true }
        elseif kind == "file" then
          files[#files + 1] = { text = name, path = path }
        end
      end
    end)
    if not ok then
      notify("Cannot read " .. dir, vim.log.levels.WARN)
    end
    local by_name = function(a, b)
      return a.text:lower() < b.text:lower()
    end
    table.sort(dirs, by_name)
    table.sort(files, by_name)
    local items = {}
    if kind == "folder" then
      items[#items + 1] = { text = "Select this folder", path = dir, select = true }
    end
    if dir ~= "/" then
      items[#items + 1] = { text = "..", path = vim.fs.dirname(dir), is_dir = true }
    end
    vim.list_extend(items, dirs)
    vim.list_extend(items, files)
    return items
  end

  Snacks.picker.pick({
    source = "lazycode_browse",
    title = (kind == "folder" and "Open Folder: " or "Open File: ") .. vim.fn.fnamemodify(dir, ":~"),
    items = entries(),
    preview = "none",
    layout = { preset = "select" },
    matcher = { sort_empty = false },
    format = function(item)
      local icon = item.select and "󰄬 " or item.is_dir and "󰉋 " or "󰈔 "
      local hl = item.select and "Function" or item.is_dir and "Directory" or "Normal"
      return { { icon, hl }, { item.text, hl } }
    end,
    win = {
      input = { keys = { ["<Esc>"] = { "cancel", mode = { "n", "i" } } } },
      list = { keys = { ["<2-LeftMouse>"] = false, ["<LeftRelease>"] = "lazycode_click" } },
    },
    confirm = function(picker, item)
      if not item then
        return
      end
      picker:close()
      vim.schedule(function()
        if item.select or not item.is_dir then
          done(item.path)
        else
          browse(kind, item.path, done)
        end
      end)
    end,
  })
end

--- Native dialog when the system has one, built-in browser otherwise.
function M.choose(kind, done)
  local start = M.folder or uv.os_homedir()
  local cmd = native_command(kind)
  if not cmd then
    return browse(kind, start, done)
  end
  local ok = pcall(vim.system, cmd, { text = true }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        local path = vim.trim(out.stdout or "")
        if path ~= "" then
          done(normalize(path))
        end
      elseif out.code ~= 1 then
        browse(kind, start, done) -- the dialog could not run; code 1 is "cancelled"
      end
    end)
  end)
  if not ok then
    browse(kind, start, done)
  end
end

local function dirty_buffers()
  return vim.tbl_filter(function(buf)
    return vim.bo[buf].buflisted and vim.bo[buf].modified and vim.bo[buf].buftype == ""
  end, vim.api.nvim_list_bufs())
end

local function switch_folder(path)
  local welcome = require("lazycode.welcome")
  local sidebar = require("lazycode.sidebar")
  sidebar.reset()
  for _, term in ipairs(Snacks.terminal.list()) do
    term:close()
  end
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
  welcome.show()
  local main = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= main and vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  vim.cmd.cd(vim.fn.fnameescape(path))
  M.folder = path
  M.remember(path)
  welcome.render()
  sidebar.toggle("explorer", { enter = false })
  sidebar.refresh_git()
end

function M.open_folder(path)
  path = normalize(path)
  if vim.fn.isdirectory(path) ~= 1 then
    return notify("Folder not found: " .. path, vim.log.levels.WARN)
  end
  local dirty = dirty_buffers()
  if #dirty == 0 then
    return switch_folder(path)
  end
  vim.ui.select({ "Cancel", "Save All", "Don't Save" }, {
    prompt = ("%d unsaved file(s). Open folder anyway?"):format(#dirty),
  }, function(_, idx)
    if idx == 2 then
      for _, buf in ipairs(dirty) do
        if vim.api.nvim_buf_get_name(buf) == "" then
          return notify("Save untitled files before opening a folder", vim.log.levels.WARN)
        end
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent write")
        end)
      end
      switch_folder(path)
    elseif idx == 3 then
      switch_folder(path)
    end
  end)
end

function M.pick_folder()
  M.choose("folder", M.open_folder)
end

function M.new_file()
  require("lazycode.welcome").focus_main()
  vim.cmd.enew()
end

function M.open_file()
  M.choose("file", function(path)
    require("lazycode.welcome").focus_main()
    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

local function repo_name(url)
  local name = url:gsub("/+$", ""):match("([^/:]+)$")
  return name and name:gsub("%.git$", "") or nil
end

local function valid_url(url)
  if url:sub(1, 1) == "-" or url:find("%s") then
    return false
  end
  return url:match("^https?://") ~= nil
    or url:match("^ssh://") ~= nil
    or url:match("^git@[^:]+:.+") ~= nil
    or url:match("^file://") ~= nil
end

function M.clone()
  Snacks.input({ prompt = "Repository URL" }, function(value)
    local url = value and vim.trim(value) or ""
    if url == "" then
      return
    end
    local name = repo_name(url)
    if not valid_url(url) or not name or name == "" or name == ".." then
      return notify("Invalid repository URL", vim.log.levels.WARN)
    end
    M.choose("folder", function(parent)
      local dest = parent .. "/" .. name
      if uv.fs_lstat(dest) then
        return notify("Already exists: " .. vim.fn.fnamemodify(dest, ":~"), vim.log.levels.WARN)
      end
      notify("Cloning " .. name .. "...")
      local env = { GIT_TERMINAL_PROMPT = "0" }
      vim.system({ "git", "clone", "--", url, dest }, { text = true, env = env }, function(out)
        vim.schedule(function()
          if out.code == 0 then
            M.open_folder(dest)
          else
            notify("Clone failed:\n" .. vim.trim(out.stderr or ""), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end

local function unsaved()
  return vim.tbl_filter(function(buf)
    return vim.bo[buf].modified and vim.bo[buf].buftype == ""
  end, vim.api.nvim_list_bufs())
end

local function reload_path()
  return vim.fn.stdpath("state") .. "/lazycode_reload.json"
end

--- Reload Window, like VS Code: restarts Neovim in the same window, folder and open files.
function M.reload()
  if #unsaved() > 0 then
    if vim.fn.confirm("Save changes before reloading the window?", "&Save All\n&Cancel", 1) ~= 1 then
      return
    end
    vim.cmd("silent! wall")
    if #unsaved() > 0 then
      return notify("Some files could not be saved, so the window was not reloaded", vim.log.levels.ERROR)
    end
  end
  -- Focus the editor: it holds the active file, and the QuitPre in sidebar.lua closes the
  -- panels, where quitting from a closed window would abort.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
  local files, current = {}, vim.api.nvim_buf_get_name(0)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and name ~= "" and name ~= current then
      files[#files + 1] = name
    end
  end
  if vim.bo.buftype == "" and current ~= "" then
    files[#files + 1] = current -- opened last, so it is the active tab again
  end
  local fd = io.open(reload_path(), "w")
  if fd then
    fd:write(vim.json.encode(files))
    fd:close()
  end
  -- The new Neovim inherits this environment and working directory.
  vim.env.LAZYCODE_START = M.folder and "folder" or "welcome"
  -- Files are saved by now; qall! only skips terminals and prompts that would block :qall.
  vim.cmd("restart +qall! lua require('lazycode.project').reopen()")
end

--- Runs in the restarted Neovim: opens the files that were open before Reload Window.
function M.reopen()
  local fd = io.open(reload_path(), "r")
  if not fd then
    return
  end
  local ok, files = pcall(vim.json.decode, fd:read("*a"))
  fd:close()
  os.remove(reload_path())
  for _, file in ipairs(ok and files or {}) do
    if uv.fs_stat(file) then
      vim.cmd.edit(vim.fn.fnameescape(file))
    end
  end
end

return M
