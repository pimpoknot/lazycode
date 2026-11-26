return {
  {
    "brenton-leighton/multiple-cursors.nvim",
    version = "*",
    lazy = false,
    opts = {
      pre_hook = function()
        require("lazycode.editing").mc_enter()
      end,
      post_hook = function()
        require("lazycode.editing").mc_leave()
      end,
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        cssls = {},
        html = {},
      },
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      -- No suggestions in name prompts or the Search panel: Enter confirms and Esc cancels right away.
      enabled = function()
        local ft = vim.bo.filetype
        return vim.bo.buftype ~= "prompt" and vim.b.completion ~= false and ft ~= "snacks_input" and ft ~= "grug-far"
      end,
      keymap = {
        preset = "enter",
        -- Like VS Code: Tab also accepts the Copilot suggestion shown in gray.
        ["<Tab>"] = {
          "select_and_accept",
          function()
            return LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" })()
          end,
          "fallback",
        },
        ["<C-p>"] = false,
        ["<C-n>"] = false,
        ["<C-k>"] = false,
        ["<C-y>"] = false,
        ["<C-b>"] = false,
        ["<C-f>"] = false,
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      },
    },
  },
  -- noice fails on the restart event of Reload Window, and an IDE needs no command line popup.
  -- Notifications still come from Snacks.
  { "folke/noice.nvim", enabled = false },
  {
    "folke/snacks.nvim",
    opts = {
      -- The start screen is the LazyCode Welcome tab.
      dashboard = { enabled = false },
      -- The LazyCode window scrolls by pixels; Snacks would move the text a line at a time.
      scroll = { enabled = false },
      -- Like VS Code, a single Esc cancels text prompts.
      styles = {
        -- The terminal keeps every key for the shell.
        terminal = {
          keys = { q = false, gf = false, term_normal = false },
        },
        input = {
          keys = {
            i_esc = { "<esc>", "cancel", mode = "i" },
          },
        },
      },
      picker = {
        actions = {
          lazycode_rename = function()
            require("lazycode.explorer").key("rename")
          end,
          lazycode_delete = function()
            require("lazycode.explorer").key("delete")
          end,
          lazycode_copy = function()
            require("lazycode.explorer").key("copy")
          end,
          lazycode_cut = function()
            require("lazycode.explorer").key("cut")
          end,
          lazycode_paste = function()
            require("lazycode.explorer").key("paste")
          end,
          lazycode_click = function(picker)
            local pos = vim.fn.getmousepos()
            if pos.winid ~= picker.list.win.win or pos.line < 1 then
              return
            end
            local idx = picker.list:row2idx(pos.line)
            local item = idx and picker.list:get(idx)
            if item then
              picker.list:move(idx, true)
              picker:action("confirm")
            end
          end,
        },
        sources = {
          explorer = {
            -- Like VS Code: show hidden and ignored files, and hide only VCS metadata.
            hidden = true,
            ignored = true,
            exclude = { "**/.git", "**/.svn", "**/.hg", "**/.DS_Store", "**/Thumbs.db" },
            -- Hidden files keep the normal color; only ignored files are dimmed.
            transform = function(item)
              item.filename_hl = item.dir and "SnacksPickerDirectory" or "SnacksPickerFile"
              return item
            end,
            layout = { layout = { width = 46 } },
            win = {
              list = {
                keys = require("lazycode.platform").picker_keys({
                  ["<2-LeftMouse>"] = false,
                  ["<LeftRelease>"] = "lazycode_click",
                  ["<F2>"] = "lazycode_rename",
                  ["<Del>"] = "lazycode_delete",
                  ["<C-c>"] = "lazycode_copy",
                  ["<C-x>"] = "lazycode_cut",
                  ["<C-v>"] = "lazycode_paste",
                  ["<Esc>"] = false,
                  ["q"] = false,
                }),
              },
            },
          },
        },
      },
    },
  },
  {
    "MagicDuck/grug-far.nvim",
    opts = {
      -- Like VS Code: a lowercase search ignores case, and Ctrl+Alt+Enter replaces all.
      extraRgArgs = "--smart-case",
      debounceMs = 250,
      helpLine = { enabled = false },
      showEngineInfo = false,
      showInputsTopPadding = false,
      engines = {
        ripgrep = {
          placeholders = {
            search = "Search the project",
            replacement = "Replace with (Ctrl+Alt+Enter: all)",
            filesFilter = "Files to include: *.ts  src/**",
            flags = "-s match case  -w word  -F plain",
            paths = "Folders (default: the project)",
          },
        },
      },
      keymaps = { replace = { n = "<localleader>r", i = "<C-M-CR>" } },
    },
  },
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.always_show_bufferline = true
      opts.options.offsets = opts.options.offsets or {}
      -- bufferline only measures the first column, so the bar's offset grows by the open panel.
      local bar = setmetatable({ filetype = "lazycode_bar" }, {
        __index = function(_, key)
          if key == "padding" then
            return require("lazycode.sidebar").panel_columns()
          end
        end,
      })
      table.insert(opts.options.offsets, 1, bar)
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function editing()
        return require("lazycode.editing")
      end
      opts.sections.lualine_a = {
        {
          function()
            return editing().vim_mode and "VIM" or "CODE"
          end,
          on_click = function()
            editing().toggle_vim()
          end,
        },
      }
      opts.sections.lualine_b = {
        {
          "branch",
          on_click = function()
            require("lazycode.sidebar").toggle("git")
          end,
        },
      }
      table.insert(opts.sections.lualine_y, 1, {
        function()
          return "󰌌 " .. (vim.bo.filetype ~= "" and vim.bo.filetype or "text")
        end,
        on_click = function()
          Snacks.picker.keymaps()
        end,
      })
    end,
  },
}
