-- Extensions panel: the LazyVim extras as a searchable list. A click turns one on or off.
local M = {}
local touched = {} ---@type table<string, table> extras changed since start, by module

local X = "lazyvim.plugins.extras."
-- Extras that break LazyCode's own features, with the reason shown when someone turns one on.
local BLOCKED = {
  [X .. "ai.copilot"] = "Copilot already comes with LazyCode (ai.copilot-native).",
  [X .. "coding.nvim-cmp"] = "LazyCode's completion and shortcuts are built on blink.cmp.",
  [X .. "editor.neo-tree"] = "LazyCode's Explorer is the Snacks explorer.",
  [X .. "ui.alpha"] = "LazyCode opens on its own Welcome tab.",
  [X .. "ui.dashboard-nvim"] = "LazyCode opens on its own Welcome tab.",
  [X .. "ui.mini-starter"] = "LazyCode opens on its own Welcome tab.",
}
-- Only one extra of each group can be on: they replace the same piece.
local ONE_OF = { { X .. "coding.luasnip", X .. "coding.mini-snippets" } }

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
  if on and BLOCKED[extra.module] then
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

return M
