-- Top menu bar (File, Edit, Selection, View, Go, Terminal, Help) rendered in the tabline.
local M = {}

local platform = require("lazycode.platform")

local function feed(keys)
  return function()
    vim.api.nvim_feedkeys(vim.keycode(keys), "m", false)
  end
end

local function menus()
  local project = require("lazycode.project")
  local editing = require("lazycode.editing")
  local sidebar = require("lazycode.sidebar")
  local terminal = require("lazycode.terminal")
  local welcome = require("lazycode.welcome")
  local languages = require("lazycode.languages")
  local font = require("lazycode.font")
  local lc = require("lazycode")

  return {
    {
      id = "File",
      items = {
        { "New File", project.new_file, "Ctrl+N" },
        { "Open File...", project.open_file, "Ctrl+O" },
        { "Open Folder...", project.pick_folder, "Ctrl+K Ctrl+O" },
        { "-" },
        {
          "Save",
          function()
            if vim.api.nvim_buf_get_name(0) ~= "" then
              vim.cmd("silent! write")
            else
              feed("<C-s>")()
            end
          end,
          "Ctrl+S",
        },
        { "Save As...", feed("<C-S-s>"), "Ctrl+Shift+S" },
        {
          "Save All",
          function()
            vim.cmd("silent! wall")
          end,
          "Ctrl+K S",
        },
        { "-" },
        { "Close Editor", editing.close_buffer, "Ctrl+W" },
        {
          "Close All Editors",
          function()
            Snacks.bufdelete.all()
            vim.schedule(welcome.show_if_empty)
          end,
          "Ctrl+K Ctrl+W",
        },
        { "Reopen Closed Editor", editing.reopen_buffer, "Ctrl+Shift+T" },
        { "-" },
        {
          "Quit",
          function()
            vim.cmd("confirm qa")
          end,
          "Ctrl+Q",
        },
      },
    },
    {
      id = "Edit",
      items = {
        { "Undo", feed("<C-z>"), "Ctrl+Z" },
        { "Redo", feed("<C-y>"), "Ctrl+Y" },
        { "-" },
        { "Cut", feed("<C-x>"), "Ctrl+X" },
        { "Copy", feed("<C-c>"), "Ctrl+C" },
        { "Paste", feed("<C-v>"), "Ctrl+V" },
        { "-" },
        {
          "Find",
          function()
            Snacks.picker.lines({ pattern = editing.consume_selection() })
          end,
          "Ctrl+F",
        },
        { "Replace", feed("<C-h>"), "Ctrl+H" },
        {
          "Find in Files",
          function()
            sidebar.toggle("search")
          end,
          "Ctrl+Shift+F",
        },
        {
          "Replace in Files",
          function()
            sidebar.open_search(editing.consume_selection())
          end,
          "Ctrl+Shift+H",
        },
        { "-" },
        { "Toggle Line Comment", feed("<C-/>"), "Ctrl+/" },
        {
          "Format Document",
          function()
            LazyVim.format({ force = true })
          end,
          "Shift+Alt+F",
        },
      },
    },
    {
      id = "Selection",
      items = {
        { "Select All", feed("<C-a>"), "Ctrl+A" },
        { "Expand Line Selection", feed("<C-l>"), "Ctrl+L" },
        { "-" },
        { "Copy Line Up", feed("<S-A-Up>"), "Shift+Alt+Up" },
        { "Copy Line Down", feed("<S-A-Down>"), "Shift+Alt+Down" },
        { "Move Line Up", feed("<A-Up>"), "Alt+Up" },
        { "Move Line Down", feed("<A-Down>"), "Alt+Down" },
        { "-" },
        { "Add Cursor Above", feed("<C-A-Up>"), "Ctrl+Alt+Up" },
        { "Add Cursor Below", feed("<C-A-Down>"), "Ctrl+Alt+Down" },
        { "Add Next Occurrence", feed("<C-d>"), "Ctrl+D" },
        { "Select All Occurrences", feed("<C-S-l>"), "Ctrl+Shift+L" },
      },
    },
    {
      id = "View",
      items = {
        { "Command Palette...", feed("<C-S-p>"), "Ctrl+Shift+P" },
        { "-" },
        {
          "Explorer",
          function()
            sidebar.toggle("explorer")
          end,
          "Ctrl+Shift+E",
        },
        {
          "Search",
          function()
            sidebar.toggle("search")
          end,
          "Ctrl+Shift+F",
        },
        {
          "Source Control (Git)",
          function()
            sidebar.toggle("git")
          end,
          "Ctrl+Shift+G",
        },
        {
          "Extensions",
          function()
            sidebar.toggle("extensions")
          end,
          "Ctrl+Shift+X",
        },
        {
          "Problems",
          function()
            Snacks.picker.diagnostics()
          end,
          "Ctrl+Shift+M",
        },
        {
          "Output",
          function()
            Snacks.notifier.show_history()
          end,
          "Ctrl+Shift+U",
        },
        {
          "Terminal",
          function()
            terminal.toggle()
          end,
          "Ctrl+`",
        },
        { "-" },
        { "Toggle Side Bar", sidebar.toggle_sidebar, "Ctrl+B" },
        {
          "Split Editor",
          function()
            vim.cmd.vsplit()
          end,
          "Ctrl+\\",
        },
        {
          "Toggle Word Wrap",
          function()
            vim.wo.wrap = not vim.wo.wrap
          end,
          "Alt+Z",
        },
        {
          "Zen Mode",
          function()
            Snacks.zen()
          end,
          "Ctrl+K Z",
        },
        { "-" },
        {
          "Color Theme...",
          function()
            Snacks.picker.colorschemes()
          end,
          "Ctrl+K Ctrl+T",
        },
        {
          "Zoom In",
          function()
            font.set(font.current_size() + 1)
          end,
          "Ctrl+=",
        },
        {
          "Zoom Out",
          function()
            font.set(font.current_size() - 1)
          end,
          "Ctrl+-",
        },
        {
          "Reset Zoom",
          function()
            font.set(font.size)
          end,
          "Ctrl+0",
        },
      },
    },
    {
      id = "Go",
      items = {
        { "Back", feed("<A-Left>"), "Alt+Left" },
        { "Forward", feed("<A-Right>"), "Alt+Right" },
        { "-" },
        { "Go to File...", feed("<C-p>"), "Ctrl+P" },
        {
          "Go to Symbol in Editor...",
          function()
            Snacks.picker.lsp_symbols()
          end,
          "Ctrl+Shift+O",
        },
        {
          "Go to Symbol in Workspace...",
          function()
            Snacks.picker.lsp_workspace_symbols()
          end,
          "Ctrl+T",
        },
        {
          "Go to Definition",
          function()
            vim.lsp.buf.definition({ reuse_win = true })
          end,
          "F12",
        },
        {
          "Go to Implementations",
          function()
            Snacks.picker.lsp_implementations()
          end,
          "Ctrl+F12",
        },
        {
          "Go to References",
          function()
            Snacks.picker.lsp_references()
          end,
          "Shift+F12",
        },
        { "Go to Line...", feed("<C-g>"), "Ctrl+G" },
        { "-" },
        { "Next Problem", feed("<F8>"), "F8" },
        { "Previous Problem", feed("<S-F8>"), "Shift+F8" },
      },
    },
    {
      id = "Terminal",
      items = {
        {
          "Toggle Terminal",
          function()
            terminal.toggle()
          end,
          "Ctrl+`",
        },
        {
          "New Terminal",
          function()
            Snacks.terminal.open(nil, { shell = terminal.shell() })
          end,
          "Ctrl+Shift+`",
        },
        { "-" },
        { "Open Claude Code", feed("<C-A-c>"), "Ctrl+Alt+C" },
        { "Send Selection to Claude Code", lc.send_to_claude, "Ctrl+Alt+S" },
      },
    },
    {
      id = "Help",
      items = {
        { "Welcome", welcome.show },
        { "Command Palette...", feed("<C-S-p>"), "Ctrl+Shift+P" },
        {
          "Keyboard Shortcuts",
          function()
            Snacks.picker.keymaps()
          end,
          "Ctrl+K Ctrl+S",
        },
        { "-" },
        {
          "Manage Plugins (Lazy)...",
          function()
            require("lazycode.extensions").pick_plugins()
          end,
        },
        { "Install LSP / Tools (Mason)...", languages.pick_mason },
        {
          "Enable Language Support...",
          function()
            languages.enable("")
          end,
        },
        { "Toggle Vim Mode", editing.toggle_vim, "Ctrl+Alt+V" },
        { "-" },
        { "Reload Window", project.reload },
      },
    },
  }
end

local actions = {} ---@type table<string, fun()>
local menu_names = { "File", "Edit", "Selection", "View", "Go", "Terminal", "Help" }

local function escape_menu(s)
  return (s:gsub("\\", "\\\\"):gsub(" ", "\\ "):gsub("%.", "\\."):gsub("\t", "\\t"))
end

local function build_menus()
  actions = {}
  for _, group in ipairs(menus()) do
    local root = "]LazyCodeTop_" .. group.id
    pcall(vim.cmd, "silent! aunmenu " .. root)
    local sep = 0
    for idx, entry in ipairs(group.items) do
      if entry[1] == "-" then
        sep = sep + 1
        vim.cmd(("anoremenu %d %s.-sep%d- <Nop>"):format(idx * 10, root, sep))
      else
        local key = ("%s_%d"):format(group.id, idx)
        actions[key] = entry[2]
        local label = escape_menu(entry[1])
        if entry[3] then
          label = label .. "<Tab>" .. escape_menu(platform.label(entry[3]))
        end
        local rhs = ("<Cmd>lua require('lazycode.menubar').run(%q)<CR>"):format(key)
        for _, cmd in ipairs({ "nnoremenu", "inoremenu", "xnoremenu", "snoremenu" }) do
          vim.cmd(("%s <silent> %d %s.%s %s"):format(cmd, idx * 10, root, label, rhs))
        end
      end
    end
  end
end

function M.run(key)
  local fn = actions[key]
  if fn then
    vim.schedule(fn)
  end
end

function M.open(id)
  build_menus()
  -- :popup requires leaving Insert or Terminal mode before opening.
  local mode = vim.fn.mode()
  if mode == "i" then
    vim.cmd.stopinsert()
  elseif mode == "t" then
    vim.cmd.stopinsert()
  end
  vim.defer_fn(function()
    if vim.fn.pumvisible() == 0 then
      pcall(vim.cmd, "popup! ]LazyCodeTop_" .. id)
    end
  end, 15)
end

--- Segments for bufferline's `custom_areas.left`: clickable top menu + dynamic sidebar alignment.
function M.segments()
  local out = {}
  local used = 0
  for _, name in ipairs(menu_names) do
    local label = " " .. name .. " "
    used = used + #label
    out[#out + 1] = {
      text = ("%%@v:lua.LazyCodeTopMenu_%s@%s%%X"):format(name, label),
      link = "BufferLineBackground",
    }
  end
  -- Keep open file tabs aligned with the editor border when a side panel (46 cols) is open.
  local target = 4 + require("lazycode.sidebar").panel_columns()
  if target > used then
    out[#out + 1] = {
      text = string.rep(" ", target - used),
      link = "BufferLineFill",
    }
  else
    out[#out + 1] = {
      text = " │",
      link = "BufferLineOffsetSeparator",
    }
  end
  return out
end

function M.setup()
  for _, name in ipairs(menu_names) do
    _G["LazyCodeTopMenu_" .. name] = function()
      M.open(name)
    end
  end
  build_menus()
end

return M
