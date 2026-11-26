-- Default language tooling, and on-demand support for other languages.
local M = {}

--- Installed with LazyCode so completion works out of the box.
M.tools = {
  "bash-language-server",
  "copilot-language-server",
  "css-lsp",
  "docker-compose-language-service",
  "dockerfile-language-server",
  "eslint-lsp",
  "hadolint",
  "html-lsp",
  "json-lsp",
  "lua-language-server",
  "markdown-toc",
  "markdownlint-cli2",
  "marksman",
  "prettier",
  "pyright",
  "ruff",
  "shfmt",
  "stylua",
  "tailwindcss-language-server",
  "taplo",
  "vtsls",
  "yaml-language-server",
}

-- filetype = { extra, display name, required toolchain }
local OPTIONAL = {
  go = { "lang.go", "Go", "go" },
  php = { "lang.php", "PHP", "php" },
  java = { "lang.java", "Java", "java" },
  ruby = { "lang.ruby", "Ruby", "ruby" },
  kotlin = { "lang.kotlin", "Kotlin", "java" },
  zig = { "lang.zig", "Zig", "zig" },
  elixir = { "lang.elixir", "Elixir", "elixir" },
  c = { "lang.clangd", "C/C++" },
  cpp = { "lang.clangd", "C/C++" },
  cs = { "lang.dotnet", "C#", "dotnet" },
  sql = { "lang.sql", "SQL" },
  terraform = { "lang.terraform", "Terraform", "terraform" },
  vue = { "lang.vue", "Vue" },
  svelte = { "lang.svelte", "Svelte" },
  astro = { "lang.astro", "Astro" },
  prisma = { "lang.prisma", "Prisma" },
}

local offered = {}

local function extra_name(extra)
  return "lazyvim.plugins.extras." .. extra
end

local function enabled(extra)
  return vim.tbl_contains(LazyVim.config.json.data.extras or {}, extra_name(extra))
end

local function offer(ft)
  local lang = OPTIONAL[ft]
  if not lang or offered[lang[1]] or enabled(lang[1]) then
    return
  end
  if lang[3] and vim.fn.executable(lang[3]) == 0 then
    return
  end
  offered[lang[1]] = true
  vim.notify(
    ("Completion for %s is available.\nRun :LazyCodeLanguage %s to install it."):format(lang[2], ft),
    vim.log.levels.INFO,
    { title = "LazyCode" }
  )
end

function M.enable(ft)
  if not ft or ft == "" then
    local items = vim.tbl_keys(OPTIONAL)
    table.sort(items)
    return vim.ui.select(items, {
      prompt = "Enable Language Support",
      format_item = function(k)
        return ("%s (%s)%s"):format(OPTIONAL[k][2], k, enabled(OPTIONAL[k][1]) and "  ● enabled" or "")
      end,
    }, function(choice)
      if choice then
        M.enable(choice)
      end
    end)
  end
  local lang = OPTIONAL[ft]
  if not lang then
    return vim.notify("No optional language for: " .. tostring(ft), vim.log.levels.WARN, { title = "LazyCode" })
  end
  if enabled(lang[1]) then
    return vim.notify(lang[2] .. " is already enabled", vim.log.levels.INFO, { title = "LazyCode" })
  end
  local data = LazyVim.config.json.data
  data.extras = data.extras or {}
  table.insert(data.extras, extra_name(lang[1]))
  LazyVim.json.save()
  vim.notify(lang[2] .. " enabled. Restart LazyCode to finish installing.", vim.log.levels.INFO, { title = "LazyCode" })
end

--- Waits for the parser install LazyVim starts on load, and returns the parsers still missing.
local function install_parsers()
  require("lazy").load({ plugins = { "nvim-treesitter" } })
  local wanted = LazyVim.opts("nvim-treesitter").ensure_installed
  local function missing()
    local installed = require("nvim-treesitter").get_installed("parsers")
    return vim.tbl_filter(function(lang)
      return not vim.list_contains(installed, lang)
    end, wanted)
  end
  local left, progress = #missing(), vim.uv.hrtime()
  -- shortcut: LazyVim exposes no install handle, so a 2 minute stall counts as failure; use the handle if it adds one.
  vim.wait(900000, function()
    local now = #missing()
    if now < left then
      left, progress = now, vim.uv.hrtime()
    end
    return left == 0 or vim.uv.hrtime() - progress > 120e9
  end, 200)
  -- Queries are linked right after the parser is copied, so let the last one finish.
  vim.wait(1000)
  return missing()
end

--- Blocking install used by the installer: nvim --headless +LazyCodeInstallTools +qa
function M.install_tools()
  require("lazy").load({ plugins = { "mason.nvim" } })
  local registry = require("mason-registry")
  local done = false
  registry.refresh(function()
    done = true
  end)
  vim.wait(120000, function()
    return done
  end, 100)
  local packages, failed = {}, {}
  for _, name in ipairs(M.tools) do
    local ok, pkg = pcall(registry.get_package, name)
    if ok then
      packages[#packages + 1] = pkg
      -- The LazyVim Mason setup may already be installing some of them.
      if not pkg:is_installed() and not pkg:is_installing() then
        pcall(pkg.install, pkg)
      end
    else
      failed[#failed + 1] = name
    end
  end
  vim.wait(900000, function()
    for _, pkg in ipairs(packages) do
      if pkg:is_installing() then
        return false
      end
    end
    return true
  end, 200)
  for _, pkg in ipairs(packages) do
    if not pkg:is_installed() then
      failed[#failed + 1] = pkg.name
    end
  end
  vim.list_extend(failed, install_parsers())
  if #failed > 0 then
    io.stderr:write("LazyCode: failed to install: " .. table.concat(failed, ", ") .. "\n")
    vim.cmd("cquit 1")
  end
end

--- Interactive picker for installing or removing individual Mason packages (Ctrl+Shift+P -> MasonInstall).
function M.pick_mason()
  require("lazy").load({ plugins = { "mason.nvim" } })
  local registry = require("mason-registry")
  local function open_picker()
    local specs = registry.get_all_package_specs()
    table.sort(specs, function(a, b)
      return a.name < b.name
    end)
    local items = {}
    for _, spec in ipairs(specs) do
      local ok, pkg = pcall(registry.get_package, spec.name)
      if ok then
        local desc = (spec.description or ""):gsub("%s+", " ")
        items[#items + 1] = {
          text = spec.name .. " " .. desc,
          pkg = pkg,
          desc = desc,
        }
      end
    end
    Snacks.picker({
      source = "lazycode_mason",
      title = "Mason Packages (Enter/Click: install or uninstall)",
      items = items,
      layout = { preset = "vscode" },
      format = function(item)
        local on = item.pkg:is_installed()
        local busy = item.pkg:is_installing()
        local icon = busy and "◌ " or on and "● " or "○ "
        local hl = busy and "DiagnosticWarn" or on and "DiagnosticOk" or "Comment"
        return {
          { icon, hl },
          { item.pkg.name, "SnacksPickerFile" },
          { "  " .. item.desc, "Comment" },
        }
      end,
      confirm = function(picker, item)
        if not item then
          return
        end
        picker:close()
        local pkg = item.pkg
        if pkg:is_installed() then
          pkg:uninstall()
          vim.notify("Uninstalled " .. pkg.name, vim.log.levels.INFO, { title = "Mason" })
        elseif not pkg:is_installing() then
          vim.notify("Installing " .. pkg.name .. "...", vim.log.levels.INFO, { title = "Mason" })
          pkg:install():once(
            "closed",
            vim.schedule_wrap(function()
              if pkg:is_installed() then
                vim.notify(pkg.name .. " installed.", vim.log.levels.INFO, { title = "Mason" })
              else
                vim.notify("Failed to install " .. pkg.name, vim.log.levels.ERROR, { title = "Mason" })
              end
            end)
          )
        end
      end,
    })
  end
  if #registry.get_all_package_names() == 0 then
    registry.refresh(vim.schedule_wrap(open_picker))
  else
    open_picker()
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("lazycode_languages", { clear = true }),
    callback = function(ev)
      vim.schedule(function()
        offer(ev.match)
      end)
    end,
  })
end

return M
