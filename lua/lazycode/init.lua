local M = {}

function M.setup()
  require("lazycode.project").init()
  require("lazycode.welcome").setup()
  require("lazycode.languages").setup()
  require("lazycode.terminal").setup()
  require("lazycode.editing").setup()
  require("lazycode.mouse").setup()
  require("lazycode.explorer").setup()
  require("lazycode.sidebar").setup()
  require("lazycode.font").setup()

  local editing = require("lazycode.editing")
  local project = require("lazycode.project")
  local map = function(modes, lhs, fn, desc)
    require("lazycode.platform").map(modes, lhs, fn, { silent = true, desc = desc })
  end
  local everywhere = { "n", "i", "x", "s", "t" }
  local editor = { "n", "i", "x", "s" }

  -- Keeps Ctrl+Z from suspending the editor outside text areas.
  map({ "n", "x", "s", "o" }, "<C-z>", "<Nop>", "Undo")
  map(everywhere, "<C-A-v>", editing.toggle_vim, "Toggle Vim Mode")
  local terminal = require("lazycode.terminal")
  map(everywhere, "<C-`>", function()
    terminal.toggle()
  end, "Terminal")
  map(editor, "<C-j>", function()
    terminal.toggle()
  end, "Toggle Panel")
  map(editor, "<C-p>", function()
    if project.folder then
      Snacks.picker.files()
    else
      project.open_file()
    end
  end, "Quick Open")
  map(editor, "<C-o>", project.open_file, "Open File")
  map(everywhere, "<C-k><C-o>", project.pick_folder, "Open Folder")
  map(everywhere, "<C-S-p>", function()
    Snacks.picker.commands()
  end, "Command Palette")
  map(editor, "<C-S-h>", function()
    require("grug-far").open()
  end, "Replace in Files")
  map(editor, "<C-S-m>", function()
    Snacks.picker.diagnostics()
  end, "Problems")
  map(editor, "<C-n>", project.new_file, "New File")
  map(editor, "<C-w>", editing.close_buffer, "Close Tab")
  map(editor, "<C-S-t>", editing.reopen_buffer, "Reopen Tab")
  map(editor, "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", "Next Tab")
  map(editor, "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", "Previous Tab")
  map(editor, "<C-\\>", "<Cmd>vsplit<CR>", "Split Editor")
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
  end, "Close All Tabs")
  map(everywhere, "<F1>", function()
    Snacks.picker.commands()
  end, "Command Palette")
  map(editor, "<C-t>", function()
    Snacks.picker.lsp_workspace_symbols()
  end, "Go to Symbol in Workspace")
  map(editor, "<C-PageDown>", "<Cmd>BufferLineCycleNext<CR>", "Next Tab")
  map(editor, "<C-PageUp>", "<Cmd>BufferLineCyclePrev<CR>", "Previous Tab")
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
  require("lazycode.platform").keep_shortcuts()
end

return M
