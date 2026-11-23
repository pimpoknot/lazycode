import json, os, subprocess, sys, tempfile, time

base = None
work = tempfile.mkdtemp(prefix="lazycode-real-", dir=base)
repo = os.path.join(work, "repo")
os.mkdir(repo)
nsock, ksock = os.path.join(work, "n.sock"), "@lc-e2e-%d" % os.getpid()
sample, other = os.path.join(repo, "sample.txt"), os.path.join(repo, "other.txt")
open(sample, "w").write("alpha beta\nbeta gamma\nthird line\n")
open(other, "w").write("other file\n")
for cmd in (["init", "-q"], ["config", "user.name", "e2e"], ["config", "user.email", "e2e@example.invalid"], ["config", "commit.gpgsign", "false"]):
    subprocess.run(["git"] + cmd, cwd=repo, check=True)

env = dict(os.environ, NVIM_APPNAME="lazycode", LC_CLIP=os.path.join(work,"clip"))
kitty = subprocess.Popen(["kitty", "--config", os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "lazycode/assets/kitty.conf"),
    "-o", "allow_remote_control=yes", "--listen-on", "unix:" + ksock, "--class", "lazycode-test",
    "--directory", repo, "nvim", "--cmd","lua vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..vim.env.LC_CLIP},['*']={'sh','-c','cat > '..vim.env.LC_CLIP}},paste={['+']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'},['*']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'}}}", "--listen", nsock, sample], env=env,
    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

def _crash(t, v, tb):
    import traceback; traceback.print_exception(t, v, tb); finish(4)
sys.excepthook = _crash

def lua(code):
    expr = "luaeval('vim.json.encode((function() " + code.replace("'", "''") + " end)())')"
    try:
        r = subprocess.run(["nvim", "--clean", "--headless", "--server", nsock, "--remote-expr", expr],
                           capture_output=True, text=True, timeout=8)
    except subprocess.TimeoutExpired:
        print("HUNG at:", code); finish(2)
    out = (r.stdout + r.stderr).strip()
    try:
        return json.loads(out)
    except Exception:
        return out

def finish(code):
    try:
        subprocess.run(["nvim", "--clean", "--headless", "--server", nsock, "--remote-expr", "execute('qa!')"], capture_output=True, timeout=3)
    except Exception:
        pass
    time.sleep(.3)
    kitty.terminate()
    os._exit(code)

for _ in range(80):
    time.sleep(.25)
    if kitty.poll() is not None:
        print("kitty exited:", kitty.stderr.read()[:500]); finish(3)
    if os.path.exists(nsock) and lua("return package.loaded['lazycode.sidebar'] ~= nil and vim.o.keymodel") == "startsel,stopsel":
        break
else:
    print("did not start"); finish(3)
time.sleep(2)

results = []
def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n   got : {got}\n   want: {want}"))
    if not ok:
        print("   state:", lua("local e=require('lazycode.editing'); return {m=vim.api.nvim_get_mode().mode, st=vim.fn.state(), ft=vim.bo.filetype, bt=vim.bo.buftype, mc=e.mc_active==true, n=e.cursor_count(), mod=vim.bo.modifiable}"))

def _kc(args):
    r = subprocess.run(["kitty", "@", "--to", "unix:" + ksock] + args, capture_output=True, text=True)
    if r.returncode:
        print("kitty @ failed:", r.stderr[:300]); finish(5)

def key(*names, wait=.5):
    _kc(["send-key"] + list(names))
    time.sleep(wait * 2.5)

def text_in(s, wait=.4):
    _kc(["send-text", s])
    time.sleep(wait * 2.5)

def mouse(button, action, row, col, mod=""):
    lua(f"vim.api.nvim_input_mouse({json.dumps(button)},{json.dumps(action)},{json.dumps(mod)},0,{row},{col}) return 1")
    time.sleep(.06)

def click(row, col, mod="", button="left", wait=.5):
    mouse(button, "press", row, col, mod); mouse(button, "release", row, col, mod); time.sleep(wait * 2.5)

def clicks(n, row, col):
    lua(f"for _=1,{n} do vim.api.nvim_input_mouse('left','press','',0,{row},{col}) vim.api.nvim_input_mouse('left','release','',0,{row},{col}) end return 1")
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
        lua("vim.cmd.stopinsert() return 1"); time.sleep(.2)
    w = editor_win()
    lua(f"vim.api.nvim_set_current_win({w}) if vim.api.nvim_buf_get_name(0) ~= {json.dumps(path)} then vim.cmd.edit({json.dumps(path)}) end return 1")
    time.sleep(.3)

def reset():
    if mode() in ("s", "v", "V"):
        key("escape", wait=.2)
    focus()
    lua("vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha beta','beta gamma','third line'}) vim.api.nvim_win_set_cursor(0,{1,0}) return 1")
    for _ in range(30):
        time.sleep(.05)
        if mode() == "i":
            break
        lua("vim.cmd.startinsert() return 1")
    time.sleep(.15)

def text_cell(line, col):
    """Zero-based screen cell of a buffer position in the editor window."""
    w = editor_win()
    p = lua(f"return vim.fn.screenpos({w},{line},{col})")
    return p["row"] - 1, p["col"] - 1

# --- Real keyboard through kitty
check("kitty opens ready to type", mode(), "i")
reset(); key("ctrl+shift+g", wait=2.5); check("kitty: Ctrl+Shift+G opens lazygit", ft(), "snacks_terminal")
key("ctrl+shift+e", wait=1); check("kitty: Ctrl+Shift+E opens Explorer", active(), "explorer")
key("ctrl+shift+f", wait=1); check("kitty: Ctrl+Shift+F opens Search", active(), "search")
key("ctrl+shift+e", wait=1)
reset(); key("ctrl+shift+p", wait=.8); check("kitty: Ctrl+Shift+P opens palette", ft(), "snacks_picker_input"); key("escape", wait=.5)
reset(); key("ctrl+p", wait=.8); check("kitty: Ctrl+P opens files", ft(), "snacks_picker_input"); key("escape", wait=.5)
reset(); key("ctrl+shift+k", wait=.4); check("kitty: Ctrl+Shift+K", text(), ["beta gamma", "third line"])
reset(); key("alt+down", wait=.4); check("kitty: Alt+Down", text()[:2], ["beta gamma", "alpha beta"])
reset(); key("shift+right", "shift+right", wait=.3); check("kitty: Shift+arrows", mode(), "s"); text_in("Z"); check("kitty: typing replaces", text()[0], "Zpha beta")
reset(); key("ctrl+a", wait=.4); check("kitty: Ctrl+A", mode(), "s"); key("escape", wait=.3)
reset(); key("ctrl+z", wait=.3); check("kitty: Ctrl+Z does not suspend", kitty.poll() is None and mode() == "i", True)
reset(); key("ctrl+`", wait=1); check("kitty: Ctrl+` opens terminal", lua("return vim.bo.buftype"), "terminal"); key("ctrl+`", wait=.6)
reset(); key("ctrl+k", "ctrl+s", wait=.8); check("kitty: Ctrl+K Ctrl+S opens shortcuts", ft(), "snacks_picker_input"); key("escape", wait=.5)

# --- Mouse
reset(); r, c = text_cell(1, 1); r2, c2 = text_cell(1, 6)
mouse("left", "press", r, c); mouse("left", "drag", r, c + 2); mouse("left", "drag", r, c2); mouse("left", "release", r, c2); time.sleep(.3)
check("mouse: drag selects", mode(), "s"); text_in("Q"); check("mouse: typing replaces drag", text()[0], "Q beta")
reset(); r, c = text_cell(2, 3); click(r, c); check("mouse: click places cursor", lua("return vim.api.nvim_win_get_cursor(0)"), [2, 2]); check("mouse: click keeps typing mode", mode(), "i")
reset(); r, c = text_cell(2, 2); clicks(2, r, c)
check("mouse: double click selects", mode(), "s"); text_in("W"); check("mouse: double click word", text()[1], "W gamma")
reset(); r, c = text_cell(2, 2); clicks(3, r, c)
check("mouse: triple click selects", mode() in ("S", "s"), True); key("escape", wait=.3)
reset(); r, c = text_cell(2, 1); click(r, c, "A", wait=.5); check("mouse: Alt+Click adds cursor", lua("return require('lazycode.editing').cursor_count()") >= 2, True); key("escape", wait=.4)
reset(); lua("_G.__def=0 vim.lsp.buf.definition=function() _G.__def=_G.__def+1 end return 1"); r, c = text_cell(2, 2); click(r, c, "C")
check("mouse: Ctrl+Click goes to definition", lua("return _G.__def"), 1)
check("context menu", lua("return vim.fn.menu_info('PopUp.Copy','i').rhs ~= nil"), True)
reset(); r, c = text_cell(1, 2)
lua(f"vim.api.nvim_input_mouse('right','press','',0,{r},{c}) vim.api.nvim_input_mouse('right','release','',0,{r},{c}) return 1"); time.sleep(1.5)
screen = subprocess.run(["kitty", "@", "--to", "unix:" + ksock, "get-text"], capture_output=True, text=True).stdout
check("mouse: right click opens menu", all(w in screen for w in ("Cut", "Copy", "Paste", "Rename")), True); key("escape", wait=.4)

# Activity bar
def bar():
    return lua("""for _,x in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(x)].filetype=='lazycode_bar' then
      local p=vim.api.nvim_win_get_position(x) return {p[1],p[2]} end end""")
reset(); b = bar()
click(b[0] + 5, b[1] + 1, wait=1.5); check("mouse: icon opens lazygit", active(), "git")
click(b[0] + 3, b[1] + 1, wait=1); check("mouse: icon opens Search", active(), "search")
click(b[0] + 1, b[1] + 1, wait=1); check("mouse: icon opens Explorer", active(), "explorer")

# Single click in the Explorer
info = lua("""local p=Snacks.picker.get({source='explorer'})[1]
  for i,it in ipairs(p.list.items) do if it.file and it.file:match('other%.txt$') then
    local row=p.list:idx2row(i) local s=vim.fn.win_screenpos(p.list.win.win) return {s[1]-1+row-1, s[2]+3} end end""")
if isinstance(info, list):
    click(info[0], info[1], wait=.8); check("mouse: single click opens file", name(), "other.txt"); check("opened file ready to type", mode(), "i")
else:
    check("mouse: explorer item", info, "list")

# Tabs and statusline
tab = lua("""for c=1,vim.o.columns-5 do local s='' for j=0,4 do s=s..vim.fn.screenstring(1,c+j) end if s=='sampl' then return c-1 end end""")
if isinstance(tab, int):
    click(0, tab, wait=.6); check("mouse: tab click", name(), "sample.txt")
else:
    check("mouse: tab found", tab, "column")
reset(); click(lua("return vim.o.lines - 1 - vim.o.cmdheight"), 2, wait=.5)
check("mouse: clicking CODE enables Vim", lua("return require('lazycode.editing').vim_mode"), True)
click(lua("return vim.o.lines - 1 - vim.o.cmdheight"), 2, wait=.5)
check("mouse: clicking again disables Vim", lua("return require('lazycode.editing').vim_mode"), False)

# --- Real lazygit: stage + commit
reset(); lua("vim.cmd('silent! %bwipeout!') return 1") if False else None
lua("vim.cmd.write() return 1")
key("ctrl+shift+g", wait=1.5)
if active() != "git":
    key("ctrl+shift+g", wait=1.5)
check("lazygit focused", mode(), "t")
def snap(label):
    t = subprocess.run(["kitty", "@", "--to", "unix:" + ksock, "get-text"], capture_output=True, text=True).stdout
    print(f"=== {label}"); print("\n".join(l[:56] for l in t.splitlines()[:30]))
def until(fn, limit=8):
    t=time.time()
    while time.time()-t<limit:
        v=fn()
        if v: return v
        time.sleep(.05)
    return fn()
screen_text=lambda: subprocess.run(["kitty","@","--to","unix:"+ksock,"get-text"],capture_output=True,text=True).stdout
gitout=lambda *a: subprocess.run(["git"]+list(a),cwd=repo,capture_output=True,text=True).stdout
if not until(lambda: "Files" in screen_text() and "Stash" in screen_text()):
    print("LAZYGIT DID NOT DRAW"); print(screen_text()[:900])
_kc(["send-key","2"]); time.sleep(.5)
_kc(["send-key","a"])
until(lambda: sorted(gitout("diff","--cached","--name-only").split())==["other.txt","sample.txt"])
staged = gitout("diff","--cached","--name-only").split()
check("lazygit: stage all", sorted(staged), ["other.txt", "sample.txt"])
_kc(["send-key","c"])
if not until(lambda: "ommit summary" in screen_text()):
    print("POPUP DID NOT OPEN"); print("\n".join(l[:60] for l in screen_text().splitlines()[:34]))
_kc(["send-text","commit e2e"]); time.sleep(.5); _kc(["send-key","enter"])
until(lambda: gitout("log","--format=%s").strip()=="commit e2e")
log = subprocess.run(["git", "log", "--format=%s"], cwd=repo, capture_output=True, text=True).stdout.strip()
check("lazygit: stage e commit", log, "commit e2e")
check("lazygit: clean tree", subprocess.run(["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True).stdout.strip(), "")

msgs = str(lua("return vim.api.nvim_exec2('messages',{output=true}).output"))
bad = [l for l in msgs.splitlines() if "E5" in l or "Error" in l or "stack traceback" in l]
if bad: print("MESSAGES:\n" + msgs[-1800:])
check("no errors in :messages", bad, [])
print(f"\n{sum(results)}/{len(results)} passed")
finish(0 if all(results) else 1)
