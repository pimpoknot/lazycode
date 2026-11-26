-- Extensions panel: the LazyVim extras as a searchable list. A click turns one on or off.
local M = {}
local touched = {} ---@type table<string, table> extras changed since start, by module

local X = "lazyvim.plugins.extras."
-- Extras that break LazyCode's own features, with the reason shown when someone turns one on.
local BLOCKED = {
  [X .. "ai.copilot"] = "Copilot already comes with LazyCode (ai.copilot-native).",
  [X .. "coding.nvim-cmp"] = "LazyCode's completion and shortcuts are built on blink.cmp.",
  [X .. "dap.nlua"] = "Turn on dap.core first: dap.nlua needs its setup.",
  [X .. "editor.fzf"] = "LazyCode's pickers and shortcuts are built on Snacks.",
  [X .. "editor.neo-tree"] = "LazyCode's Explorer is the Snacks explorer.",
  [X .. "editor.telescope"] = "LazyCode's pickers and shortcuts are built on Snacks.",
  [X .. "ui.alpha"] = "LazyCode opens on its own Welcome tab.",
  [X .. "ui.dashboard-nvim"] = "LazyCode opens on its own Welcome tab.",
  [X .. "ui.mini-starter"] = "LazyCode opens on its own Welcome tab.",
}
M.BLOCKED = BLOCKED
-- Only one extra of each group can be on: they replace the same piece.
local ONE_OF = { { X .. "coding.luasnip", X .. "coding.mini-snippets" } }

--- Removes incompatible extras from lazyvim.json before LazyVim loads them.
function M.sanitize(path)
  path = path or (vim.fn.stdpath("config") .. "/lazyvim.json")
  local fd = io.open(path, "r")
  if not fd then
    return
  end
  local raw = fd:read("*a")
  fd:close()
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" or type(data.extras) ~= "table" then
    return
  end
  local has_dap_core = vim.list_contains(data.extras, X .. "dap.core")
  local seen_group = {}
  local kept, changed = {}, false
  for _, mod in ipairs(data.extras) do
    local blocked = BLOCKED[mod] ~= nil and not (mod == X .. "dap.nlua" and has_dap_core)
    local conflict = false
    for idx, group in ipairs(ONE_OF) do
      if vim.list_contains(group, mod) then
        if seen_group[idx] then
          conflict = true
        else
          seen_group[idx] = true
        end
      end
    end
    if blocked or conflict then
      changed = true
    else
      kept[#kept + 1] = mod
    end
  end
  if changed then
    data.extras = kept
    local out = io.open(path, "w")
    if out then
      out:write(vim.json.encode(data))
      out:close()
    end
  end
end

local function json()
  local data = LazyVim.config.json.data
  data.extras = data.extras or {}
  return data
end

--- On after the next restart: chosen here, or imported by LazyCode itself.
local function wanted(extra)
  return extra.managed and vim.list_contains(json().extras, extra.module) or (not extra.managed and extra.enabled)
end

--- True while a change made here waits for Reload Window.
function M.pending()
  for _, extra in pairs(touched) do
    if wanted(extra) ~= extra.enabled then
      return true
    end
  end
  return false
end

function M.toggle(extra)
  if not extra.managed then
    return LazyVim.warn(extra.name .. " comes with LazyCode and cannot be turned off here.", { title = "Extensions" })
  end
  local data, on = json(), not wanted(extra)
  if
    on
    and BLOCKED[extra.module]
    and not (extra.module == X .. "dap.nlua" and vim.list_contains(data.extras, X .. "dap.core"))
  then
    return LazyVim.warn(extra.name .. " cannot be turned on: " .. BLOCKED[extra.module], { title = "Extensions" })
  end
  for _, group in ipairs(on and ONE_OF or {}) do
    for _, other in ipairs(vim.list_contains(group, extra.module) and group or {}) do
      if other ~= extra.module and vim.list_contains(data.extras, other) then
        local name = other:sub(#X + 1)
        return LazyVim.warn(("Turn off %s first: both replace the same part."):format(name), { title = "Extensions" })
      end
    end
  end
  data.extras = vim.tbl_filter(function(module)
    return module ~= extra.module
  end, data.extras)
  if on then
    table.insert(data.extras, extra.module)
    table.sort(data.extras)
  end
  LazyVim.json.save()
  touched[extra.module] = extra
  require("lazycode.sidebar").render()
  LazyVim.info(
    ("%s %s. Click Reload Window in the activity bar to apply."):format(extra.name, on and "enabled" or "disabled"),
    { title = "Extensions" }
  )
end

local function format(item)
  local extra, on = item.extra, wanted(item.extra)
  local ret = {
    { on and "● " or "○ ", on and "DiagnosticOk" or "Comment" },
    { extra.name, "SnacksPickerFile" },
  }
  if on ~= extra.enabled then
    ret[#ret + 1] = { "  restart", "DiagnosticWarn" }
  end
  ret[#ret + 1] = { "  " .. (extra.desc or ""), "Comment" }
  return ret
end

function M.open()
  local items = {}
  for _, extra in ipairs(require("lazyvim.util.extras").get()) do
    items[#items + 1] = { text = extra.name .. " " .. (extra.desc or ""), extra = extra }
  end
  Snacks.picker({
    source = "lazycode_extensions",
    title = "Extensions",
    items = items,
    format = format,
    auto_close = false,
    focus = "input",
    layout = { preset = "sidebar", preview = false },
    confirm = function(picker, item)
      if item then
        M.toggle(item.extra)
        picker.list:update({ force = true })
      end
    end,
    win = {
      list = {
        keys = { ["<2-LeftMouse>"] = false, ["<LeftRelease>"] = "lazycode_click" },
      },
    },
  })
end

local function add_custom_plugin()
  Snacks.input({ prompt = "GitHub Plugin (author/repo)" }, function(value)
    local repo = value and vim.trim(value) or ""
    repo = repo:gsub("^https?://github%.com/", ""):gsub("%.git$", ""):gsub("/+$", "")
    if not repo:match("^[%w%.%-%_]+/[%w%.%-%_]+$") then
      if repo ~= "" then
        LazyVim.warn("Use the format author/plugin.nvim", { title = "Plugins" })
      end
      return
    end
    local custom = vim.fn.stdpath("config") .. "/lua/plugins/custom.lua"
    local specs = {}
    if (vim.uv or vim.loop).fs_stat(custom) then
      local ok, loaded = pcall(dofile, custom)
      if ok and type(loaded) == "table" then
        specs = loaded
      end
    end
    for _, s in ipairs(specs) do
      local existing = type(s) == "string" and s or (type(s) == "table" and s[1])
      if existing == repo then
        return LazyVim.info(repo .. " is already in custom.lua.", { title = "Plugins" })
      end
    end
    specs[#specs + 1] = { repo }
    local lines = {
      "-- Custom plugins added from LazyCode (Ctrl+Shift+P -> Plugins).",
      "return {",
    }
    for _, s in ipairs(specs) do
      local r = type(s) == "string" and s or (type(s) == "table" and s[1])
      if type(s) == "table" and vim.tbl_count(s) > 1 then
        lines[#lines + 1] = "  " .. vim.inspect(s):gsub("\n%s*", " ") .. ","
      elseif r then
        lines[#lines + 1] = ("  { %q },"):format(r)
      end
    end
    lines[#lines + 1] = "}"
    vim.fn.mkdir(vim.fs.dirname(custom), "p")
    local fd = io.open(custom, "w")
    if fd then
      fd:write(table.concat(lines, "\n") .. "\n")
      fd:close()
    end
    LazyVim.info("Added " .. repo .. ". Reloading window to install...", { title = "Plugins" })
    vim.defer_fn(function()
      require("lazycode.project").reload()
    end, 300)
  end)
end

--- Mason/Extensions-style interactive picker to add, install, and load lazy.nvim plugins.
function M.pick_plugins()
  local function build_items()
    local plugins = vim.tbl_filter(function(p)
      return p.enabled ~= false
    end, require("lazy").plugins())
    table.sort(plugins, function(a, b)
      local sa = (a._.loaded and 2) or (a._.installed and 1) or 0
      local sb = (b._.loaded and 2) or (b._.installed and 1) or 0
      if sa ~= sb then
        return sa < sb
      end
      return a.name:lower() < b.name:lower()
    end)
    local not_loaded = 0
    for _, p in ipairs(plugins) do
      if not p._.loaded then
        not_loaded = not_loaded + 1
      end
    end
    local items = {
      {
        text = "load all plugins now carregar todos",
        action = "load_all",
        label = ("⚡ Load All Plugins Now (%d not loaded)"):format(not_loaded),
      },
      {
        text = "add install new plugin github custom instalar novo",
        action = "add",
        label = "+ Install New Plugin from GitHub (author/repo)...",
      },
    }
    for _, p in ipairs(plugins) do
      items[#items + 1] = {
        text = p.name
          .. " "
          .. (p.url or "")
          .. " "
          .. (p._.loaded and "loaded" or p._.installed and "not loaded" or "not installed"),
        plugin = p,
      }
    end
    return items, plugins
  end

  local initial_items, plugins = build_items()
  Snacks.picker({
    source = "lazycode_plugins",
    title = "Lazy Plugins (Click or Enter: install & load · Esc: close)",
    items = initial_items,
    layout = { preset = "vscode" },
    matcher = { sort_empty = false },
    format = function(item)
      if item.action then
        return { { item.label, "Function" } }
      end
      local p = item.plugin
      local loaded = p._.loaded ~= nil
      local installed = p._.installed == true
      local icon = loaded and "● " or installed and "◐ " or "○ "
      local hl = loaded and "DiagnosticOk" or installed and "DiagnosticWarn" or "DiagnosticError"
      local state = loaded and "Loaded"
        or installed and "Not Loaded — click/Enter to load"
        or "Not Installed — click/Enter to install & load"
      return {
        { icon, hl },
        { p.name, "SnacksPickerFile" },
        { "  " .. state, "Comment" },
      }
    end,
    confirm = function(picker, item)
      if not item then
        return
      end
      if item.action == "add" then
        picker:close()
        return vim.schedule(add_custom_plugin)
      elseif item.action == "load_all" then
        local missing, to_load = {}, {}
        for _, p in ipairs(plugins) do
          if not p._.installed then
            missing[#missing + 1] = p.name
          end
          if not p._.loaded then
            to_load[#to_load + 1] = p.name
          end
        end
        if #missing > 0 then
          require("lazy").install({ plugins = missing, show = false, wait = true })
        end
        if #to_load > 0 then
          pcall(require("lazy").load, { plugins = to_load })
        end
        require("lazycode.platform").keep_shortcuts()
        local left = 0
        for _, p in ipairs(plugins) do
          if not p._.loaded then
            left = left + 1
          end
        end
        item.label = ("⚡ Load All Plugins Now (%d not loaded)"):format(left)
        picker.list:update({ force = true })
        LazyVim.info(("Loaded %d plugin(s)."):format(#to_load), { title = "Lazy Plugins" })
        return
      end
      local p = item.plugin
      if p._.loaded then
        LazyVim.info(p.name .. " is already loaded.", { title = "Lazy Plugins" })
        return
      end
      if not p._.installed then
        LazyVim.info("Installing " .. p.name .. "...", { title = "Lazy Plugins" })
        require("lazy").install({ plugins = { p.name }, show = false, wait = true })
      end
      local ok, err = pcall(function()
        require("lazy").load({ plugins = { p.name } })
      end)
      require("lazycode.platform").keep_shortcuts()
      local left = 0
      for _, pl in ipairs(plugins) do
        if not pl._.loaded then
          left = left + 1
        end
      end
      initial_items[1].label = ("⚡ Load All Plugins Now (%d not loaded)"):format(left)
      picker.list:update({ force = true })
      if ok and p._.loaded then
        LazyVim.info("Loaded " .. p.name .. ".", { title = "Lazy Plugins" })
      elseif not ok then
        LazyVim.error("Failed loading " .. p.name .. ": " .. tostring(err), { title = "Lazy Plugins" })
      end
    end,
  })
end

return M
