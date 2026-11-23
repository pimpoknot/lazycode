import json, os, subprocess, sys, tempfile, time

import atexit, shutil
work = tempfile.mkdtemp(prefix="lazycode-e2e-", dir=None)
atexit.register(shutil.rmtree, work, True)
sock = os.path.join(work, "n.sock")
sample = os.path.join(work, "sample.txt")
open(sample, "w").write("alpha beta\nbeta gamma\nthird line\n")
subprocess.run(["git", "init", "-q"], cwd=work)
open(os.path.join(work,"clip.lua"),"w").write("local f=vim.env.LC_CLIP; vim.g.clipboard={name='e2e',copy={['+']={'sh','-c','cat > '..f},['*']={'sh','-c','cat > '..f}},paste={['+']={'sh','-c','cat '..f..' 2>/dev/null'},['*']={'sh','-c','cat '..f..' 2>/dev/null'}}}")
TM = ["tmux", "-L", "lazycode-e2e"]
subprocess.run(TM + ["new-session", "-d", "-x", "160", "-y", "45", "-c", work,
    f"LC_CLIP={work}/clip NVIM_APPNAME=lazycode nvim --cmd \"luafile {work}/clip.lua\" --listen {sock} {sample}"], check=True)

def lua(code):
    expr = "luaeval('vim.json.encode((function() " + code.replace("'", "''") + " end)())')"
    try:
        r = subprocess.run(["nvim", "--clean", "--headless", "--server", sock, "--remote-expr", expr],
                           capture_output=True, text=True, timeout=8)
    except subprocess.TimeoutExpired:
        print("HUNG at:", code)
        print(subprocess.run(TM + ["capture-pane", "-p"], capture_output=True, text=True).stdout)
        subprocess.run(TM + ["kill-server"], capture_output=True)
        os._exit(2)
    out = (r.stdout + r.stderr).strip()
    try:
        return json.loads(out)
    except Exception:
        return out

for _ in range(60):
    time.sleep(.25)
    if os.path.exists(sock) and lua("return package.loaded['lazycode.sidebar'] ~= nil and vim.o.keymodel") == "startsel,stopsel":
        break
time.sleep(1.5)

def keys(k, wait=.3):
    lua("vim.api.nvim_input(" + json.dumps(k) + ") return 1")
    time.sleep(wait)

def focus_editor():
    lua("""for _,w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w)==vim.fn.bufnr(%s) then vim.api.nvim_set_current_win(w) end end return 1""" % json.dumps(sample))

def reset(line=1, col=0):
    m = lua("return vim.api.nvim_get_mode().mode")
    if m == "t":
        lua("vim.cmd.stopinsert() return 1"); time.sleep(.2)
    elif m in ("s", "v", "V"):
        keys("<Esc>", .15)
    focus_editor()
    lua(f"""require('lazycode.editing').clear_cursors()
      vim.api.nvim_buf_set_lines(0,0,-1,false,{{'alpha beta','beta gamma','third line'}})
      vim.api.nvim_win_set_cursor(0,{{{line},{col}}}) return 1""")
    for _ in range(40):
        time.sleep(.05)
        if lua("return vim.api.nvim_get_mode().mode") == "i":
            break
        lua("vim.cmd.startinsert() return 1")
    lua(f"vim.api.nvim_win_set_cursor(0,{{{line},{col}}}) return 1")
    time.sleep(.1)

text = lambda: lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
mode = lambda: lua("return vim.api.nvim_get_mode().mode")
results = []
def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n   got : {got}\n   want: {want}"))

A = ["alpha beta", "beta gamma", "third line"]
check("opens ready to type", mode(), "i")
reset(); keys("<Esc>"); check("Esc stays in typing mode", mode(), "i")
reset(); keys("<S-Right><S-Right>"); check("Shift+arrows select", mode(), "s")
keys("X"); check("typing replaces selection", text()[0], "Xpha beta")
reset(); keys("<S-Right><S-Right>"); keys("<C-c>"); keys("<Esc>"); check("Esc leaves selection", mode(), "i")
check("Ctrl+C copies selection", lua("return vim.fn.getreg('+')"), "al")
reset(1, 6); keys("<C-v>"); check("Ctrl+V pastes", text()[0], "alpha albeta")
reset(); keys("<S-Right><S-Right>"); keys("<C-x>"); check("Ctrl+X cuts", text()[0], "pha beta"); check("Ctrl+X stays in insert", mode(), "i")
reset(2); keys("<C-c>"); check("Ctrl+C without selection copies line", lua("return vim.fn.getreg('+')"), "beta gamma\n")
reset(1); keys("<C-v>"); check("pastes whole line above", text()[:2], ["beta gamma", "alpha beta"])
reset(2); keys("<C-x>"); check("Ctrl+X without selection cuts line", text(), [A[0], A[2]])
reset(1); keys("<A-Down>"); check("Alt+Down moves line", text(), [A[1], A[0], A[2]])
reset(2); keys("<A-Up>"); check("Alt+Up moves line", text(), [A[1], A[0], A[2]])
reset(1); keys("<S-A-Down>"); check("Shift+Alt+Down duplicates", text(), [A[0], A[0], A[1], A[2]])
reset(2); keys("<C-S-k>"); check("Ctrl+Shift+K deletes line", text(), [A[0], A[2]])
reset(1); keys("<C-CR>"); keys("n"); check("Ctrl+Enter opens line", text(), [A[0], "n", A[1], A[2]])
reset(1); keys("<C-/>"); check("Ctrl+/ runs", mode(), "i")
reset(1, 2); keys("Z"); keys("<C-z>"); check("Ctrl+Z undoes", text(), A)
keys("<C-y>"); check("Ctrl+Y redoes", text()[0], "alZpha beta")
reset(); keys("<C-a>"); check("Ctrl+A selects", mode(), "s"); keys("Q"); check("Ctrl+A + typing", text(), ["Q"])
reset(); keys("<C-d>"); check("Ctrl+D selects word", mode(), "s")
reset(1, 6); keys("<C-d>"); keys("<C-d>", .5)
check("Ctrl+D adds cursor", lua("return require('lazycode.editing').cursor_count()"), 2)
keys("Z", .5); check("multicursor replaces", text()[:2], ["alpha Z", "Z gamma"])
keys("Y", .5); check("multicursor keeps typing", text()[:2], ["alpha ZY", "ZY gamma"])
lua("vim.fn.setreg('+','P','v') return 1"); keys("<C-v>", .5); check("Ctrl+V at every cursor", text()[:2], ["alpha ZYP", "ZYP gamma"])
keys("<Esc>", .4); check("Esc clears cursors", lua("return require('lazycode.editing').cursor_count()"), 1)
check("stays in insert after cursors", mode(), "i")
reset(1, 6); keys("<C-S-l>", .5); check("Ctrl+Shift+L all matches", lua("return require('lazycode.editing').cursor_count()"), 2)
reset(1, 0); keys("<C-A-Down>", .5); check("Ctrl+Alt+Down cursor", lua("return require('lazycode.editing').cursor_count()"), 2)
keys("K", .5); check("line cursors type", text()[:2], ["Kalpha beta", "Kbeta gamma"])
reset()

W = "local n={} for _,w in ipairs(vim.api.nvim_list_wins()) do local c=vim.api.nvim_win_get_config(w); if c.relative=='' then n[#n+1]=vim.bo[vim.api.nvim_win_get_buf(w)].filetype end end return n"
bar_left = lambda: lua("local w=vim.fn.win_getid(1) for _,x in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(x)].filetype=='lazycode_bar' then return vim.api.nvim_win_get_position(x)[2]==0 and vim.api.nvim_win_get_width(x) end end return false")
check("activity bar on the left", bar_left(), 4)
print("windows:", lua(W))
keys("<C-S-g>", 2.5)
check("lazygit open", lua("return vim.bo.filetype"), "snacks_terminal")
check("lazygit in terminal mode", mode(), "t")
check("lazygit width", lua("return vim.api.nvim_win_get_width(0)"), 46)
check("bar stays on the left", bar_left(), 4)
pid1 = lua("return vim.b.terminal_job_id")
keys("<C-S-e>", 1); check("Explorer replaces lazygit", lua("return #Snacks.picker.get({source='explorer'})"), 1)
keys("<C-S-g>", 1); check("lazygit reopens same process", lua("return vim.b.terminal_job_id"), pid1)
check("explorer closed", lua("return #Snacks.picker.get({source='explorer'})"), 0)
screen = subprocess.run(TM + ["capture-pane", "-p"], capture_output=True, text=True).stdout
open(os.path.join(work, "screen.txt"), "w").write(screen)
print(screen)
keys("<C-b>", .6); check("Ctrl+B closes panel", lua("return require('lazycode.sidebar').active"), None)
reset(); keys("<C-A-v>", .4); check("Vim mode turns on", mode(), "n")
keys("x", .2); check("Vim mode runs commands", text()[0], "lpha beta")
keys("<C-A-v>", .4); check("Vim mode turns off", mode(), "i")
errs = lua("return vim.api.nvim_exec2('messages',{output=true}).output")
bad = [l for l in str(errs).splitlines() if "E5" in l or "Error" in l or "stack" in l]
check("no errors in :messages", bad, [])
subprocess.run(TM + ["kill-server"], capture_output=True)
print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
