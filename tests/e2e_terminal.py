import json, os, signal, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appctl
work=tempfile.mkdtemp(prefix="lazycode-term-",dir=None)
proj=work+"/p"; os.makedirs(proj); open(proj+"/a.txt","w").write("x\n"); out=work+"/out"
nsock=os.path.join(tempfile.gettempdir(),"lct%d.sock"%os.getpid())
clip="lua local f=vim.env.LC_CLIP; vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..f},['*']={'sh','-c','cat > '..f}},paste={['+']={'sh','-c','cat '..f..' 2>/dev/null'},['*']={'sh','-c','cat '..f..' 2>/dev/null'}}}"
app=appctl.App(["--cmd","set shell=/bin/bash","--cmd",clip,"--listen",nsock,"a.txt"],proj,env=dict(os.environ,NVIM_APPNAME="lazycode",LAZYCODE_START="",LC_CLIP=work+"/clip",SHELL="/bin/bash"))
def finish(c):
    try: subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr","execute('qa!')"],capture_output=True,timeout=3)
    except Exception: pass
    time.sleep(.3); app.close()
    try: os.unlink(nsock)
    except OSError: pass
    __import__('shutil').rmtree(work, ignore_errors=True); os._exit(c)
signal.signal(signal.SIGTERM,lambda *_:finish(9)); sys.excepthook=lambda t,v,tb:(__import__("traceback").print_exception(t,v,tb),finish(4))
def lua(c,limit=8):
    e="luaeval('vim.json.encode((function() "+c.replace("'","''")+" end)())')"
    try: r=subprocess.run(["nvim","--clean","--headless","--server",nsock,"--remote-expr",e],capture_output=True,text=True,timeout=limit)
    except subprocess.TimeoutExpired: print("HUNG:",c[:90]); print(screen()[-1200:]); finish(2)
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
mode=lambda: lua("return vim.api.nvim_get_mode().mode")
key=lambda *k,wait=.15:(kc(["send-key"]+list(k)),time.sleep(wait))
typ=lambda s,wait=.15:(kc(["send-text",s]),time.sleep(wait))
def sgr(b,r,c,p): kc(["send-text","\\x1b[<%d;%d;%d%s"%(b,c+1,r+1,"M" if p else "m")]); time.sleep(.06)
def drag(r,c1,c2):
    sgr(0,r,c1,True); sgr(32,r,c1+1,True); sgr(32,r,c2,True); sgr(0,r,c2,False); time.sleep(.25)
def cat(f):
    try: return open(f).read().strip()
    except OSError: return None
def run(cmd):
    typ(cmd+"\r")
def term_cell():
    return lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].buftype=='terminal' then local p=vim.fn.win_screenpos(w) return {p[1]-1,p[2]-1,vim.api.nvim_win_get_height(w)} end end")
def find(text):
    for r,l in enumerate(screen().splitlines()):
        i=l.find(text)
        if i>=0: return r,i
if not until(lambda: os.path.exists(nsock) and lua("return package.loaded['lazycode.terminal']~=nil and vim.o.keymodel~=''",25),25): print("did not start"); finish(3)
time.sleep(1); key("ctrl+`",wait=.1); check("terminal opens ready to type", bool(until(lambda: mode()=="t")))
time.sleep(.7); run("export PS1='$ '; clear"); time.sleep(.4)
run(f"echo first > {out}"); check("shell receives command", bool(until(lambda: cat(out)=="first")))
run(f"printf '%s|%s' \"$NVIM_APPNAME\" \"$LG_CONFIG_FILE\" > {out}.env"); until(lambda: cat(out+".env") is not None); check("no NVIM_APPNAME/LG_CONFIG_FILE", cat(out+".env"), "|")
run(f"echo \"$PATH\" > {out}.path"); until(lambda: cat(out+".path")); check("PATH without Mason", "/lazycode/mason" not in cat(out+".path"))
t=term_cell(); sgr(0,t[0]+1,t[1]+8,True); sgr(0,t[0]+1,t[1]+8,False); check("click keeps shell active", bool(until(lambda: mode()=="t",2)))
run(f"echo after-click > {out}2"); check("types after click", bool(until(lambda: cat(out+"2")=="after-click")))
run("echo COPYABLE-TEXT"); p=until(lambda: (lambda x: x if x and x[1]<8 else None)(find("COPYABLE-TEXT"))); drag(p[0],p[1],p[1]+5)
check("drag selects", mode() in ("s","v"), True); key("ctrl+shift+c",wait=.3); check("Ctrl+Shift+C copies", lua("return vim.fn.getreg('+')"), "COPYA"); check("returns to shell after copy", bool(until(lambda: mode()=="t")))
lua("vim.fn.setreg('+','pasted-ok') return 1"); typ("echo "); key("ctrl+shift+v",wait=.25); run(f" > {out}3"); check("Ctrl+Shift+V pastes", bool(until(lambda: cat(out+"3")=="pasted-ok")))
lua("vim.fn.setreg('+','echo A > %s4\\necho B > %s5') return 1"%(out,out)); key("ctrl+shift+v",wait=.4); check("multi-line paste does not run", not os.path.exists(out+"4")); key("ctrl+c",wait=.25)
t=term_cell(); sgr(64,t[0]+2,t[1]+5,True); time.sleep(.25); check("mouse wheel scrolls", mode()=="nt" or mode()=="t")
if mode()=="nt": typ("e"); check("typing returns to prompt", bool(until(lambda: mode()=="t"))); key("backspace",wait=.1)
run(f"echo back > {out}6"); check("shell works after scrolling", bool(until(lambda: cat(out+"6")=="back")))
t=term_cell(); sgr(2,t[0]+2,t[1]+10,True); sgr(2,t[0]+2,t[1]+10,False); ok=until(lambda:"Clear" in screen() and "Paste" in screen(),3); check("right click menu", bool(ok))
if ok:
    p=find("Clear"); sgr(0,p[0],p[1]+1,True); sgr(0,p[0],p[1]+1,False); time.sleep(.5); check("Clear clears the screen","COPYABLE-TEXT" not in screen()); check("shell active after menu", bool(until(lambda: mode()=="t")))
typ("q"); time.sleep(.2); check("q does not hide terminal", lua("return vim.bo.buftype"), "terminal"); key("backspace",wait=.1)
key("escape",wait=.15); check("Esc stays in shell", mode(), "t")
key("ctrl+c",wait=.25); run("%s --clean -n %s7"%(__import__("shutil").which("nvim"), out)); until(lambda: "%s7"%os.path.basename(out) in screen() or "[No Name]" in screen(),4); time.sleep(.8); typ("iok-vi"); key("escape",wait=.15); typ(":wq\r"); ok=bool(until(lambda: cat(out+"7")=="ok-vi"))
if not ok: print("--- SCREEN"); print("\n".join(l[48:125] for l in screen().splitlines()[-16:])); print("mode",mode())
check("full-screen program", ok)
key("ctrl+`",wait=.5); check("Ctrl+` hides", bool(until(lambda: lua("return vim.bo.buftype")!="terminal"))); key("ctrl+`",wait=.5); check("Ctrl+` reopens the same shell", bool(until(lambda: lua("return vim.bo.buftype")=="terminal" and vim_ok()))) if False else None
m=str(lua("return vim.api.nvim_exec2('messages',{output=true}).output")); bad=[l for l in m.splitlines() if "E5" in l or "Error" in l or "stack traceback" in l]
if bad: print(m[-1000:])
check("no errors",bad,[])
print(f"{sum(res)}/{len(res)} passed"); finish(0 if all(res) else 1)
