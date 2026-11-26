-- Font of the LazyCode window, through Neovim's 'guifont'. Like VS Code, Ctrl+= and Ctrl+-
-- zoom, Ctrl+0 resets, and the size is remembered.
-- `family` lists names as `fc-list : family` shows them, in order; `weight` is 400 regular, 600 semibold.
-- FiraCode SemiBold, or JetBrains Mono SemiBold where FiraCode is not installed.
local M = { family = "FiraCode Nerd Font Mono", weight = 550, default = 13 }

local function guifont(size)
  return ("%s:h%s:w%d"):format(M.family, size, M.weight)
end

local function path()
  return vim.fn.stdpath("state") .. "/lazycode_font_size"
end

local function saved()
  local fd = io.open(path(), "r")
  local size = fd and tonumber(fd:read("*l"))
  if fd then
    fd:close()
  end
  return size
end

function M.size()
  return tonumber(vim.o.guifont:match(":h([%d.]+)")) or M.default
end

function M.set(size)
  size = math.max(8, math.min(32, size))
  vim.o.guifont = guifont(size)
  vim.fn.mkdir(vim.fn.stdpath("state"), "p")
  local fd = io.open(path(), "w")
  if fd then
    fd:write(size, "\n")
    fd:close()
  end
end

function M.setup()
  vim.o.guifont = guifont(saved() or M.default)
  local map = function(lhs, fn, desc)
    require("lazycode.platform").map({ "n", "i", "x", "s", "t" }, lhs, fn, { silent = true, desc = desc })
  end
  local zoom_in = function()
    M.set(M.size() + 1)
  end
  map("<C-=>", zoom_in, "Zoom in")
  map("<C-+>", zoom_in, "Zoom in")
  map("<C-->", function()
    M.set(M.size() - 1)
  end, "Zoom out")
  map("<C-0>", function()
    M.set(M.default)
  end, "Reset zoom")
end

return M
