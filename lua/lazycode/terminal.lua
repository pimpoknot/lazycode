-- Integrated terminal that behaves like a terminal: clicks and scrolling never
-- leave the shell stuck as plain text.
local M = {}

local MENU = "]LazyCodeTerminal"
local SPECIAL = {
  ["<CR>"] = "\r",
  ["<BS>"] = "\127",
  ["<Tab>"] = "\t",
  ["<C-c>"] = "\3",
  ["<C-d>"] = "\4",
  ["<C-l>"] = "\12",
  ["<C-u>"] = "\21",
  ["<Up>"] = "\27[A",
  ["<Down>"] = "\27[B",
  ["<Right>"] = "\27[C",
  ["<Left>"] = "\27[D",
}

local function vim_mode()
  return require("lazycode.editing").vim_mode
end

local function in_selection()
  return vim.fn.mode():match("^[vVsS\22\19]") ~= nil
end

--- Back to the shell, from Normal or from a selection.
local function focus_shell()
  local keys = (in_selection() and "<Esc>" or "") .. "<Cmd>startinsert<CR>"
  vim.api.nvim_feedkeys(vim.keycode(keys), "n", false)
end

local function send(data)
  local job = vim.b.terminal_job_id
  if job then
    vim.api.nvim_chan_send(job, data)
  end
end

--- Shell command without LazyCode's private environment, so that running
--- `nvim` or `lazygit` inside the terminal uses the person's own setup.
function M.shell()
  local function inside(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
  end
  local private = vim.fn.stdpath("data")
  local runtime = vim.env.LAZYCODE_RUNTIME
  local path = vim.env.LAZYCODE_USER_PATH
  if not path then
    local kept = {}
    for entry in (vim.env.PATH or ""):gmatch("[^:]+") do
      if not inside(entry, private) and not (runtime and inside(entry, runtime)) then
        kept[#kept + 1] = entry
      end
    end
    path = table.concat(kept, ":")
  end
  local cmd = { "env" }
  for _, name in ipairs({ "NVIM_APPNAME", "LG_CONFIG_FILE", "LAZYCODE_USER_PATH", "LAZYCODE_RUNTIME" }) do
    vim.list_extend(cmd, { "-u", name })
  end
  cmd[#cmd + 1] = "PATH=" .. path
  return vim.list_extend(cmd, Snacks.terminal.parse(vim.o.shell))
end

function M.toggle(opts)
  return Snacks.terminal(nil, vim.tbl_extend("force", { shell = M.shell() }, opts or {}))
end

function M.copy()
  if in_selection() then
    local mode = vim.fn.mode()
    local kind = (mode == "s" and "v") or (mode == "S" and "V") or (mode == "\19" and "\22") or mode
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = kind })
    lines = vim.tbl_map(function(line)
      return (line:gsub("%s+$", ""))
    end, lines)
    vim.fn.setreg("+", table.concat(lines, "\n"))
  end
  focus_shell()
end

--- Bracketed paste: multi-line text is not executed line by line.
function M.paste()
  local text = vim.fn.getreg("+")
  if text ~= "" then
    vim.api.nvim_paste(text, true, -1)
  end
end

function M.clear()
  send("\12")
  focus_shell()
end

function M.over()
  local win = vim.fn.getmousepos().winid
  return win ~= 0 and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
end

--- True when the shell itself is in the foreground, not a program like htop.
function M.at_prompt()
  local win = vim.fn.getmousepos().winid
  local job = win ~= 0 and vim.b[vim.api.nvim_win_get_buf(win)].terminal_job_id
  if not job then
    return false
  end
  local ok, pid = pcall(vim.fn.jobpid, job)
  if not ok then
    return false
  end
  local out = vim.system({ "ps", "-o", "tpgid=,pgid=", "-p", tostring(pid) }, { text = true }):wait(500)
  local foreground, group = (out.stdout or ""):match("(%-?%d+)%s+(%d+)")
  return foreground ~= nil and foreground == group
end

local PASTE = "<Cmd>startinsert<CR><Cmd>lua require('lazycode.terminal').paste()<CR>"

function M.context()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= 0 and pos.winid ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(pos.winid)
  end
  pcall(vim.cmd, "silent! aunmenu " .. MENU)
  local entries = {
    {
      "Paste",
      "<Tab>" .. require("lazycode.platform").label(require("lazycode.platform").mac and "Ctrl+V" or "Ctrl+Shift+V"),
      PASTE,
      PASTE,
    },
    { "Clear", "", "<Cmd>lua require('lazycode.terminal').clear()<CR>" },
  }
  if in_selection() then
    local copy = "<Cmd>lua require('lazycode.terminal').copy()<CR>"
    table.insert(entries, 1, {
      "Copy",
      "<Tab>" .. require("lazycode.platform").label(require("lazycode.platform").mac and "Ctrl+C" or "Ctrl+Shift+C"),
      copy,
    })
  end
  for _, entry in ipairs(entries) do
    local rhs = entry[3]
    for _, cmd in ipairs({ "nnoremenu", "xnoremenu", "snoremenu" }) do
      local value = rhs
      if entry[4] and cmd ~= "nnoremenu" then
        value = "<Esc>" .. rhs
      end
      vim.cmd(("%s <silent> %s.%s%s %s"):format(cmd, MENU, entry[1], entry[2], value))
    end
  end
  vim.defer_fn(function()
    pcall(vim.cmd, "popup! " .. MENU)
  end, 15)
end

local function attach(buf)
  local function map(modes, lhs, rhs)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end
  local platform = require("lazycode.platform")
  local function forward(lhs, raw)
    return function()
      if vim_mode() then
        return vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
      end
      send(raw)
      focus_shell()
    end
  end
  local modes = { "n", "x", "s" }
  for code = 32, 126 do
    local ch = string.char(code)
    local lhs = ch == " " and "<Space>"
      or ch == "<" and "<lt>"
      or ch == "|" and "<Bar>"
      or ch == "\\" and "<Bslash>"
      or ch
    map(modes, lhs, forward(lhs, ch))
  end
  for lhs, raw in pairs(SPECIAL) do
    map(modes, lhs, forward(lhs, raw))
  end
  map(modes, "<Esc>", function()
    if vim_mode() then
      return vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
    end
    focus_shell()
  end)
  -- A click without a drag goes straight back to the shell.
  map("n", "<LeftRelease>", function()
    if not vim_mode() and vim.fn.getmousepos().winid == vim.api.nvim_get_current_win() then
      focus_shell()
    end
  end)
  map({ "n", "x", "s", "t" }, "<C-S-c>", M.copy)
  map("t", "<C-S-v>", M.paste)
  map("n", "<C-S-v>", PASTE)
  map({ "x", "s" }, "<C-S-v>", "<Esc>" .. PASTE)
  if platform.mac then
    map({ "n", "x", "s", "t" }, "<D-c>", M.copy)
    map("t", "<D-v>", M.paste)
    map("n", "<D-v>", PASTE)
    map({ "x", "s" }, "<D-v>", "<Esc>" .. PASTE)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("lazycode_terminal", { clear = true }),
    callback = function(ev)
      attach(ev.buf)
    end,
  })
end

return M
