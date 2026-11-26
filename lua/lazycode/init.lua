local M = {}

function M.send_to_claude()
  pcall(function()
    require("lazy").load({ plugins = { "claudecode.nvim" } })
  end)
  if vim.fn.exists(":ClaudeCode") ~= 2 then
    return vim.notify(
      "Enable ai.claudecode in Extensions (Ctrl+Shift+X) first.",
      vim.log.levels.INFO,
      { title = "Claude Code" }
    )
  end
  local mode = vim.fn.mode()
  if mode:match("^[vVsS\22\19]") then
    local ok, vc = pcall(require, "claudecode.visual_commands")
    if ok and vc.send_to_claude_from_visual then
      vc.send_to_claude_from_visual()
      vim.defer_fn(function()
        pcall(vim.cmd, "ClaudeCodeFocus")
      end, 120)
      return
    end
  end
  if vim.api.nvim_buf_get_name(0) ~= "" then
    pcall(vim.cmd, "ClaudeCodeAdd %")
  end
  pcall(vim.cmd, "ClaudeCodeFocus")
end

local function focus_group(index)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" and not vim.w[win].snacks_layout then
      local b = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[b].filetype
      if
        ft ~= "lazycode_bar"
        and ft ~= "lazycode_side"
        and ft ~= "snacks_layout_box"
        and ft ~= "grug-far"
        and vim.bo[b].buftype ~= "terminal"
      then
        wins[#wins + 1] = win
      end
    end
  end
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  while #wins < index do
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[#wins])
    end
    vim.cmd.vsplit()
    wins[#wins + 1] = vim.api.nvim_get_current_win()
  end
  if wins[index] and vim.api.nvim_win_is_valid(wins[index]) then
    vim.api.nvim_set_current_win(wins[index])
  end
end

function M.setup()
  require("lazycode.project").init()
  require("lazycode.welcome").setup()
  require("lazycode.languages").setup()
  require("lazycode.terminal").setup()
  require("lazycode.editing").setup()
  require("lazycode.mouse").setup()
  require("lazycode.explorer").setup()
  require("lazycode.sidebar").setup()
  require("lazycode.menubar").setup()
  require("lazycode.font").setup()

  local editing = require("lazycode.editing")
  local project = require("lazycode.project")
  local sidebar = require("lazycode.sidebar")
  local terminal = require("lazycode.terminal")
  local map = function(modes, lhs, fn, desc)
    require("lazycode.platform").map(modes, lhs, fn, { silent = true, desc = desc })
  end
  local everywhere = { "n", "i", "x", "s", "t" }
  local editor = { "n", "i", "x", "s" }

  local function quick_open()
    if project.folder then
      Snacks.picker.files()
    else
      project.open_file()
    end
  end

  local function safe_undo()
    if vim.fn.mode():match("^[vVsS\22\19]") then
      vim.cmd("normal! \27")
    end
    if vim.bo.buftype == "prompt" then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    elseif vim.bo.modifiable and not vim.bo.readonly then
      pcall(vim.cmd, "silent! undo")
    end
  end

  local function safe_redo()
    if vim.fn.mode():match("^[vVsS\22\19]") then
      vim.cmd("normal! \27")
    end
    if vim.bo.modifiable and not vim.bo.readonly and vim.bo.buftype ~= "prompt" then
      pcall(vim.cmd, "silent! redo")
    end
  end

  -- Global Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z so Undo/Redo works everywhere (including Vim mode and
  -- inputs) and NEVER inserts literal ^Z or suspends the process.
  map({ "n", "i", "x", "s", "o" }, "<C-z>", safe_undo, "Undo")
  map("c", "<C-z>", "<Nop>", "Undo")
  map(editor, "<C-y>", safe_redo, "Redo")
  map(editor, "<C-S-z>", safe_redo, "Redo")
  map(everywhere, "<C-A-v>", editing.toggle_vim, "Toggle Vim Mode")
  map(everywhere, "<C-`>", function()
    terminal.toggle()
  end, "Terminal")
  map(everywhere, "<C-S-`>", function()
    Snacks.terminal.open(nil, { shell = terminal.shell() })
  end, "New Terminal")
  map(editor, "<C-j>", function()
    terminal.toggle()
  end, "Toggle Panel")
  map(editor, "<C-p>", quick_open, "Quick Open")
  map(editor, "<C-e>", quick_open, "Quick Open")
  map(editor, "<C-o>", project.open_file, "Open File")
  map(everywhere, "<C-k><C-o>", project.pick_folder, "Open Folder")
  local function command_palette()
    local platform = require("lazycode.platform")
    local font = require("lazycode.font")
    local welcome = require("lazycode.welcome")
    local languages = require("lazycode.languages")
    local entries = {
      {
        label = "Extensions: Install / Uninstall LSP, Linter or Formatter (Mason)...",
        run = languages.pick_mason,
      },
      {
        label = "Extensions: Manage Extensions (LazyVim Extras)",
        key = "Ctrl+Shift+X",
        run = function()
          sidebar.toggle("extensions")
        end,
      },
      {
        label = "Extensions: Enable Language Support...",
        run = function()
          languages.enable("")
        end,
      },
      {
        label = "Extensions: Open Mason Package Manager",
        run = function()
          vim.cmd("Mason")
        end,
      },
      {
        label = "Extensions: Manage / Load Plugins (Lazy)...",
        run = function()
          require("lazycode.extensions").pick_plugins()
        end,
      },
      {
        label = "Extensions: Edit Custom Plugins (lua/plugins/custom.lua)",
        run = function()
          local custom = vim.fn.stdpath("config") .. "/lua/plugins/custom.lua"
          if not (vim.uv or vim.loop).fs_stat(custom) then
            local f = io.open(custom, "w")
            if f then
              f:write(
                '-- Add any Neovim / LazyVim plugins here, save (Ctrl+S), and click Reload Window.\nreturn {\n  -- { "author/plugin.nvim", opts = {} },\n}\n'
              )
              f:close()
            end
          end
          welcome.focus_main()
          vim.cmd.edit(vim.fn.fnameescape(custom))
        end,
      },
      { label = "Developer: Reload Window", run = project.reload },
      { label = "File: New File", key = "Ctrl+N", run = project.new_file },
      { label = "File: Open File...", key = "Ctrl+O", run = project.open_file },
      { label = "File: Open Folder...", key = "Ctrl+K Ctrl+O", run = project.pick_folder },
      {
        label = "File: Save",
        key = "Ctrl+S",
        run = function()
          vim.cmd("silent! write")
        end,
      },
      {
        label = "File: Save All",
        key = "Ctrl+K S",
        run = function()
          vim.cmd("silent! wall")
        end,
      },
      { label = "File: Close Editor", key = "Ctrl+W", run = editing.close_buffer },
      {
        label = "File: Close All Editors",
        key = "Ctrl+K Ctrl+W",
        run = function()
          Snacks.bufdelete.all()
          vim.schedule(welcome.show_if_empty)
        end,
      },
      { label = "File: Reopen Closed Editor", key = "Ctrl+Shift+T", run = editing.reopen_buffer },
      {
        label = "Edit: Find in File",
        key = "Ctrl+F",
        run = function()
          Snacks.picker.lines()
        end,
      },
      {
        label = "Edit: Find in Files",
        key = "Ctrl+Shift+F",
        run = function()
          sidebar.toggle("search")
        end,
      },
      {
        label = "Edit: Format Document",
        key = "Shift+Alt+F",
        run = function()
          LazyVim.format({ force = true })
        end,
      },
      { label = "Go: Go to File...", key = "Ctrl+P", run = quick_open },
      {
        label = "Go: Go to Symbol in Editor...",
        key = "Ctrl+Shift+O",
        run = function()
          Snacks.picker.lsp_symbols()
        end,
      },
      {
        label = "Go: Go to Symbol in Workspace...",
        key = "Ctrl+T",
        run = function()
          Snacks.picker.lsp_workspace_symbols()
        end,
      },
      {
        label = "View: Toggle Explorer",
        key = "Ctrl+Shift+E",
        run = function()
          sidebar.toggle("explorer")
        end,
      },
      {
        label = "View: Toggle Source Control (Git)",
        key = "Ctrl+Shift+G",
        run = function()
          sidebar.toggle("git")
        end,
      },
      {
        label = "View: Toggle Terminal",
        key = "Ctrl+`",
        run = function()
          terminal.toggle()
        end,
      },
      {
        label = "View: Toggle Problems",
        key = "Ctrl+Shift+M",
        run = function()
          Snacks.picker.diagnostics()
        end,
      },
      {
        label = "View: Toggle Output / Notifications",
        key = "Ctrl+Shift+U",
        run = function()
          Snacks.notifier.show_history()
        end,
      },
      { label = "View: Toggle Primary Side Bar", key = "Ctrl+B", run = sidebar.toggle_sidebar },
      {
        label = "View: Split Editor",
        key = "Ctrl+\\",
        run = function()
          vim.cmd.vsplit()
        end,
      },
      {
        label = "View: Toggle Zen Mode",
        key = "Ctrl+K Z",
        run = function()
          Snacks.zen()
        end,
      },
      {
        label = "View: Zoom In",
        key = "Ctrl+=",
        run = function()
          font.set(font.current_size() + 1)
        end,
      },
      {
        label = "View: Zoom Out",
        key = "Ctrl+-",
        run = function()
          font.set(font.current_size() - 1)
        end,
      },
      {
        label = "View: Reset Zoom",
        key = "Ctrl+0",
        run = function()
          font.set(font.size)
        end,
      },
      {
        label = "Preferences: Color Theme",
        key = "Ctrl+K Ctrl+T",
        run = function()
          Snacks.picker.colorschemes()
        end,
      },
      {
        label = "Preferences: Open Keyboard Shortcuts",
        key = "Ctrl+K Ctrl+S",
        run = function()
          Snacks.picker.keymaps()
        end,
      },
      {
        label = "Python: Select Type Checking Mode (off / basic / standard / strict)",
        run = function()
          vim.ui.select({ "off", "basic", "standard", "strict" }, {
            prompt = "Python Type Checking Mode",
          }, function(mode)
            if not mode then
              return
            end
            for _, client in ipairs(vim.lsp.get_clients({ name = "pyright" })) do
              client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
                python = { analysis = { typeCheckingMode = mode } },
              })
              client:notify("workspace/didChangeConfiguration", { settings = client.settings })
            end
            vim.notify("Python type checking: " .. mode, vim.log.levels.INFO, { title = "Python" })
          end)
        end,
      },
      { label = "Preferences: Toggle Vim Mode", key = "Ctrl+Alt+V", run = editing.toggle_vim },
      { label = "Git: Clone Repository...", run = project.clone },
    }
    if vim.fn.exists(":ClaudeCode") == 2 then
      local claude_entries = {
        {
          label = "Claude Code: Open / Toggle",
          key = "Ctrl+Alt+C",
          run = function()
            vim.cmd("ClaudeCode")
          end,
        },
        {
          label = "Claude Code: Send Selection or Current File",
          key = "Ctrl+Alt+S",
          run = M.send_to_claude,
        },
        {
          label = "Claude Code: Focus",
          run = function()
            vim.cmd("ClaudeCodeFocus")
          end,
        },
        {
          label = "Claude Code: Resume Conversation",
          run = function()
            vim.cmd("ClaudeCode --resume")
          end,
        },
        {
          label = "Claude Code: Continue Last Conversation",
          run = function()
            vim.cmd("ClaudeCode --continue")
          end,
        },
        {
          label = "Claude Code: Add Current File",
          run = function()
            vim.cmd("ClaudeCodeAdd %")
          end,
        },
        {
          label = "Claude Code: Accept Diff",
          run = function()
            vim.cmd("ClaudeCodeDiffAccept")
          end,
        },
        {
          label = "Claude Code: Deny Diff",
          run = function()
            vim.cmd("ClaudeCodeDiffDeny")
          end,
        },
      }
      for i = #claude_entries, 1, -1 do
        table.insert(entries, 1, claude_entries[i])
      end
    end
    local items = {}
    for _, e in ipairs(entries) do
      local key = e.key and platform.label(e.key) or nil
      items[#items + 1] = {
        text = e.label .. (key and (" " .. key) or ""),
        label = e.label,
        key = key,
        run = e.run,
      }
    end
    -- Include all active plugin/user commands brightly below the curated IDE commands.
    local cmds = vim.api.nvim_get_commands({})
    local names = vim.tbl_keys(cmds)
    table.sort(names)
    for _, name in ipairs(names) do
      local def = cmds[name]
      items[#items + 1] = {
        text = name .. " :" .. name .. " " .. (def.definition or ""),
        label = name,
        desc = def.definition,
        cmd = name,
        nargs = def.nargs,
      }
    end
    Snacks.picker({
      source = "lazycode_palette",
      title = "Command Palette",
      items = items,
      layout = { preset = "vscode" },
      matcher = { sort_empty = false },
      format = function(item)
        local ret = { { item.label, "SnacksPickerFile" } }
        if item.key then
          ret[#ret + 1] = { "  " .. item.key, "SnacksPickerSpecial" }
        elseif item.desc and item.desc ~= "" then
          ret[#ret + 1] = { "  " .. item.desc, "Comment" }
        end
        return ret
      end,
      confirm = function(picker, item)
        if not item then
          return picker:close()
        end
        picker:norm(function()
          picker:close()
          vim.schedule(function()
            if item.run then
              item.run()
            elseif item.cmd == "Lazy" then
              require("lazycode.extensions").pick_plugins()
            elseif item.cmd == "MasonInstall" or item.cmd == "MasonUninstall" then
              languages.pick_mason()
            elseif item.nargs == "1" or item.nargs == "+" then
              Snacks.input({ prompt = item.cmd .. " " }, function(arg)
                if arg and vim.trim(arg) ~= "" then
                  local ok, err = pcall(vim.cmd, item.cmd .. " " .. arg)
                  if not ok then
                    vim.notify(tostring(err), vim.log.levels.ERROR, { title = item.cmd })
                  end
                end
              end)
            elseif item.cmd then
              local ok, err = pcall(vim.cmd, item.cmd)
              if not ok then
                vim.notify(tostring(err), vim.log.levels.ERROR, { title = item.cmd })
              end
            end
          end)
        end)
      end,
    })
  end

  map(everywhere, "<C-S-p>", command_palette, "Command Palette")
  map(everywhere, "<F1>", command_palette, "Command Palette")
  map(editor, "<C-S-h>", function()
    sidebar.open_search(editing.consume_selection())
  end, "Replace in Files")
  map(editor, "<C-S-m>", function()
    Snacks.picker.diagnostics()
  end, "Problems")
  map(editor, "<C-S-u>", function()
    Snacks.notifier.show_history()
  end, "Output")
  map(editor, "<C-n>", project.new_file, "New File")
  map(editor, "<C-w>", editing.close_buffer, "Close Tab")
  map(editor, "<C-F4>", editing.close_buffer, "Close Tab")
  map(everywhere, "<C-q>", "<Cmd>confirm qa<CR>", "Close Window")
  map(everywhere, "<C-S-w>", "<Cmd>confirm qa<CR>", "Close Window")
  map(editor, "<C-S-t>", editing.reopen_buffer, "Reopen Tab")
  map(editor, "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", "Next Tab")
  map(editor, "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", "Previous Tab")
  map(editor, "<C-PageDown>", "<Cmd>BufferLineCycleNext<CR>", "Next Tab")
  map(editor, "<C-PageUp>", "<Cmd>BufferLineCyclePrev<CR>", "Previous Tab")
  map(editor, "<C-S-PageDown>", "<Cmd>BufferLineMoveNext<CR>", "Move Tab Right")
  map(editor, "<C-S-PageUp>", "<Cmd>BufferLineMovePrev<CR>", "Move Tab Left")
  map(editor, "<C-\\>", "<Cmd>vsplit<CR>", "Split Editor")
  for i = 1, 3 do
    map(editor, "<C-" .. i .. ">", function()
      focus_group(i)
    end, "Focus Editor Group " .. i)
  end
  for i = 1, 9 do
    map(editor, "<A-" .. i .. ">", "<Cmd>BufferLineGoToBuffer " .. i .. "<CR>", "Go to Tab " .. i)
  end
  map(everywhere, "<C-k><C-s>", function()
    Snacks.picker.keymaps()
  end, "Keyboard Shortcuts")
  map(editor, "<C-S-s>", function()
    vim.ui.input({ prompt = "Save As", default = vim.fn.expand("%:p"), completion = "file" }, function(path)
      if path and path ~= "" then
        vim.cmd.saveas(vim.fn.fnameescape(path))
      end
    end)
  end, "Save As")
  map(editor, "<C-k>s", "<Cmd>wall<CR>", "Save All")
  map(editor, "<C-k><C-w>", function()
    Snacks.bufdelete.all()
    vim.schedule(function()
      require("lazycode.welcome").show_if_empty()
    end)
  end, "Close All Tabs")
  map(editor, "<C-k>p", function()
    local p = vim.fn.expand("%:p")
    if p ~= "" then
      vim.fn.setreg("+", p)
    end
  end, "Copy Path of Active File")
  map(editor, "<C-k>r", function()
    local p = vim.fn.expand("%:p:h")
    if p ~= "" then
      vim.ui.open(p)
    end
  end, "Reveal Active File")
  map(editor, "<C-t>", function()
    Snacks.picker.lsp_workspace_symbols()
  end, "Go to Symbol in Workspace")
  map(editor, "<C-k>z", function()
    Snacks.zen()
  end, "Zen Mode")
  map(editor, "<C-k><C-t>", function()
    Snacks.picker.colorschemes()
  end, "Color Theme")
  map(editor, "<C-k>m", function()
    vim.ui.select(vim.fn.getcompletion("", "filetype"), { prompt = "Language Mode" }, function(ft)
      if ft then
        vim.bo.filetype = ft
      end
    end)
  end, "Change Language Mode")
  map(everywhere, "<C-A-c>", function()
    pcall(function()
      require("lazy").load({ plugins = { "claudecode.nvim" } })
    end)
    if vim.fn.exists(":ClaudeCode") == 2 then
      vim.cmd("ClaudeCode")
    else
      vim.notify(
        "Enable ai.claudecode in Extensions (Ctrl+Shift+X) first.",
        vim.log.levels.INFO,
        { title = "Claude Code" }
      )
    end
  end, "Toggle Claude Code")
  map(editor, "<C-A-s>", M.send_to_claude, "Send to Claude Code")
  require("lazycode.platform").keep_shortcuts()
  -- Auto-load installed plugins after startup so extras whose LazyVim specs only had <leader>
  -- keys (like claudecode.nvim) are immediately active without manual loading on every restart.
  vim.defer_fn(function()
    local names = {}
    for _, p in ipairs(require("lazy").plugins()) do
      if p.enabled ~= false and p._.installed and not p._.loaded and p.name ~= "catppuccin" then
        names[#names + 1] = p.name
      end
    end
    if #names > 0 then
      pcall(require("lazy").load, { plugins = names })
      require("lazycode.platform").keep_shortcuts()
    end
  end, 80)
  -- Replace the modal :Lazy window (when run interactively without subcommands) with the VS Code picker.
  if #vim.api.nvim_list_uis() > 0 then
    pcall(vim.api.nvim_create_user_command, "Lazy", function(args)
      if vim.trim(args.args or "") == "" then
        require("lazycode.extensions").pick_plugins()
      else
        require("lazy.view.commands").cmd(args.args, { bang = args.bang })
      end
    end, {
      bang = true,
      nargs = "*",
      desc = "Manage and load Lazy plugins",
      complete = function(_, line)
        return require("lazy.view.commands").complete("", line)
      end,
    })
  end
end

return M
