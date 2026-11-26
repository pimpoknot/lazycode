-- Font of the LazyCode window. Every detail is spelled out here, even when it matches a default.
-- Like VS Code, Ctrl+= and Ctrl+- zoom, Ctrl+0 resets to `size`, and the zoom is remembered.
local M = {
  -- Name as `fc-list : family` shows it first, without variant suffixes like "SemBd".
  family = "FiraCode Nerd Font Mono",
  -- Used where `family` is not installed. The installer pins both fonts.
  fallback = "JetBrainsMono Nerd Font Mono",
  -- Points, like VS Code's editor.fontSize and kitty's font_size: 13 pt is about 17 pixels.
  size = 13,
  -- Weight of normal text: 300 light, 400 regular, 500 medium, 600 semibold, 700 bold.
  weight = 550,
  -- Weight of bold text (keywords and headings in most themes).
  bold_weight = 700,
  -- Extra pixels between lines, on top of the font's own line height (Neovim's 'linespace').
  line_height = 0,
  -- Extra pixels between letters, split evenly around each one.
  letter_spacing = 0,
}

--- The 'guifont' the LazyCode window reads: families in order, then each detail.
local function guifont(size)
  return ("%s,%s:h%s:w%d:W%d:c%s"):format(M.family, M.fallback, size, M.weight, M.bold_weight, M.letter_spacing)
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

function M.current_size()
  return tonumber(vim.o.guifont:match(":h([%d.]+)")) or M.size
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
  vim.o.linespace = M.line_height
  vim.o.guifont = guifont(saved() or M.size)
  local map = function(lhs, fn, desc)
    require("lazycode.platform").map({ "n", "i", "x", "s", "t" }, lhs, fn, { silent = true, desc = desc })
  end
  local zoom_in = function()
    M.set(M.current_size() + 1)
  end
  map("<C-=>", zoom_in, "Zoom in")
  map("<C-+>", zoom_in, "Zoom in")
  map("<C-->", function()
    M.set(M.current_size() - 1)
  end, "Zoom out")
  map("<C-0>", function()
    M.set(M.size)
  end, "Reset zoom")
end

return M
