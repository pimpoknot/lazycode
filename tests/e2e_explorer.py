import glob, json, os, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appctl
base = None
work = tempfile.mkdtemp(prefix="lazycode-exp-", dir=os.environ.get("LC_BASE", base))
proj = os.path.join(work, "proj"); os.makedirs(proj + "/src"); os.makedirs(proj + "/.config/app")
uniq = f"lc-del-{os.getpid()}.txt"
for f, t in {"a.txt":"A\n","b.txt":"B\n","c.txt":"C\n",uniq:"D\n",".env":"X=1\n",".gitignore":"ignored.log\n","ignored.log":"i\n",".config/app/x":"x\n","src/keep.txt":"k\n"}.items():
    open(os.path.join(proj, f), "w").write(t)
subprocess.run(["git", "init", "-q"], cwd=proj, check=True)
nsock = os.path.join(tempfile.gettempdir(), "lce%d.sock" % os.getpid())
args = sys.argv[1:] or []
app = appctl.App(["--cmd","lua vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..vim.env.LC_CLIP},['*']={'sh','-c','cat > '..vim.env.LC_CLIP}},paste={['+']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'},['*']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'}}}","--listen",nsock]+args, proj, size=(120, 36),
    env=dict(os.environ, NVIM_APPNAME="lazycode", LAZYCODE_START="", LC_CLIP=os.path.join(work,"clip")))
def finish(c):
    try: subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr","execute('qa!')"],capture_output=True,timeout=3)
    except Exception: pass
    time.sleep(.3); app.close()
    try: os.unlink(nsock)
    except OSError: pass
    __import__('shutil').rmtree(work, ignore_errors=True); os._exit(c)
import signal; signal.signal(signal.SIGTERM, lambda *_: finish(9))
sys.excepthook = lambda t,v,tb: (__import__("traceback").print_exception(t,v,tb), finish(4))
def lua(code, limit=8):
    expr = "luaeval('vim.json.encode((function() " + code.replace("'", "''") + " end)())')"
    try: r = subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr",expr],capture_output=True,text=True,timeout=limit)
    except subprocess.TimeoutExpired: print("HUNG at:", code[:120]); print(gettext()[:900]); finish(2)
    o = (r.stdout+r.stderr).strip()
    try: return json.loads(o)
    except Exception: return o
kc = app.kc
gettext = lambda: kc(["get-text"])
def key(*k, wait=.45): kc(["send-key"]+list(k)); time.sleep(wait)
def until(fn, limit=5):
    t=time.time()
    while time.time()-t<limit:
        v=fn()
        if v: return v
        time.sleep(.04)
    return fn()
ftype=lambda: lua("return vim.bo.filetype")
imode=lambda: lua("return vim.api.nvim_get_mode().mode")
def typ(s, wait=.15):
    if not until(lambda: ftype()=="snacks_input" and imode()=="i"):
        print("input did not open for", repr(s)); print(gettext()[:700]); finish(7)
    kc(["send-text", s]); time.sleep(wait)
def submit():
    key("enter",wait=.05); until(lambda: ftype()!="snacks_input")
    time.sleep(.25)
def dialog(choice):
    if not until(lambda: ftype()=="snacks_picker_input" and lua("local p=Snacks.picker.get({source='select'})[1]; return p ~= nil and #p.list.items==2")):
        print("dialog did not open"); print(gettext()[:700]); finish(8)
    if choice==2:
        key("down",wait=.03); until(lambda: lua("local p=Snacks.picker.get({source='select'})[1]; local i=p and p:current(); return i ~= nil and i.idx==2"))
        key("enter",wait=.05)
    else:
        key("escape",wait=.05)
    until(lambda: not lua("return #Snacks.picker.get({source='select'})>0"))
    time.sleep(.2)
T0=time.time()
for _ in range(80):
    time.sleep(.25)
    if os.path.exists(nsock) and lua("return package.loaded['lazycode.explorer'] ~= nil and #Snacks.picker.get({source='explorer'})", 25) == 1: break
else: print("did not start"); finish(3)
print("ready in %.1fs" % (time.time()-T0)); time.sleep(1.5)
res=[]
def check(n,g,w):
    ok=g==w; res.append(ok); print(("PASS " if ok else "FAIL ")+n+("" if ok else f"\n   got : {g}\n   want: {w}"))
P = lambda r: os.path.exists(os.path.join(proj,r))
names = lambda: lua("local p=Snacks.picker.get({source='explorer'})[1]; local o={} for _,i in ipairs(p.list.items) do o[#o+1]=vim.fn.fnamemodify(i.file,':t') end return o")
def cell(name):
    for _ in range(25):
        c = lua("""local p=Snacks.picker.get({source='explorer'})[1]
        for i,it in ipairs(p.list.items) do if vim.fn.fnamemodify(it.file,':t')==%s then
        local s=vim.fn.win_screenpos(p.list.win.win); return {s[1]-1+p.list:idx2row(i)-1, s[2]+7} end end return false""" % json.dumps(name))
        if c: return c
        time.sleep(.1)
    print("missing item", name); finish(5)
ORDER=["New File","New Folder","Open in Terminal","Reveal","Cut","Copy","Paste","Copy Path","Copy Relative Path","Rename","Delete"]
def sgr(btn, row, col, press):
    kc(["send-text", "\\x1b[<%d;%d;%d%s" % (btn, col+1, row+1, "M" if press else "m")])
    time.sleep(.05)
def rclick(row,col):
    until(lambda: "Reveal" not in gettext(), 2)
    sgr(2,row,col,True); sgr(2,row,col,False)
    if not until(lambda: "Reveal" in gettext(), 3):
        print("menu did not open"); print(gettext()[:900]); finish(6)
    time.sleep(.1)
import re
def menu(name, label, order=ORDER):
    r,c = cell(name); rclick(r,c)
    pat = re.compile(re.escape(label) + r"(?!\.)" + (r"(?! (Path|Relative))" if label=="Copy" else "") + "")
    for attempt in range(16):
        for row,line in enumerate(gettext().splitlines()):
            m = pat.search(line)
            if m:
                sgr(0,row,m.start()+1,True); sgr(0,row,m.start()+1,False); until(lambda: "Reveal" not in gettext(), 3); time.sleep(.12)
                return
        key("down", wait=.06)
    print("ITEM NOT FOUND", label); print(gettext()[:1500]); finish(6)
check("hidden file .env", ".env" in names(), True); check("hidden folder .config", ".config" in names(), True)
check("ignored file visible", "ignored.log" in names(), True); check(".git hidden", ".git" in names(), False)
check("hidden file not dimmed", lua("local p=Snacks.picker.get({source='explorer'})[1]; for _,i in ipairs(p.list.items) do if i.file:match('%.env$') then return i.filename_hl ~= nil and i.filename_hl ~= 'SnacksPickerPathHidden' end end"), True)
lua("Snacks.picker.get({source='explorer'})[1]:focus('list') return 1"); time.sleep(.4)
check("cursor hidden in Explorer (option)", lua("return vim.o.guicursor"), "a:LazyCodeHiddenCursor")
out = kc(["get-text","--add-cursor"]); check("cursor hidden on screen", "\x1b[?25l" in out, True)
r,c = cell("src"); rclick(r,c); s=gettext()
ok=all(w in s for w in ("New File","New Folder","Cut","Copy","Rename","Delete"))
if not ok: print(s[:1700])
check("item menu", ok, True); key("escape")
h = lua("return vim.o.lines"); rclick(h-4, c); s=gettext()
check("empty area menu", "New File" in s and "Rename" not in s, True); key("escape")
menu("src","New File"); typ("new.txt"); submit(); until(lambda: lua("return vim.fn.expand('%:t')")=="new.txt")
check("creates file in folder", P("src/new.txt"), True); check("opens created file", lua("return vim.fn.expand('%:t')"), "new.txt"); check("file ready to type", until(lambda: imode()=="i") and imode(), "i")
check("cursor returns in editor", until(lambda: lua("return vim.o.guicursor") != "a:LazyCodeHiddenCursor"), True)
menu("src","New File"); typ("canceled.txt"); key("escape",wait=.05); check("one Esc cancels prompt", bool(until(lambda: ftype()!="snacks_input")) and not P("src/canceled.txt"), True)
menu("src","New Folder"); typ("sub"); submit(); check("creates folder", bool(until(lambda: os.path.isdir(proj+"/src/sub"))), True)
menu("a.txt","Copy"); menu("src","Paste"); check("copy and paste", bool(until(lambda: P("src/a.txt"))) and P("a.txt"), True)
menu("src","Paste"); check("pasting again makes a copy", bool(until(lambda: P("src/a copy.txt"))), True)
menu("b.txt","Cut"); menu("src","Paste"); check("cut and paste", bool(until(lambda: P("src/b.txt") and not P("b.txt"))), True)
menu("c.txt","Rename"); typ("\x15d.txt"); submit(); check("rename", bool(until(lambda: P("d.txt") and not P("c.txt"))), True)
menu("d.txt","Copy Path"); check("copy path", until(lambda: lua("return vim.fn.getreg('+')")==os.path.join(proj,"d.txt")), True)
menu("d.txt","Copy Relative Path"); check("relative path", until(lambda: lua("return vim.fn.getreg('+')")=="d.txt"), True)
menu(uniq,"Delete"); dialog(1); check("cancel does not delete", P(uniq), True)
menu(uniq,"Delete"); dialog(2)
if "LC_BASE" in os.environ:
    check("delete goes to trash", bool(until(lambda: not P(uniq))), True)
    trash = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "Trash")
    hit = glob.glob(os.path.join(trash, "files", glob.escape(uniq) + "*"))
    check("item is in trash", len(hit), 1)
    for path in hit:
        os.remove(path)
        info = os.path.join(trash, "info", os.path.basename(path) + ".trashinfo")
        if os.path.exists(info):
            os.remove(info)
else:
    until(lambda: "Permanently" in gettext()); check("without trash it asks first", P(uniq) and "Permanently" in gettext(), True)
    dialog(1); check("cancel permanent delete", P(uniq), True)
    menu(uniq,"Delete"); dialog(2); until(lambda: "Permanently" in gettext()); dialog(2)
    check("permanent delete confirmed", bool(until(lambda: not P(uniq))), True)
until(lambda: uniq not in names() or P(uniq))
lua("local p=Snacks.picker.get({source='explorer'})[1] p:focus('list') for i,it in ipairs(p.list.items) do if it.file:match('/d%.txt$') then p.list:move(i,true) end end return 1"); until(lambda: ftype()=="snacks_picker_list"); time.sleep(.15)
key("f2",wait=.05); typ("\x15e.txt"); submit(); check("F2 renames", bool(until(lambda: P("e.txt"))), True)
until(lambda: ftype()=="snacks_picker_list"); until(lambda: lua("local p=Snacks.picker.get({source='explorer'})[1]; local i=p:current(); return i ~= nil and i.file:match('/e%.txt$') ~= nil")); key("ctrl+c",wait=.15); key("ctrl+v",wait=.05); check("Ctrl+C/V no Explorer", bool(until(lambda: P("e copy.txt"))), True)
key("escape",wait=.3); check("Esc does not close Explorer", lua("return #Snacks.picker.get({source='explorer'})"), 1)
lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.api.nvim_win_get_config(w).relative=='' and vim.bo[vim.api.nvim_win_get_buf(w)].buftype=='' then vim.api.nvim_set_current_win(w) break end end return 1"); until(lambda: imode()=="i")
term=lambda: lua("return vim.bo.buftype")=="terminal"
key("ctrl+`",wait=.05); check("terminal opens", bool(until(term)), True); check("Explorer stays with terminal", lua("return #Snacks.picker.get({source='explorer'})"), 1)
until(lambda: imode()=="t"); key("ctrl+`",wait=.05); until(lambda: not term()); time.sleep(.2); key("ctrl+`",wait=.05); check("terminal reopens", bool(until(term)), True)
msgs=str(lua("return vim.api.nvim_exec2('messages',{output=true}).output")); bad=[l for l in msgs.splitlines() if "E5" in l or "Error" in l or "traceback" in l]
if bad: print(msgs[-1200:])
check("no errors", bad, [])
print(f"{sum(res)}/{len(res)} passed"); finish(0 if all(res) else 1)
