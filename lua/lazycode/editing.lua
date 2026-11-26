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

--- Single-line text currently selected in Select or Visual mode, if any, leaving selection cleanly.
function M.consume_selection()
  local mode = vim.fn.mode()
  if not mode:match("^[vVsS\22\19]") then
    return nil
  end
  local kind = (mode == "s" and "v") or (mode == "S" and "V") or (mode == "\19" and "\22") or mode
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = kind })
  vim.cmd("normal! \27")
  if ok and #lines == 1 and lines[1] ~= "" then
    return lines[1]
  end
  return nil
end

local function with_normal(fn)
  return function()
    if vim.fn.mode():match("^[vVsS\22\19]") then
      vim.cmd("normal! \27")
    end
    fn()
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

--- Ctrl+F: finds text in the current file with VS Code controls (Enter jumps, Esc cancels, click opens).
local function find_in_file()
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.is_visible() then
    blink.hide()
  end
  local pattern = M.consume_selection()
  Snacks.picker.lines({ pattern = pattern })
end

local function find_replace_file()
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.is_visible() then
    blink.hide()
  end
  local search = M.consume_selection()
  local path = vim.fn.expand("%:p")
  local _, _, buf = require("grug-far").open({
    transient = true,
    windowCreationCommand = "botright 14split",
    prefills = { search = search, paths = path ~= "" and path or nil },
  })
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.b[buf].lazycode_transient = true
  end
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
  return with_normal(function()
    pcall(vim.cmd.normal, { args = { vim.keycode(key) }, bang = true })
  end)
end

local function mc_visual(command)
  return "<Cmd>lua require('lazycode.editing').mc_visual('" .. command .. "')<CR>"
end

local I, S, X = "i", "s", "x"
local ALL = { I, "n" }
local ANY = { I, "n", X, S }

-- { modes, key, action, options }
local function bindings()
  local selected_up = ":m '<-2<CR>gv<C-g>"
  local selected_down = ":m '>+1<CR>gv<C-g>"
  return {
    { ANY, "<C-s>", save, { desc = "Save" } },
    { ALL, "<C-z>", "<Cmd>undo<CR>", { desc = "Undo" } },
    { ALL, "<C-y>", "<Cmd>redo<CR>", { desc = "Redo" } },
    { ALL, "<C-S-z>", "<Cmd>redo<CR>", { desc = "Redo" } },
    { { X, S }, "<C-z>", "<Esc><Cmd>undo<CR>", { desc = "Undo" } },
    { { X, S }, "<C-y>", "<Esc><Cmd>redo<CR>", { desc = "Redo" } },
    { { X, S }, "<C-S-z>", "<Esc><Cmd>redo<CR>", { desc = "Redo" } },

    { ALL, "<C-c>", copy_line, { desc = "Copy" } },
    { S, "<C-c>", '<C-g>"+ygv<C-g>', { desc = "Copy" } },
    { X, "<C-c>", '"+ygv', { desc = "Copy" } },
    { ALL, "<C-x>", cut_line, { desc = "Cut" } },
    { S, "<C-x>", '<C-g>"+c', { desc = "Cut" } },
    { X, "<C-x>", '"+c', { desc = "Cut" } },
    { ALL, "<C-v>", paste, { desc = "Paste" } },
    { S, "<C-v>", '<C-g>"_c<C-r><C-o>+', { desc = "Paste" } },
    { X, "<C-v>", '"_c<C-r><C-o>+', { desc = "Paste" } },
    { I, "<C-a>", "<C-o>gg<C-o>0<C-o>vG$<C-g>", { desc = "Select All" } },
    { "n", "<C-a>", "gg0vG$<C-g>", { desc = "Select All" } },
    { X, "<C-a>", "<Esc>gg0vG$<C-g>", { desc = "Select All" } },
    { S, "<C-a>", "<C-g><Esc>gg0vG$<C-g>", { desc = "Select All" } },

    { ALL, "<C-/>", "<Cmd>normal gcc<CR>", { desc = "Toggle Line Comment" } },
    { { X, S }, "<C-/>", "<C-g>gcgv<C-g>", { remap = true, desc = "Toggle Line Comment" } },
    { ALL, "<C-_>", "<Cmd>normal gcc<CR>", { desc = "Toggle Line Comment" } },
    { { X, S }, "<C-_>", "<C-g>gcgv<C-g>", { remap = true, desc = "Toggle Line Comment" } },
    { ALL, "<S-A-a>", "<Cmd>normal gcc<CR>", { desc = "Toggle Block Comment" } },
    { { X, S }, "<S-A-a>", "<C-g>gcgv<C-g>", { remap = true, desc = "Toggle Block Comment" } },

    {
      ALL,
      "<A-Up>",
      function()
        move_line(-1)
      end,
      { desc = "Move Line Up" },
    },
    {
      ALL,
      "<A-Down>",
      function()
        move_line(1)
      end,
      { desc = "Move Line Down" },
    },
    { S, "<A-Up>", "<C-g>" .. selected_up, { desc = "Move Line Up" } },
    { S, "<A-Down>", "<C-g>" .. selected_down, { desc = "Move Line Down" } },
    { X, "<A-Up>", selected_up, { desc = "Move Line Up" } },
    { X, "<A-Down>", selected_down, { desc = "Move Line Down" } },
    {
      ANY,
      "<S-A-Up>",
      with_normal(function()
        duplicate_line(-1)
      end),
      { desc = "Copy Line Up" },
    },
    {
      ANY,
      "<S-A-Down>",
      with_normal(function()
        duplicate_line(1)
      end),
      { desc = "Copy Line Down" },
    },
    { ANY, "<C-S-k>", with_normal(delete_line), { desc = "Delete Line" } },
    {
      ANY,
      "<C-CR>",
      with_normal(function()
        open_line(1)
      end),
      { desc = "Insert Line Below" },
    },
    {
      ANY,
      "<C-S-CR>",
      with_normal(function()
        open_line(-1)
      end),
      { desc = "Insert Line Above" },
    },

    { I, "<C-]>", "<C-t>", { desc = "Indent Line" } },
    { "n", "<C-]>", ">>", { desc = "Indent Line" } },
    { I, "<C-[>", "<C-d>", { desc = "Outdent Line" } },
    { "n", "<C-[>", "<<", { desc = "Outdent Line" } },
    { I, "<S-Tab>", "<C-d>", { desc = "Outdent Line" } },
    { S, "<Tab>", "<C-g>>gv<C-g>", { desc = "Indent Selection" } },
    { S, "<S-Tab>", "<C-g><gv<C-g>", { desc = "Outdent Selection" } },
    { X, "<Tab>", ">gv", { desc = "Indent Selection" } },
    { X, "<S-Tab>", "<gv", { desc = "Outdent Selection" } },
    { S, "<C-]>", "<C-g>>gv<C-g>", { desc = "Indent Selection" } },
    { S, "<C-[>", "<C-g><gv<C-g>", { desc = "Outdent Selection" } },
    { ALL, "<Home>", smart_home, { desc = "Go to Beginning of Line" } },
    { I, "<C-BS>", "<C-w>", { desc = "Delete Word Left" } },
    { I, "<C-Del>", "<C-o>dw", { desc = "Delete Word Right" } },
    { ALL, "<C-Up>", "<Cmd>normal! \25<CR>", { desc = "Scroll Line Up" } },
    { ALL, "<C-Down>", "<Cmd>normal! \5<CR>", { desc = "Scroll Line Down" } },

    { I, "<C-d>", "<C-o>viw<C-g>", { desc = "Add Selection to Next Find Match" } },
    { "n", "<C-d>", "viw<C-g>", { desc = "Add Selection to Next Find Match" } },
    { S, "<C-d>", "<C-g>" .. mc_visual("AddJumpNextMatch"), { desc = "Add Selection to Next Find Match" } },
    { X, "<C-d>", mc_visual("AddJumpNextMatch"), { desc = "Add Selection to Next Find Match" } },
    { I, "<C-S-l>", "<C-o>viw" .. mc_visual("AddMatches"), { desc = "Select All Occurrences" } },
    { "n", "<C-S-l>", "viw" .. mc_visual("AddMatches"), { desc = "Select All Occurrences" } },
    { S, "<C-S-l>", "<C-g>" .. mc_visual("AddMatches"), { desc = "Select All Occurrences" } },
    { X, "<C-S-l>", mc_visual("AddMatches"), { desc = "Select All Occurrences" } },
    { I, "<C-F2>", "<C-o>viw" .. mc_visual("AddMatches"), { desc = "Change All Occurrences" } },
    { "n", "<C-F2>", "viw" .. mc_visual("AddMatches"), { desc = "Change All Occurrences" } },
    { S, "<C-F2>", "<C-g>" .. mc_visual("AddMatches"), { desc = "Change All Occurrences" } },
    { X, "<C-F2>", mc_visual("AddMatches"), { desc = "Change All Occurrences" } },
    { { I, "n" }, "<C-A-Up>", "<Cmd>MultipleCursorsAddUp<CR>", { desc = "Add Cursor Above" } },
    { { I, "n" }, "<C-A-Down>", "<Cmd>MultipleCursorsAddDown<CR>", { desc = "Add Cursor Below" } },

    { ALL, "<Esc>", escape, { desc = "Escape" } },
    { S, "<Esc>", "<C-g><Esc>", { desc = "Clear Selection" } },

    { ANY, "<C-f>", find_in_file, { desc = "Find" } },
    { ANY, "<C-h>", find_replace_file, { desc = "Replace" } },
    { ANY, "<F3>", jump("n"), { desc = "Find Next" } },
    { ANY, "<S-F3>", jump("N"), { desc = "Find Previous" } },
    { ANY, "<C-g>", with_normal(goto_line), { desc = "Go to Line" } },
    { ANY, "<A-Left>", jump("<C-o>"), { desc = "Go Back" } },
    { ANY, "<A-Right>", jump("<C-i>"), { desc = "Go Forward" } },

    { ANY, "<F12>", with_normal(vim.lsp.buf.definition), { desc = "Go to Definition" } },
    {
      ANY,
      "<A-F12>",
      with_normal(function()
        Snacks.picker.lsp_definitions()
      end),
      { desc = "Peek Definition" },
    },
    {
      ANY,
      "<S-F12>",
      with_normal(function()
        Snacks.picker.lsp_references()
      end),
      { desc = "Go to References" },
    },
    { ANY, "<F2>", with_normal(vim.lsp.buf.rename), { desc = "Rename Symbol" } },
    { ANY, "<C-.>", with_normal(vim.lsp.buf.code_action), { desc = "Quick Fix" } },
    {
      ANY,
      "<S-A-f>",
      with_normal(function()
        LazyVim.format({ force = true })
      end),
      { desc = "Format Document" },
    },
    {
      ANY,
      "<F8>",
      with_normal(function()
        vim.diagnostic.jump({ count = 1, float = true })
      end),
      { desc = "Go to Next Problem" },
    },
    {
      ANY,
      "<S-F8>",
      with_normal(function()
        vim.diagnostic.jump({ count = -1, float = true })
      end),
      { desc = "Go to Previous Problem" },
    },
    {
      ANY,
      "<C-S-o>",
      with_normal(function()
        Snacks.picker.lsp_symbols()
      end),
      { desc = "Go to Symbol in Editor" },
    },
    {
      ALL,
      "<C-LeftMouse>",
      function()
        require("lazycode.mouse").goto_definition()
      end,
      { desc = "Go to Definition" },
    },
    { { I, "n" }, "<A-LeftMouse>", "<Cmd>MultipleCursorsMouseAddDelete<CR>", { desc = "Add Cursor at Click" } },

    -- More of VS Code's default keyboard shortcuts.
    { I, "<C-l>", "<C-o>V<C-g>", { desc = "Expand Line Selection" } },
    { "n", "<C-l>", "V<C-g>", { desc = "Expand Line Selection" } },
    { S, "<C-l>", "<C-g>j<C-g>", { desc = "Expand Line Selection" } },
    { X, "<C-l>", "j", { desc = "Expand Line Selection" } },
    { ALL, "<C-Bar>", "<Cmd>normal! %<CR>", { desc = "Go to Bracket" } },
    { ANY, "<A-z>", "<Cmd>set wrap!<CR>", { desc = "Toggle Word Wrap" } },
    { ANY, "<C-k><C-x>", "<Cmd>keeppatterns %s/\\s\\+$//e<CR>", { desc = "Trim Trailing Whitespace" } },
    -- shortcut: both toggle the comment, while VS Code only adds or only removes; split them if asked.
    { ALL, "<C-k><C-c>", "<Cmd>normal gcc<CR>", { desc = "Add Line Comment" } },
    { { X, S }, "<C-k><C-c>", "<C-g>gcgv<C-g>", { remap = true, desc = "Add Line Comment" } },
    { ALL, "<C-k><C-u>", "<Cmd>normal gcc<CR>", { desc = "Remove Line Comment" } },
    { { X, S }, "<C-k><C-u>", "<C-g>gcgv<C-g>", { remap = true, desc = "Remove Line Comment" } },
    { ANY, "<C-{>", "<Cmd>normal! zc<CR>", { desc = "Fold" } },
    { ANY, "<C-}>", "<Cmd>normal! zo<CR>", { desc = "Unfold" } },
    { ANY, "<C-k><C-[>", "<Cmd>normal! zC<CR>", { desc = "Fold Recursively" } },
    { ANY, "<C-k><C-]>", "<Cmd>normal! zO<CR>", { desc = "Unfold Recursively" } },
    { ANY, "<C-k><C-0>", "<Cmd>normal! zM<CR>", { desc = "Fold All" } },
    { ANY, "<C-k><C-j>", "<Cmd>normal! zR<CR>", { desc = "Unfold All" } },
    { { I, "n", S }, "<C-S-Space>", vim.lsp.buf.signature_help, { desc = "Trigger Parameter Hints" } },
    { ANY, "<C-k><C-i>", with_normal(vim.lsp.buf.hover), { desc = "Show Hover" } },
    {
      ANY,
      "<C-F12>",
      with_normal(function()
        Snacks.picker.lsp_implementations()
      end),
      { desc = "Go to Implementations" },
    },
    {
      ANY,
      "<C-k><F12>",
      with_normal(function()
        vim.cmd.vsplit()
        vim.lsp.buf.definition()
      end),
      { desc = "Open Definition to the Side" },
    },
    {
      ALL,
      "<C-k><C-f>",
      function()
        LazyVim.format({ force = true })
      end,
      { desc = "Format Document" },
    },
    { { X, S }, "<C-k><C-f>", "<C-g><Cmd>lua vim.lsp.buf.format()<CR>", { desc = "Format Selection" } },
  }
end

function M.attach(buf)
  if M.vim_mode or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  if attached[buf] and vim.fn.maparg("<C-z>", "i", false, true).buffer == buf then
    return
  end
  require("lazycode.platform").clear_leader(buf)
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
