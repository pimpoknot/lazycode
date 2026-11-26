import json, os, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appctl

base = None
work = tempfile.mkdtemp(prefix="lazycode-real-", dir=base)
repo = os.path.join(work, "repo")
os.mkdir(repo)
nsock = os.path.join(work, "n.sock")
sample, other = os.path.join(repo, "sample.txt"), os.path.join(repo, "other.txt")
open(sample, "w").write("alpha beta\nbeta gamma\nthird line\n")
open(other, "w").write("other file\n")
for cmd in (
    ["init", "-q"],
    ["config", "user.name", "e2e"],
    ["config", "user.email", "e2e@example.invalid"],
    ["config", "commit.gpgsign", "false"],
):
    subprocess.run(["git"] + cmd, cwd=repo, check=True)

env = dict(os.environ, NVIM_APPNAME="lazycode", LC_CLIP=os.path.join(work, "clip"))
app = appctl.App(
    [
        "--cmd",
        "lua vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..vim.env.LC_CLIP},['*']={'sh','-c','cat > '..vim.env.LC_CLIP}},paste={['+']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'},['*']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'}}}",
        "--listen",
        nsock,
        sample,
    ],
    repo,
    env=dict(env, LAZYCODE_START=""),
    stderr=subprocess.PIPE,
)
proc = app.proc


def _crash(t, v, tb):
    import traceback

    traceback.print_exception(t, v, tb)
    finish(4)


sys.excepthook = _crash


def lua(code):
    expr = (
        "luaeval('vim.json.encode((function() " + code.replace("'", "''") + " end)())')"
    )
    try:
        r = subprocess.run(
            ["nvim", "--clean", "--headless", "--server", nsock, "--remote-expr", expr],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        print("HUNG at:", code)
        finish(2)
    out = (r.stdout + r.stderr).strip()
    try:
        return json.loads(out)
    except Exception:
        return out


def finish(code):
    try:
        subprocess.run(
            [
                "nvim",
                "--clean",
                "--headless",
                "--server",
                nsock,
                "--remote-expr",
                "execute('qa!')",
            ],
            capture_output=True,
            timeout=3,
        )
    except Exception:
        pass
    time.sleep(0.3)
    app.close()
    os._exit(code)


for _ in range(80):
    time.sleep(0.25)
    if proc.poll() is not None:
        print("app exited:", proc.stderr.read()[:500])
        finish(3)
    if (
        os.path.exists(nsock)
        and lua("return package.loaded['lazycode.sidebar'] ~= nil and vim.o.keymodel")
        == "startsel,stopsel"
    ):
        break
else:
    print("did not start")
    finish(3)
time.sleep(2)

results = []


def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(
        ("PASS " if ok else "FAIL ")
        + name
        + ("" if ok else f"\n   got : {got}\n   want: {want}")
    )
    if not ok:
        print(
            "   state:",
            lua(
                "local e=require('lazycode.editing'); return {m=vim.api.nvim_get_mode().mode, st=vim.fn.state(), ft=vim.bo.filetype, bt=vim.bo.buftype, mc=e.mc_active==true, n=e.cursor_count(), mod=vim.bo.modifiable}"
            ),
        )


def _kc(args):
    app.kc(args)


def key(*names, wait=0.5):
    _kc(["send-key"] + list(names))
    time.sleep(wait * 2.5)


def text_in(s, wait=0.4):
    _kc(["send-text", s])
    time.sleep(wait * 2.5)


def mouse(button, action, row, col, mod=""):
    lua(
        f"vim.api.nvim_input_mouse({json.dumps(button)},{json.dumps(action)},{json.dumps(mod)},0,{row},{col}) return 1"
    )
    time.sleep(0.06)


def click(row, col, mod="", button="left", wait=0.5):
    mouse(button, "press", row, col, mod)
    mouse(button, "release", row, col, mod)
    time.sleep(wait * 2.5)


def clicks(n, row, col):
    lua(
        f"for _=1,{n} do vim.api.nvim_input_mouse('left','press','',0,{row},{col}) vim.api.nvim_input_mouse('left','release','',0,{row},{col}) end return 1"
    )
    time.sleep(1.2)


mode = lambda: lua("return vim.api.nvim_get_mode().mode")
ft = lambda: lua("return vim.bo.filetype")
name = lambda: lua("return vim.fn.expand('%:t')")
text = lambda: lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
active = lambda: lua("return require('lazycode.sidebar').active")


def editor_win(path=sample):
    return lua("""for _,w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative=='' and vim.bo[vim.api.nvim_win_get_buf(w)].buftype=='' then return w end end""")


def focus(path=sample):
    if mode() == "t":
        lua("vim.cmd.stopinsert() return 1")
        time.sleep(0.2)
    w = editor_win()
    lua(
        f"vim.api.nvim_set_current_win({w}) if vim.api.nvim_buf_get_name(0) ~= {json.dumps(path)} then vim.cmd.edit({json.dumps(path)}) end return 1"
    )
    time.sleep(0.3)


def reset():
    if mode() in ("s", "v", "V"):
        key("escape", wait=0.2)
    focus()
    lua(
        "vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha beta','beta gamma','third line'}) vim.api.nvim_win_set_cursor(0,{1,0}) return 1"
    )
    for _ in range(30):
        time.sleep(0.05)
        if mode() == "i":
            break
        lua("vim.cmd.startinsert() return 1")
    time.sleep(0.15)


def text_cell(line, col):
    """Zero-based screen cell of a buffer position in the editor window."""
    w = editor_win()
    p = lua(f"return vim.fn.screenpos({w},{line},{col})")
    return p["row"] - 1, p["col"] - 1


# --- Real keyboard through the app window
check("app opens ready to type", mode(), "i")
reset()
key("ctrl+shift+g", wait=2.5)
check("keyboard: Ctrl+Shift+G opens lazygit", ft(), "snacks_terminal")
key("ctrl+shift+e", wait=1)
check("keyboard: Ctrl+Shift+E opens Explorer", active(), "explorer")
key("ctrl+shift+f", wait=1)
check("keyboard: Ctrl+Shift+F opens Search", active(), "search")
key("ctrl+shift+e", wait=1)
reset()
key("ctrl+shift+p", wait=0.8)
check("keyboard: Ctrl+Shift+P opens palette", ft(), "snacks_picker_input")
key("escape", wait=0.5)
reset()
key("ctrl+p", wait=0.8)
check("keyboard: Ctrl+P opens files", ft(), "snacks_picker_input")
key("escape", wait=0.5)
reset()
key("ctrl+shift+k", wait=0.4)
check("keyboard: Ctrl+Shift+K", text(), ["beta gamma", "third line"])
reset()
key("alt+down", wait=0.4)
check("keyboard: Alt+Down", text()[:2], ["beta gamma", "alpha beta"])
reset()
key("shift+right", "shift+right", wait=0.3)
check("keyboard: Shift+arrows", mode(), "s")
text_in("Z")
check("keyboard: typing replaces", text()[0], "Zpha beta")
reset()
key("ctrl+a", wait=0.4)
check("keyboard: Ctrl+A", mode(), "s")
key("escape", wait=0.3)
reset()
key("ctrl+z", wait=0.3)
check("keyboard: Ctrl+Z does not suspend", proc.poll() is None and mode() == "i", True)
reset()
key("ctrl+`", wait=1)
check("keyboard: Ctrl+` opens terminal", lua("return vim.bo.buftype"), "terminal")
key("ctrl+`", wait=0.6)
reset()
key("ctrl+k", "ctrl+s", wait=0.8)
check("keyboard: Ctrl+K Ctrl+S opens shortcuts", ft(), "snacks_picker_input")
key("escape", wait=0.5)

# --- Mouse
reset()
r, c = text_cell(1, 1)
r2, c2 = text_cell(1, 6)
mouse("left", "press", r, c)
mouse("left", "drag", r, c + 2)
mouse("left", "drag", r, c2)
mouse("left", "release", r, c2)
time.sleep(0.3)
check("mouse: drag selects", mode(), "s")
text_in("Q")
check("mouse: typing replaces drag", text()[0], "Q beta")
reset()
r, c = text_cell(2, 3)
click(r, c)
check(
    "mouse: click places cursor", lua("return vim.api.nvim_win_get_cursor(0)"), [2, 2]
)
check("mouse: click keeps typing mode", mode(), "i")
reset()
r, c = text_cell(2, 2)
clicks(2, r, c)
check("mouse: double click selects", mode(), "s")
text_in("W")
check("mouse: double click word", text()[1], "W gamma")
reset()
r, c = text_cell(2, 2)
clicks(3, r, c)
check("mouse: triple click selects", mode() in ("S", "s"), True)
key("escape", wait=0.3)
reset()
r, c = text_cell(2, 1)
click(r, c, "A", wait=0.5)
check(
    "mouse: Alt+Click adds cursor",
    lua("return require('lazycode.editing').cursor_count()") >= 2,
    True,
)
key("escape", wait=0.4)
reset()
lua("_G.__def=0 vim.lsp.buf.definition=function() _G.__def=_G.__def+1 end return 1")
r, c = text_cell(2, 2)
click(r, c, "C")
check("mouse: Ctrl+Click goes to definition", lua("return _G.__def"), 1)
check("context menu", lua("return vim.fn.menu_info('PopUp.Copy','i').rhs ~= nil"), True)
reset()
r, c = text_cell(1, 2)
lua(
    f"vim.api.nvim_input_mouse('right','press','',0,{r},{c}) vim.api.nvim_input_mouse('right','release','',0,{r},{c}) return 1"
)
time.sleep(1.5)
screen = app.kc(["get-text"])
check(
    "mouse: right click opens menu",
    all(w in screen for w in ("Cut", "Copy", "Paste", "Rename")),
    True,
)
key("escape", wait=0.4)


# Activity bar
def bar():
    return lua("""for _,x in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(x)].filetype=='lazycode_bar' then
      local p=vim.api.nvim_win_get_position(x) return {p[1],p[2]} end end""")


reset()
b = bar()
# Icons sit on bar lines 2, 5, 8, 11, 14 and 17, and answer the lines around them too.
click(b[0] + 7, b[1] + 1, wait=1.5)
check("mouse: icon opens lazygit", active(), "git")
click(b[0] + 5, b[1] + 1, wait=1)
check("mouse: the line below the icon opens Search", active(), "search")
check("Search is a side panel, not a picker", ft(), "grug-far")
text_in("gamma", wait=1)


def result_row():
    for r, line in enumerate(app.screen().splitlines()):
        i = line.find("beta gamma")
        if 0 <= i < 50:
            return r, i


hit = None
for _ in range(40):
    hit = result_row()
    if hit:
        break
    time.sleep(0.25)
if hit:
    click(hit[0], hit[1] + 2, wait=1)
    check(
        "Search: clicking a result opens it",
        (ft(), lua("return vim.api.nvim_win_get_cursor(0)[1]")),
        ("text", 2),
    )
else:
    check("Search: result shown", app.screen(), "a 'beta gamma' result")
click(b[0] + 1, b[1] + 1, wait=1)
check("mouse: icon opens Explorer", active(), "explorer")
check(
    "Search panel closed",
    lua(
        "return #vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'grug-far' end, vim.api.nvim_list_wins())"
    ),
    0,
)
click(b[0] + 10, b[1] + 1, wait=1)
check("mouse: icon opens terminal", lua("return vim.bo.buftype"), "terminal")
check("terminal keeps Explorer", active(), "explorer")
click(b[0] + 10, b[1] + 1, wait=1)
check("mouse: icon hides terminal", lua("return vim.bo.buftype") != "terminal", True)

# Extensions: search and toggle a LazyVim extra, then put lazyvim.json back.
saved = open(
    os.path.join(lua("return vim.fn.stdpath('config')"), "lazyvim.json")
).read()
wanted = lambda: lua(
    "return vim.list_contains(LazyVim.config.json.data.extras, 'lazyvim.plugins.extras.lang.go')"
)
key("ctrl+shift+x", wait=1)
check("keyboard: Ctrl+Shift+X opens Extensions", active(), "extensions")
text_in("lang.go", wait=0.6)
key("enter", wait=0.6)
check("Extensions: Enter enables an extra", wanted(), True)
key("enter", wait=0.6)
check("Extensions: Enter again disables it", wanted(), False)
open(os.path.join(lua("return vim.fn.stdpath('config')"), "lazyvim.json"), "w").write(
    saved
)
click(b[0] + 13, b[1] + 1, wait=1)
check("mouse: icon closes Extensions", active(), None)
click(b[0] + 1, b[1] + 1, wait=1)
check("mouse: icon reopens Explorer", active(), "explorer")

# Single click in the Explorer
info = lua("""local p=Snacks.picker.get({source='explorer'})[1]
  for i,it in ipairs(p.list.items) do if it.file and it.file:match('other%.txt$') then
    local row=p.list:idx2row(i) local s=vim.fn.win_screenpos(p.list.win.win) return {s[1]-1+row-1, s[2]+3} end end""")


def hover(row, col):
    app.kc(["send-text", "\\x1b[<35;%d;%dM" % (col + 1, row + 1)])
    time.sleep(0.4)
    return lua("return require('lazycode.mouse').shape")


if isinstance(info, list):
    check("hover: Explorer item shows a pointer", hover(info[0], info[1]), "pointer")
    r, c = text_cell(1, 3)
    check("hover: editor text shows the text cursor", hover(r, c), "text")
    low = lua(
        "local w=Snacks.picker.get({source='explorer'})[1].list.win.win return vim.fn.win_screenpos(w)[1]-1+vim.api.nvim_win_get_height(w)-1"
    )
    check(
        "hover: empty Explorer space is not clickable", hover(low, info[1]), "default"
    )
    check("hover: bar icon shows a pointer", hover(b[0] + 1, b[1] + 1), "pointer")
    check(
        "hover: empty bar shows the default cursor",
        hover(b[0] + 22, b[1] + 1),
        "default",
    )
    sep = lua(
        "local p=Snacks.picker.get({source='explorer'})[1] local s=vim.fn.win_screenpos(p.list.win.win) return s[2]-1+vim.api.nvim_win_get_width(p.list.win.win)"
    )
    check(
        "hover: panel border shows the resize cursor", hover(info[0], sep), "ew-resize"
    )
    # Dragging that border resizes the Explorer, then dragging back restores it.
    width = lambda: lua(
        "return vim.api.nvim_win_get_width(Snacks.picker.get({source='explorer'})[1].layout.root.win)"
    )

    def drag(row, a, b):
        app.mouse(0, row, a, True)
        time.sleep(0.2)
        for c in range(a, b, 1 if b > a else -1):
            app.mouse(32, row, c + (1 if b > a else -1), True)
            time.sleep(0.05)
        app.mouse(0, row, b, False)
        time.sleep(0.6)

    before = width()
    drag(info[0], sep, sep + 6)
    check("mouse: dragging the panel border resizes the Explorer", width() - before, 6)
    drag(info[0], sep + 6, sep)
    check("mouse: dragging back restores it", width(), before)
    click(info[0], info[1], wait=0.8)
    check("mouse: single click opens file", name(), "other.txt")
    check("opened file ready to type", mode(), "i")
else:
    check("mouse: explorer item", info, "list")

# Smooth scroll with the Explorer open: its floats stop grid_scroll, so Lua reports the scroll.
long = os.path.join(work, "long.txt")
open(long, "w").write("".join(f"line {i}\n" for i in range(300)))
lua(f"vim.cmd.edit({json.dumps(long)}) return 1")
time.sleep(0.8)
check(
    "Explorer is open while scrolling",
    len(lua("return Snacks.picker.get({source='explorer'})")) > 0,
    True,
)
before = app.header()[3]
r, c = lua("local p = vim.fn.screenpos(0, 5, 2) return {p.row - 1, p.col - 1}")
for _ in range(3):
    app.mouse(65, r, c, True)
    time.sleep(0.15)
time.sleep(0.6)
check("scroll: the wheel scrolls the file", lua("return vim.fn.line('w0')") > 1, True)
check("scroll: the window animates it", app.header()[3] > before, True)

# Focus: the window reports it, so FocusGained reloads files changed in other apps.
lua(
    "_G.lc_focus = {} vim.api.nvim_create_autocmd({'FocusGained','FocusLost'}, {callback=function(e) table.insert(_G.lc_focus, e.event) end}) return 1"
)
root = appctl.xdotool("search", "--maxdepth", "0", "--name", "").split()
if root:
    appctl.xdotool("windowfocus", "--sync", root[0])
    time.sleep(0.5)
appctl.xdotool("windowfocus", "--sync", app.window)
time.sleep(0.5)
check(
    "focus: lost and gained reach Neovim",
    lua("return _G.lc_focus"),
    ["FocusLost", "FocusGained"],
)

# Tabs and statusline
tab = lua(
    """for c=1,vim.o.columns-5 do local s='' for j=0,4 do s=s..vim.fn.screenstring(1,c+j) end if s=='sampl' then return c-1 end end"""
)
if isinstance(tab, int):
    check(
        "tabs start after the side panel",
        tab >= lua("return require('lazycode.sidebar').panel_columns() + 4"),
        True,
    )
    click(0, tab, wait=0.6)
    check("mouse: tab click", name(), "sample.txt")
else:
    check("mouse: tab found", tab, "column")
reset()
click(lua("return vim.o.lines - 1 - vim.o.cmdheight"), 2, wait=0.5)
check(
    "mouse: clicking CODE enables Vim",
    lua("return require('lazycode.editing').vim_mode"),
    True,
)
click(lua("return vim.o.lines - 1 - vim.o.cmdheight"), 2, wait=0.5)
check(
    "mouse: clicking again disables Vim",
    lua("return require('lazycode.editing').vim_mode"),
    False,
)

# --- Real lazygit: stage + commit
reset()
lua("vim.cmd('silent! %bwipeout!') return 1") if False else None
lua("vim.cmd.write() return 1")
key("ctrl+shift+g", wait=1.5)
if active() != "git":
    key("ctrl+shift+g", wait=1.5)
check("lazygit focused", mode(), "t")


def snap(label):
    t = app.kc(["get-text"])
    print(f"=== {label}")
    print("\n".join(l[:56] for l in t.splitlines()[:30]))


def until(fn, limit=8):
    t = time.time()
    while time.time() - t < limit:
        v = fn()
        if v:
            return v
        time.sleep(0.05)
    return fn()


screen_text = lambda: app.kc(["get-text"])
gitout = lambda *a: (
    subprocess.run(["git"] + list(a), cwd=repo, capture_output=True, text=True).stdout
)
if not until(lambda: "Files" in screen_text() and "Stash" in screen_text()):
    print("LAZYGIT DID NOT DRAW")
    print(screen_text()[:900])
_kc(["send-key", "2"])
time.sleep(0.5)
_kc(["send-key", "a"])
until(
    lambda: (
        sorted(gitout("diff", "--cached", "--name-only").split())
        == ["other.txt", "sample.txt"]
    )
)
staged = gitout("diff", "--cached", "--name-only").split()
check("lazygit: stage all", sorted(staged), ["other.txt", "sample.txt"])
_kc(["send-key", "c"])
if not until(lambda: "ommit summary" in screen_text()):
    print("POPUP DID NOT OPEN")
    print("\n".join(l[:60] for l in screen_text().splitlines()[:34]))
_kc(["send-text", "commit e2e"])
time.sleep(0.5)
_kc(["send-key", "enter"])
until(lambda: gitout("log", "--format=%s").strip() == "commit e2e")
log = subprocess.run(
    ["git", "log", "--format=%s"], cwd=repo, capture_output=True, text=True
).stdout.strip()
check("lazygit: stage e commit", log, "commit e2e")
check(
    "lazygit: clean tree",
    subprocess.run(
        ["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True
    ).stdout.strip(),
    "",
)

# Reload Window: a new Neovim in the same window, with the same file open.
lua("vim.cmd('silent! wall') vim.g.lazycode_before_reload = 1 return 1")
old = lua("return vim.fn.getpid()")
click(b[0] + 16, b[1] + 1, wait=1)
time.sleep(4)  # the old server is quitting
until(
    lambda: (
        lua("return vim.fn.getpid()") not in (old, None, "")
        and lua("return vim.fn.getpid()") != old
    ),
    20,
)
check("reload: new Neovim", lua("return vim.fn.getpid()") != old, True)
check("reload: window stays open", proc.poll() is None, True)
until(lambda: name() == "sample.txt", 10)
check("reload: file open again", name(), "sample.txt")
check("reload: state is fresh", lua("return vim.g.lazycode_before_reload"), None)
msgs = str(lua("return vim.api.nvim_exec2('messages',{output=true}).output"))
bad = [
    l for l in msgs.splitlines() if "E5" in l or "Error" in l or "stack traceback" in l
]
if bad:
    print("MESSAGES:\n" + msgs[-1800:])
check("no errors in :messages", bad, [])
print(f"\n{sum(results)}/{len(results)} passed")
finish(0 if all(results) else 1)
