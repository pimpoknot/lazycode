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
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      -- Clear LazyVim's Vim LSP bindings (gd, gr, K, <leader>c*, <c-k>...); LazyCode sets VS Code's.
      opts.servers["*"] = vim.tbl_deep_extend("force", opts.servers["*"] or {}, { keys = {} })
      opts.servers["*"].keys = {}
      opts.servers.bashls = opts.servers.bashls or {}
      opts.servers.cssls = opts.servers.cssls or {}
      opts.servers.html = opts.servers.html or {}
      -- Match VS Code / Pylance default: report real syntax/import/undefined issues via Ruff + Pyright,
      -- without noisy static type errors ("Operator '+' not supported...") unless configured in the project.
      opts.servers.pyright = vim.tbl_deep_extend("force", opts.servers.pyright or {}, {
        settings = {
          python = {
            analysis = {
              typeCheckingMode = "off",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
            },
          },
        },
      })
      -- Skip Mason auto-installs where Mason has no binary for the platform or lacks the SDK.
      if vim.fn.has("linux") == 1 and (vim.uv.os_uname().machine or ""):find("aarch64") then
        opts.servers.clangd = vim.tbl_deep_extend("force", opts.servers.clangd or {}, { mason = false })
      end
      local tool_for_server = {
        omnisharp = "dotnet",
        fsautocomplete = "dotnet",
        csharp_ls = "dotnet",
        gopls = "go",
        intelephense = "php",
        phpactor = "php",
        solargraph = "ruby",
        ruby_lsp = "ruby",
        elixirls = "elixir",
      }
      for srv, bin in pairs(tool_for_server) do
        if opts.servers[srv] and vim.fn.executable(bin) == 0 then
          opts.servers[srv].mason = false
          opts.servers[srv].enabled = false
        end
      end
    end,
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
  -- Disable LazyVim UI/navigation plugins that expose Vim-only controls or fail on Reload Window.
  { "folke/noice.nvim", enabled = false },
  { "folke/which-key.nvim", enabled = false },
  { "folke/flash.nvim", enabled = false },
  {
    "folke/trouble.nvim",
    keys = function()
      return {}
    end,
  },
  {
    "folke/todo-comments.nvim",
    keys = function()
      return {}
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      on_attach = function() end,
    },
  },
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUpdate", "MasonLog" },
    keys = function()
      return {}
    end,
    opts = function(_, opts)
      opts.ui = vim.tbl_deep_extend("force", opts.ui or {}, {
        keymaps = {
          install_package = "<CR>",
          toggle_package_expand = "<Tab>",
          uninstall_package = "<Del>",
        },
      })
      local skip = {
        clangd = vim.fn.has("linux") == 1 and (vim.uv.os_uname().machine or ""):find("aarch64") ~= nil,
        csharpier = vim.fn.executable("dotnet") == 0,
        fantomas = vim.fn.executable("dotnet") == 0,
        netcoredbg = vim.fn.executable("dotnet") == 0,
        omnisharp = vim.fn.executable("dotnet") == 0,
        fsautocomplete = vim.fn.executable("dotnet") == 0,
        gofumpt = vim.fn.executable("go") == 0,
        goimports = vim.fn.executable("go") == 0,
        delve = vim.fn.executable("go") == 0,
      }
      opts.ensure_installed = vim.tbl_filter(function(pkg)
        return not skip[pkg]
      end, opts.ensure_installed or {})
    end,
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lazycode_mason_ui", { clear = true }),
        pattern = { "mason", "lazy" },
        callback = function(ev)
          vim.keymap.set("n", "<Esc>", "<Cmd>close<CR>", { buffer = ev.buf, silent = true, nowait = true })
        end,
      })
    end,
  },
  {
    "folke/snacks.nvim",
    keys = function()
      return {}
    end,
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
          lazycode_paste_input = function()
            local text = (vim.fn.getreg("+") or ""):gsub("[\r\n]+", " ")
            if text ~= "" then
              vim.api.nvim_put({ text }, "c", false, true)
            end
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
            elseif
              picker.opts.auto_close ~= false
              and picker.input
              and picker.input.win
              and picker.input.win:valid()
            then
              vim.api.nvim_set_current_win(picker.input.win.win)
            end
          end,
        },
        win = {
          input = {
            keys = require("lazycode.platform").picker_keys({
              ["<Esc>"] = { "cancel", mode = { "n", "i" } },
              ["<CR>"] = { "confirm", mode = { "n", "i" } },
              ["<Down>"] = { "list_down", mode = { "n", "i" } },
              ["<Up>"] = { "list_up", mode = { "n", "i" } },
              ["<F3>"] = { "list_down", mode = { "n", "i" } },
              ["<S-F3>"] = { "list_up", mode = { "n", "i" } },
              ["<PageDown>"] = { "list_scroll_down", mode = { "n", "i" } },
              ["<PageUp>"] = { "list_scroll_up", mode = { "n", "i" } },
              ["<C-v>"] = { "lazycode_paste_input", mode = { "n", "i" } },
              ["<C-BS>"] = { "<c-s-w>", mode = "i", expr = true },
              ["<C-w>"] = { "cancel", mode = { "n", "i" } },
              ["<c-w>H"] = false,
              ["<c-w>J"] = false,
              ["<c-w>K"] = false,
              ["<c-w>L"] = false,
              ["<c-f>"] = false,
              ["<c-s>"] = false,
              ["<c-a>"] = false,
              ["<c-b>"] = false,
              ["<c-d>"] = false,
              ["<c-u>"] = false,
              ["<c-g>"] = false,
              ["<c-q>"] = false,
              ["<c-t>"] = false,
              ["<c-j>"] = false,
              ["<c-k>"] = false,
              ["<c-n>"] = false,
              ["<c-p>"] = false,
              ["/"] = false,
              ["?"] = false,
              ["q"] = false,
              ["j"] = false,
              ["k"] = false,
              ["G"] = false,
              ["gg"] = false,
            }),
          },
          list = {
            keys = require("lazycode.platform").picker_keys({
              ["<2-LeftMouse>"] = false,
              ["<LeftRelease>"] = "lazycode_click",
              ["<Esc>"] = "cancel",
              ["<F3>"] = "list_down",
              ["<S-F3>"] = "list_up",
              ["q"] = false,
            }),
          },
          preview = {
            keys = {
              ["<Esc>"] = "cancel",
              ["q"] = false,
            },
          },
        },
        sources = {
          commands = {
            layout = { preset = "vscode" },
            confirm = function(picker, item)
              if not (item and item.cmd) then
                return picker:close()
              end
              local cmd = item.cmd
              local nargs = item.command and item.command.nargs or "0"
              picker:norm(function()
                picker:close()
                vim.schedule(function()
                  if cmd == "MasonInstall" or cmd == "MasonUninstall" then
                    require("lazycode.languages").pick_mason()
                  elseif nargs == "1" or nargs == "+" then
                    Snacks.input({ prompt = cmd .. " " }, function(arg)
                      if arg and vim.trim(arg) ~= "" then
                        local ok, err = pcall(vim.cmd, cmd .. " " .. arg)
                        if not ok then
                          vim.notify(tostring(err), vim.log.levels.ERROR, { title = cmd })
                        end
                      end
                    end)
                  else
                    local ok, err = pcall(vim.cmd, cmd)
                    if not ok then
                      vim.notify(tostring(err), vim.log.levels.ERROR, { title = cmd })
                    end
                  end
                end)
              end)
            end,
          },
          lines = {
            layout = { preset = "vscode", preview = "main" },
            jump = { match = true },
            confirm = function(picker, item, action)
              local pat = picker.input and picker.input:get() or ""
              if pat ~= "" then
                vim.fn.setreg("/", "\\V" .. vim.fn.escape(pat, "\\"))
              end
              return Snacks.picker.actions.jump(picker, item, action)
            end,
          },
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
    keys = function()
      return {}
    end,
    opts = {
      -- Like VS Code: a lowercase search ignores case, Tab moves fields, and Ctrl+Alt+Enter replaces all.
      extraRgArgs = "--smart-case",
      debounceMs = 250,
      helpLine = { enabled = false },
      showEngineInfo = false,
      showInputsTopPadding = false,
      engines = {
        ripgrep = {
          placeholders = {
            search = "Search",
            replacement = "Replace with (Ctrl+Alt+Enter: all)",
            filesFilter = "Files to include: *.ts  src/**",
            flags = "-s match case  -w word  -F plain",
            paths = "Folders (default: the project)",
          },
        },
      },
      keymaps = {
        replace = { n = "<C-M-CR>", i = "<C-M-CR>" },
        nextInput = { n = "<Tab>", i = "<Tab>" },
        prevInput = { n = "<S-Tab>", i = "<S-Tab>" },
        gotoLocation = { n = "<CR>" },
        close = { n = "<Esc>" },
      },
    },
  },
  {
    "akinsho/bufferline.nvim",
    keys = function()
      return {}
    end,
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.always_show_bufferline = true
      opts.options.offsets = {}
      opts.options.custom_areas = opts.options.custom_areas or {}
      opts.options.custom_areas.left = function()
        return require("lazycode.menubar").segments()
      end
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
