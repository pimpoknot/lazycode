-- Differences between Linux and macOS.
local M = {}

M.mac = vim.fn.has("mac") == 1

--- Shortcut text shown in the UI: "Ctrl+O" becomes "⌘O" on macOS.
function M.label(text)
  if not M.mac then
    return text
  end
  return (text:gsub("Ctrl%+", "⌘"):gsub("Shift%+", "⇧"):gsub("Alt%+", "⌥"))
end

local KEEP_CTRL = { ["<C-`>"] = true, ["<C-Tab>"] = true, ["<C-S-Tab>"] = true, ["<C-j>"] = true, ["<C-[>"] = true }

--- Key variants for one shortcut: on macOS, Ctrl shortcuts also work with Cmd.
function M.variants(lhs)
  if not M.mac or KEEP_CTRL[lhs] or not lhs:find("<C-", 1, true) then
    return { lhs }
  end
  return { lhs, (lhs:gsub("<C%-", "<D-")) }
end

function M.map(modes, lhs, rhs, opts)
  for _, key in ipairs(M.variants(lhs)) do
    vim.keymap.set(modes, key, rhs, opts)
  end
end

--- Expands a picker key table with the macOS variants.
function M.picker_keys(keys)
  local out = {}
  for lhs, action in pairs(keys) do
    for _, key in ipairs(M.variants(lhs)) do
      out[key] = action
    end
  end
  return out
end

return M
