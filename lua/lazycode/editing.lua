-- VS Code style editing: always in Insert, and typing replaces the selection.
local M = { vim_mode = false }

local attached = {} ---@type table<integer, {[1]:string|string[], [2]:string}[]>
local closed = {} ---@type string[]

local cursor_keys = {} ---@type {[1]:integer, [2]:string}[]

function M.cursor_count()
  return require("multiple-cursors.virtual_cursors").get_num_virtual_cursors() + 1
end

function M.clear_cursors()
  if M.mc_active then
    require("multiple-cursors").deinit(true)
  end
end

local function exit_cursors()
  local mode = vim.fn.mode()
  M.clear_cursors()
  if mode == "v" or mode == "V" then
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  end
end

-- Called by the plugin when the first extra cursor is created.
function M.mc_enter()
  M.mc_active = true
  vim.o.selection = "inclusive"
  vim.schedule(function()
    if not M.mc_active then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local change = vim.fn.maparg("c", "x", false, true).callback
    local function set(mode, lhs, fn)
      vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, nowait = true })
    end
    for code = 32, 126 do
      local ch = string.char(code)
      local lhs = ch == " " and "<Space>"
        or ch == "<" and "<lt>"
        or ch == "|" and "<Bar>"
        or ch == "\\" and "<Bslash>"
        or ch
      set("x", lhs, function()
        change()
        vim.api.nvim_feedkeys(ch, "nt", false)
      end)
      cursor_keys[#cursor_keys + 1] = { buf, lhs }
    end
    for _, key in ipairs({ "<BS>", "<Del>" }) do
      set("x", key, change)
      cursor_keys[#cursor_keys + 1] = { buf, key }
    end
    set({ "i", "n", "x" }, "<Esc>", exit_cursors)
    set("i", "<C-v>", function()
      vim.paste(vim.fn.getreg("+", 1, true), -1)
    end)
  end)
end

-- Called by the plugin when the extra cursors are removed.
function M.mc_leave()
  M.mc_active = false
  vim.o.selection = M.vim_mode and "inclusive" or "exclusive"
  for _, item in ipairs(cursor_keys) do
    if vim.api.nvim_buf_is_valid(item[1]) then
      pcall(vim.keymap.del, "x", item[2], { buffer = item[1] })
    end
  end
  cursor_keys = {}
end

-- VS Code selections are exclusive; the plugin expects inclusive ones.
function M.mc_visual(command)
  if vim.o.selection == "exclusive" then
    local pos = vim.fn.getcurpos()
    if pos[3] > 1 then
      vim.fn.cursor(pos[2], pos[3] - 1)
    end
    vim.o.selection = "inclusive"
  end
  vim.cmd("MultipleCursors" .. command)
end

function M.editable(buf, win)
  buf = buf or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()
  local bo = vim.bo[buf]
  return bo.buftype == "" and bo.modifiable and not bo.readonly and vim.api.nvim_win_get_config(win).relative == ""
end

function M.ensure_insert()
  if M.vim_mode or M.mc_active then
    return
  end
  -- Lists (Explorer, activity bar) take no text, so they stay in Normal.
  if vim.fn.mode() == "i" and vim.bo.buftype == "nofile" and not vim.bo.modifiable then
    vim.cmd.stopinsert()
    return
  end
  if not M.editable() then
    return
  end
  if vim.api.nvim_get_mode().mode == "n" and vim.fn.state("mo") == "" then
    -- While the editor is idle, :startinsert would only apply on the next key.
    vim.api.nvim_feedkeys(vim.keycode("<Cmd>lua require('lazycode.editing').start_insert()<CR>"), "n", false)
  end
end

-- The window may have changed between the request and this call.
function M.start_insert()
  if not M.vim_mode and not M.mc_active and M.editable() and vim.fn.mode() == "n" then
    vim.cmd.startinsert()
  end
end

local function set_cursor(line, col)
  line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(0)))
  vim.api.nvim_win_set_cursor(0, { line, col })
end

local function move_line(dir)
  local l, c = unpack(vim.api.nvim_win_get_cursor(0))
  local target = l + dir
  if target < 1 or target > vim.api.nvim_buf_line_count(0) then
    return
  end
  vim.cmd(("silent move %d"):format(dir > 0 and l + 1 or l - 2))
  set_cursor(target, c)
end

local function duplicate_line(dir)
  local l, c = unpack(vim.api.nvim_win_get_cursor(0))
  local text = vim.api.nvim_get_current_line()
  vim.api.nvim_buf_set_lines(0, l, l, false, { text })
  set_cursor(dir > 0 and l + 1 or l, c)
end

local function delete_line()
  local l, c = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_lines(0, l - 1, l, false, {})
  local line = math.min(l, vim.api.nvim_buf_line_count(0))
  set_cursor(line, math.min(c, #vim.fn.getline(line)))
end

local function open_line(dir)
  local l = vim.api.nvim_win_get_cursor(0)[1]
  local indent = vim.api.nvim_get_current_line():match("^%s*")
  local at = dir > 0 and l or l - 1
  vim.api.nvim_buf_set_lines(0, at, at, false, { indent })
  set_cursor(at + 1, #indent)
end

local function copy_line()
  vim.fn.setreg("+", vim.api.nvim_get_current_line() .. "\n", "V")
end

local function cut_line()
  copy_line()
  delete_line()
end

local function paste()
  local lines = vim.fn.getreg("+", 1, true)
  if #lines == 0 then
    return
  end
  if vim.fn.getregtype("+") == "V" then
    local l, c = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_lines(0, l - 1, l - 1, false, lines)
    set_cursor(l + #lines, c)
  else
    vim.api.nvim_put(lines, "c", false, true)
  end
end

local function smart_home()
  local l, c = unpack(vim.api.nvim_win_get_cursor(0))
  local first = #vim.api.nvim_get_current_line():match("^%s*")
  set_cursor(l, c == first and 0 or first)
end

local function save()
  if vim.api.nvim_buf_get_name(0) ~= "" then
    vim.cmd("silent write")
    return
  end
  vim.ui.input({ prompt = "Save as: ", completion = "file" }, function(name)
    if name and name ~= "" then
      vim.cmd.saveas(vim.fn.fnameescape(name))
    end
  end)
end

function M.close_buffer()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    table.insert(closed, name)
  end
  Snacks.bufdelete()
  vim.schedule(function()
    require("lazycode.welcome").show_if_empty()
  end)
end

function M.reopen_buffer()
  local name = table.remove(closed)
  if name then
    vim.cmd.edit(vim.fn.fnameescape(name))
  end
end

local function escape()
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.is_visible() then
    blink.hide()
  end
  vim.cmd.nohlsearch()
end

local function find_replace_file()
  require("grug-far").open({ prefills = { paths = vim.fn.expand("%:p") } })
end

local function goto_line()
  vim.ui.input({ prompt = "Go to line: " }, function(value)
    local line = tonumber(value)
    if line then
      set_cursor(line, 0)
    end
  end)
end

local function jump(key)
  return function()
    vim.cmd.normal({ args = { vim.keycode(key) }, bang = true })
  end
end

local function mc_visual(command)
  return "<Cmd>lua require('lazycode.editing').mc_visual('" .. command .. "')<CR>"
end

local I, S, X = "i", "s", "x"
local ALL = { I, "n" }

-- { modes, key, action, options }
local function bindings()
  local selected_up = ":m '<-2<CR>gv<C-g>"
  local selected_down = ":m '>+1<CR>gv<C-g>"
  return {
    { { I, "n", X, S }, "<C-s>", save },
    { ALL, "<C-z>", "<Cmd>undo<CR>" },
    { ALL, "<C-y>", "<Cmd>redo<CR>" },
    { ALL, "<C-S-z>", "<Cmd>redo<CR>" },
    { { X, S }, "<C-z>", "<Esc><Cmd>undo<CR>" },

    { ALL, "<C-c>", copy_line },
    { S, "<C-c>", '<C-g>"+ygv<C-g>' },
    { X, "<C-c>", '"+ygv' },
    { ALL, "<C-x>", cut_line },
    { S, "<C-x>", '<C-g>"+c' },
    { X, "<C-x>", '"+c' },
    { ALL, "<C-v>", paste },
    { S, "<C-v>", '<C-g>"_c<C-r><C-o>+' },
    { X, "<C-v>", '"_c<C-r><C-o>+' },
    { I, "<C-a>", "<C-o>gg<C-o>0<C-o>vG$<C-g>" },
    { "n", "<C-a>", "gg0vG$<C-g>" },
    { X, "<C-a>", "<Esc>gg0vG$<C-g>" },
    { S, "<C-a>", "<C-g><Esc>gg0vG$<C-g>" },

    { ALL, "<C-/>", "<Cmd>normal gcc<CR>" },
    { { X, S }, "<C-/>", "<C-g>gcgv<C-g>", { remap = true } },
    { ALL, "<S-A-a>", "<Cmd>normal gcc<CR>" },

    {
      ALL,
      "<A-Up>",
      function()
        move_line(-1)
      end,
    },
    {
      ALL,
      "<A-Down>",
      function()
        move_line(1)
      end,
    },
    { S, "<A-Up>", "<C-g>" .. selected_up },
    { S, "<A-Down>", "<C-g>" .. selected_down },
    { X, "<A-Up>", selected_up },
    { X, "<A-Down>", selected_down },
    {
      ALL,
      "<S-A-Up>",
      function()
        duplicate_line(-1)
      end,
    },
    {
      ALL,
      "<S-A-Down>",
      function()
        duplicate_line(1)
      end,
    },
    { ALL, "<C-S-k>", delete_line },
    {
      ALL,
      "<C-CR>",
      function()
        open_line(1)
      end,
    },
    {
      ALL,
      "<C-S-CR>",
      function()
        open_line(-1)
      end,
    },

    { I, "<C-]>", "<C-t>" },
    { I, "<C-[>", "<C-d>" },
    { I, "<S-Tab>", "<C-d>" },
    { S, "<Tab>", "<C-g>>gv<C-g>" },
    { S, "<S-Tab>", "<C-g><gv<C-g>" },
    { S, "<C-]>", "<C-g>>gv<C-g>" },
    { S, "<C-[>", "<C-g><gv<C-g>" },
    { I, "<Home>", smart_home },
    { I, "<C-BS>", "<C-w>" },
    { I, "<C-Del>", "<C-o>dw" },

    { I, "<C-d>", "<C-o>viw<C-g>" },
    { S, "<C-d>", "<C-g>" .. mc_visual("AddJumpNextMatch") },
    { X, "<C-d>", mc_visual("AddJumpNextMatch") },
    { I, "<C-S-l>", "<C-o>viw" .. mc_visual("AddMatches") },
    { S, "<C-S-l>", "<C-g>" .. mc_visual("AddMatches") },
    { X, "<C-S-l>", mc_visual("AddMatches") },
    { { I, "n" }, "<C-A-Up>", "<Cmd>MultipleCursorsAddUp<CR>" },
    { { I, "n" }, "<C-A-Down>", "<Cmd>MultipleCursorsAddDown<CR>" },

    { ALL, "<Esc>", escape },
    { S, "<Esc>", "<C-g><Esc>" },

    { ALL, "<C-f>", "<C-o>/" },
    { { X, S }, "<C-f>", "<Esc>/" },
    { ALL, "<C-h>", find_replace_file },
    { ALL, "<F3>", jump("n") },
    { ALL, "<S-F3>", jump("N") },
    { ALL, "<C-g>", goto_line },
    { ALL, "<A-Left>", jump("<C-o>") },
    { ALL, "<A-Right>", jump("<C-i>") },

    { ALL, "<F12>", vim.lsp.buf.definition },
    {
      ALL,
      "<A-F12>",
      function()
        Snacks.picker.lsp_definitions()
      end,
    },
    {
      ALL,
      "<S-F12>",
      function()
        Snacks.picker.lsp_references()
      end,
    },
    { ALL, "<F2>", vim.lsp.buf.rename },
    { ALL, "<C-.>", vim.lsp.buf.code_action },
    {
      ALL,
      "<S-A-f>",
      function()
        LazyVim.format({ force = true })
      end,
    },
    {
      ALL,
      "<F8>",
      function()
        vim.diagnostic.jump({ count = 1, float = true })
      end,
    },
    {
      ALL,
      "<S-F8>",
      function()
        vim.diagnostic.jump({ count = -1, float = true })
      end,
    },
    {
      ALL,
      "<C-S-o>",
      function()
        Snacks.picker.lsp_symbols()
      end,
    },
    {
      ALL,
      "<C-LeftMouse>",
      function()
        require("lazycode.mouse").goto_definition()
      end,
    },
    { { I, "n" }, "<A-LeftMouse>", "<Cmd>MultipleCursorsMouseAddDelete<CR>" },
  }
end

function M.attach(buf)
  if M.vim_mode or attached[buf] or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local list = {}
  for _, b in ipairs(bindings()) do
    local opts = vim.tbl_extend("force", { buffer = buf, silent = true, nowait = true }, b[4] or {})
    for _, key in ipairs(require("lazycode.platform").variants(b[2])) do
      vim.keymap.set(b[1], key, b[3], opts)
      list[#list + 1] = { b[1], key }
    end
  end
  attached[buf] = list
end

function M.detach(buf)
  for _, item in ipairs(attached[buf] or {}) do
    pcall(vim.keymap.del, item[1], item[2], { buffer = buf })
  end
  attached[buf] = nil
end

local function apply_options()
  vim.o.keymodel = M.vim_mode and "" or "startsel,stopsel"
  vim.o.selectmode = M.vim_mode and "" or "mouse,key"
  vim.o.virtualedit = M.vim_mode and "block" or "onemore"
  vim.o.selection = M.vim_mode and "inclusive" or "exclusive"
end

function M.toggle_vim()
  M.vim_mode = not M.vim_mode
  apply_options()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if M.vim_mode then
      M.detach(buf)
    else
      M.attach(buf)
    end
  end
  if M.vim_mode then
    vim.cmd.stopinsert()
  else
    M.ensure_insert()
  end
  vim.cmd.redrawstatus()
  vim.notify(M.vim_mode and "Vim mode on" or "VS Code mode on", vim.log.levels.INFO, { title = "LazyCode" })
end

function M.setup()
  apply_options()
  local group = vim.api.nvim_create_augroup("lazycode_editing", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = group,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      attached[ev.buf] = nil
    end,
  })
  -- SafeState only fires with no pending keys, so it never interrupts mappings.
  vim.api.nvim_create_autocmd("SafeState", {
    group = group,
    callback = M.ensure_insert,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      vim.defer_fn(function()
        -- When a terminal (including lazygit) gets focus, keys go to the program.
        if vim.bo.buftype == "terminal" and vim.api.nvim_get_mode().mode == "nt" and not M.vim_mode then
          vim.api.nvim_feedkeys(vim.keycode("<Cmd>if &buftype ==# 'terminal' | startinsert | endif<CR>"), "n", false)
        else
          M.ensure_insert()
        end
      end, 20)
    end,
  })
  -- Fallback: error messages can prevent SafeState from firing.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:n",
    callback = function()
      vim.defer_fn(M.ensure_insert, 30)
    end,
  })
  -- Undo in chunks: break the undo sequence at spaces and punctuation.
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    callback = function()
      if not M.vim_mode and vim.v.char:match("[%s%.,;:]") then
        vim.go.undolevels = vim.go.undolevels
      end
    end,
  })

  -- Pickers switch windows without firing autocmds; this timer covers those cases.
  local timer = assert(vim.uv.new_timer())
  timer:start(200, 200, vim.schedule_wrap(M.ensure_insert))

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.attach(buf)
  end
  M.ensure_insert()
end

return M
