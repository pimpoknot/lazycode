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

local KEEP_CTRL = {
  ["<C-`>"] = true,
  ["<C-S-`>"] = true,
  ["<C-Tab>"] = true,
  ["<C-S-Tab>"] = true,
  ["<C-j>"] = true,
  ["<C-[>"] = true,
  ["<C-Space>"] = true,
  ["<C-S-Space>"] = true,
}

--- Key variants for one shortcut: on macOS, Ctrl shortcuts also work with Cmd.
function M.variants(lhs)
  if not M.mac or KEEP_CTRL[lhs] or not lhs:find("<C-", 1, true) then
    return { lhs }
  end
  return { lhs, (lhs:gsub("<C%-", "<D-")) }
end

local global = {} ---@type table[] every global LazyCode shortcut, to set again later

function M.map(modes, lhs, rhs, opts)
  global[#global + 1] = { modes, lhs, rhs, opts }
  for _, key in ipairs(M.variants(lhs)) do
    vim.keymap.set(modes, key, rhs, opts)
  end
end

local function clear_leader_maps(buf)
  for _, mode in ipairs({ "n", "x", "o" }) do
    local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
    for _, m in ipairs(maps) do
      if m.lhs and #m.lhs > 1 and m.lhs:sub(1, 1) == " " then
        pcall(vim.keymap.del, mode, m.lhs, buf and { buffer = buf } or nil)
      end
    end
  end
end

function M.clear_leader(buf)
  if not require("lazycode.editing").vim_mode then
    clear_leader_maps(buf)
  end
end

--- VS Code shortcuts always win: plugins that load later (extras included) may map the same
--- keys or add LazyVim <leader> bindings, so LazyCode clears <leader> maps and sets its own again.
function M.keep_shortcuts()
  local function apply()
    M.clear_leader()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        M.clear_leader(buf)
      end
    end
    for _, m in ipairs(global) do
      for _, key in ipairs(M.variants(m[2])) do
        vim.keymap.set(m[1], key, m[3], m[4])
      end
    end
  end
  apply()
  local group = vim.api.nvim_create_augroup("lazycode_shortcuts", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "LazyLoad", "VeryLazy" },
    callback = vim.schedule_wrap(apply),
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) then
          M.clear_leader(ev.buf)
        end
      end)
    end,
  })
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
