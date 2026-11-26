import json, os, re, signal, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appctl
work = tempfile.mkdtemp(prefix="lazycode-wel-", dir=None)
home = work + "/home"; os.makedirs(home + "/projects/app/src"); open(home+"/projects/app/main.txt","w").write("hi\n"); open(home+"/note.txt","w").write("note\n")
up = work + "/up"; subprocess.run(["git","init","-q",up],check=True); open(up+"/README.md","w").write("x\n")
subprocess.run(["git","-C",up,"add","."],check=True); subprocess.run(["git","-C",up,"-c","user.name=e","-c","user.email=e@example.invalid","commit","-qm","i"],check=True)
state = work + "/state"; os.makedirs(state + "/lazycode")
open(state+"/lazycode/lazycode_recent.json","w").write(json.dumps([home+"/projects"]))
nsock=os.path.join(tempfile.gettempdir(),"lcw%d.sock"%os.getpid())
child={"NVIM_APPNAME":"lazycode","LAZYCODE_START":"welcome","HOME":home,"XDG_STATE_HOME":state,"XDG_CONFIG_HOME":os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),"XDG_DATA_HOME":os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),"XDG_CACHE_HOME":work+"/cache","LC_CLIP":work+"/clip"}
clip="lua vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..vim.env.LC_CLIP},['*']={'sh','-c','cat > '..vim.env.LC_CLIP}},paste={['+']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'},['*']={'sh','-c','cat '..vim.env.LC_CLIP..' 2>/dev/null'}}}"
app=appctl.App(["--cmd",clip,"--listen",nsock],home,env=dict(os.environ,**child),size=(120,36))
def finish(c):
    try: subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr","execute('qa!')"],capture_output=True,timeout=3)
    except Exception: pass
    time.sleep(.3); app.close()
    try: os.unlink(nsock)
    except OSError: pass
    __import__('shutil').rmtree(work, ignore_errors=True); os._exit(c)
signal.signal(signal.SIGTERM,lambda *_:finish(9)); sys.excepthook=lambda t,v,tb:(__import__("traceback").print_exception(t,v,tb),finish(4))
def lua(code,limit=8):
    e="luaeval('vim.json.encode((function() "+code.replace("'","''")+" end)())')"
    try: r=subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr",e],capture_output=True,text=True,timeout=limit,env=dict(os.environ))
    except subprocess.TimeoutExpired: print("HUNG:",code[:100]); print(screen()[:1500]); finish(2)
    o=(r.stdout+r.stderr).strip()
    try: return json.loads(o)
    except Exception: return o
kc=app.kc
screen=lambda: kc(["get-text"])
def until(f,limit=6):
    t=time.time()
    while time.time()-t<limit:
        v=f()
        if v: return v
        time.sleep(.05)
    return f()
res=[]
def check(n,g,w=True):
    ok=g==w; res.append(ok); print(("PASS " if ok else "FAIL ")+n+("" if ok else f"\n   got : {g}\n   want: {w}"))
def sgr(b,r,c,p): kc(["send-text","\\x1b[<%d;%d;%d%s"%(b,c+1,r+1,"M" if p else "m")]); time.sleep(.05)
def click_text(label):
    def find():
        for r,l in enumerate(screen().splitlines()):
            i=l.find(label)
            if i>=0: return (r,i+1)
    p=until(find); time.sleep(.35); p=find() or p
    if not p: print("NOT FOUND",label); print(screen()[:1800]); finish(5)
    sgr(0,p[0],p[1],True); sgr(0,p[0],p[1],False); time.sleep(.3)
ft=lambda: lua("return vim.bo.filetype")
if not until(lambda: os.path.exists(nsock) and lua("return package.loaded['lazycode.sidebar']~=nil and vim.bo.filetype","25")=="lazycode_welcome" if False else os.path.exists(nsock) and lua("return package.loaded['lazycode.welcome']~=nil and vim.bo.filetype",25)=="lazycode_welcome",20):
    print("welcome did not open",lua("return vim.bo.filetype")); print(screen()[:1800]); finish(3)
time.sleep(.8); s=screen()
for w in ("No Folder Opened","You have not yet opened a folder.","Open Folder","Clone Repository","Start","New File...","Open File...","Open Folder...","Clone Git Repository...","Recent","projects"):
    check("screen shows: "+w, w in s)
check("no folder open", lua("return require('lazycode.project').folder"), None)
check("Explorer did not load $HOME", lua("return #Snacks.picker.get({source='explorer'})"), 0)
check("Welcome tab", "Welcome" in s.splitlines()[0])
check("cursor hidden", "\x1b[?25l" in kc(["get-text","--add-cursor"]))
kc(["send-key","ctrl+shift+g"]); until(lambda:"Source Control" in screen()); check("Source Control without folder", "Source Control" in screen())
kc(["send-key","ctrl+shift+e"]); check("back to No Folder", bool(until(lambda:"No Folder Opened" in screen())))
click_text("New File..."); check("New File opens tab", until(lambda: lua("return vim.bo.buftype=='' and vim.api.nvim_get_mode().mode=='i'")))
kc(["send-text","abc"]); check("New File accepts text", until(lambda: lua("return vim.api.nvim_get_current_line()")=="abc"))
lua("vim.bo.modified=false vim.cmd('enew!') require('lazycode.welcome').show() return 1"); until(lambda: ft()=="lazycode_welcome")
click_text("Open File..."); until(lambda:"Open File:" in screen()); check("file chooser", "Open File:" in screen()); click_text("note.txt"); check("Open File opens", until(lambda: lua("return vim.fn.expand('%:t')")=="note.txt"))
lua("require('lazycode.welcome').show() return 1"); until(lambda: ft()=="lazycode_welcome")
click_text("Open Folder..."); until(lambda:"Open Folder:" in screen()); click_text("󰉋 projects"); until(lambda:"Open Folder: ~/projects" in screen()); click_text("󰉋 app"); until(lambda:"Open Folder: ~/projects/app" in screen()); click_text("Select this folder")
check("Open Folder switches project", until(lambda: lua("return require('lazycode.project').folder")==home+"/projects/app"))
check("project cwd", lua("return vim.uv.cwd()"), home+"/projects/app"); check("Explorer opens in project", bool(until(lambda:"main.txt" in screen())))
check("saved to Recent", json.load(open(state+"/lazycode/lazycode_recent.json"))[0], home+"/projects/app")
check("Welcome stays", ft()=="lazycode_welcome")
click_text("main.txt"); check("opens project file", until(lambda: lua("return vim.fn.expand('%:t')")=="main.txt"))
lua("require('lazycode.editing').close_buffer() return 1"); check("closing last file returns to Welcome", bool(until(lambda: ft()=="lazycode_welcome")))
click_text("Clone Git Repository..."); until(lambda: ft()=="snacks_input" and lua("return vim.api.nvim_get_mode().mode")=="i"); kc(["send-text","file://"+up]); time.sleep(.2); kc(["send-key","enter"])
until(lambda:"Open Folder:" in screen()); click_text("Select this folder"); check("clone opens project", until(lambda: lua("return require('lazycode.project').folder")==home+"/projects/app/up",10)); check("clone downloaded", os.path.exists(home+"/projects/app/up/README.md"))
m=str(lua("return vim.api.nvim_exec2('messages',{output=true}).output")); bad=[l for l in m.splitlines() if "E5" in l or "Error" in l or "traceback" in l]
if bad: print(m[-1500:])
check("no errors",bad,[])
print(f"{sum(res)}/{len(res)} passed"); finish(0 if all(res) else 1)
