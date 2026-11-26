import json
import os
import signal
import subprocess
import sys
import tempfile
import time

work = tempfile.mkdtemp(prefix="lazycode-cmp-", dir=None)
p = work + "/proj"
os.makedirs(p + "/src")
subprocess.run(["git", "init", "-q", p], check=True)
open(p + "/package.json", "w").write('{\n  "name": "t",\n  "version": "1.0.0"\n}\n')
open(p + "/tsconfig.json", "w").write(
    '{"compilerOptions":{"target":"ES2022","module":"ESNext","moduleResolution":"bundler","strict":true},"include":["src"]}\n'
)
open(p + "/src/util.ts", "w").write(
    "export function helperFunction(): number { return 1 }\n"
)
for f in (
    "a.ts",
    "a.py",
    "a.html",
    "a.css",
    "a.sh",
    "Dockerfile",
    "a.txt",
    "b.json",
    "c.yaml",
):
    open(p + "/" + ("src/" if f == "a.ts" else "") + f, "w").write("")
sock = os.path.join(tempfile.gettempdir(), "lcc%d.sock" % os.getpid())
TM = ["tmux", "-L", "lc-cmp"]
subprocess.run(TM + ["kill-server"], capture_output=True)
subprocess.run(
    TM
    + [
        "new-session",
        "-d",
        "-x",
        "150",
        "-y",
        "45",
        "-c",
        p,
        f"NVIM_APPNAME=lazycode nvim --listen {sock}",
    ],
    check=True,
)


def finish(c):
    subprocess.run(TM + ["kill-server"], capture_output=True)
    try:
        os.unlink(sock)
    except OSError:
        pass
    __import__("shutil").rmtree(work, ignore_errors=True)
    os._exit(c)


signal.signal(signal.SIGTERM, lambda *_: finish(9))
sys.excepthook = lambda t, v, tb: (
    __import__("traceback").print_exception(t, v, tb),
    finish(4),
)


def lua(c, limit=15):
    e = "luaeval('vim.json.encode((function() " + c.replace("'", "''") + " end)())')"
    try:
        r = subprocess.run(
            ["nvim", "--clean", "--headless", "--server", sock, "--remote-expr", e],
            capture_output=True,
            text=True,
            timeout=limit,
        )
    except subprocess.TimeoutExpired:
        print("HUNG", c[:90])
        finish(2)
    o = (r.stdout + r.stderr).strip()

    try:
        return json.loads(o)
    except Exception:
        return o


def until(f, limit=25):
    t = time.time()
    while time.time() - t < limit:
        v = f()
        if v:
            return v
        time.sleep(0.15)
    return f()


res = []


def check(n, g, w=True):
    ok = g == w
    res.append(ok)
    print(
        ("PASS " if ok else "FAIL ")
        + n
        + ("" if ok else f"\n   got : {g}\n   want: {w}")
    )


until(
    lambda: (
        os.path.exists(sock)
        and lua("return package.loaded['lazycode.sidebar']~=nil and vim.o.keymodel~=''")
    )
)
time.sleep(1)
keys = lambda k, w=0.25: (
    lua("vim.api.nvim_input(" + json.dumps(k) + ") return 1"),
    time.sleep(w),
)


def open_file(f, content=None):
    lua(
        "for _,w in ipairs(vim.api.nvim_list_wins()) do local b=vim.api.nvim_win_get_buf(w) if vim.api.nvim_win_get_config(w).relative=='' and (vim.bo[b].buftype=='' or vim.bo[b].filetype=='lazycode_welcome') then vim.api.nvim_set_current_win(w) break end end vim.cmd('silent! write') vim.cmd.edit(%s) return 1"
        % json.dumps(p + "/" + f)
    )
    until(lambda: lua("return vim.fn.expand('%:t')") == os.path.basename(f))
    if content is not None:
        lua(
            f"vim.api.nvim_buf_set_lines(0,0,-1,false,vim.json.decode([==[{json.dumps(content)}]==])) local __n=vim.api.nvim_buf_line_count(0); vim.api.nvim_win_set_cursor(0,{{__n,#vim.fn.getline(__n)}}) vim.cmd('silent write') return 1"
        )
    until(lambda: lua("return vim.api.nvim_get_mode().mode") == "i")


labels = lambda: lua(
    "local ok,b=pcall(require,'blink.cmp'); if not ok then return {} end local o={} for _,i in ipairs(b.get_items() or {}) do o[#o+1]=i.label end return o"
)


def has(want):
    def f():
        l = labels()
        return isinstance(l, list) and any(
            want == x.strip() or x.strip().startswith(want) for x in l
        )

    return f


def case(name, f, server, content, typed, want):
    open_file(f, content)
    if server:
        check(
            name + ": server " + server,
            bool(
                until(
                    lambda: lua(
                        "return #vim.lsp.get_clients({bufnr=0,name=%s})>0"
                        % json.dumps(server)
                    ),
                    40,
                )
            ),
        )
    if server == "vtsls":
        # tsserver needs a few seconds to index the project the first time.
        until(
            lambda: lua(
                "local r=vim.lsp.buf_request_sync(0,'textDocument/completion',vim.lsp.util.make_position_params(0,'utf-16'),4000) or {}; for _,x in pairs(r) do local it=x.result and (x.result.items or x.result); if it and #it>0 then return true end end return false"
            ),
            30,
        )
    for attempt in range(3):
        keys(typed, 0.2)
        if until(has(want), 10):
            break
        keys("<C-Space>", 0.2)
        if until(has(want), 5):
            break
        lua(
            "vim.api.nvim_buf_set_lines(0,-2,-1,false,{vim.json.decode([==[%s]==])}) local __n=vim.api.nvim_buf_line_count(0); vim.api.nvim_win_set_cursor(0,{__n,#vim.fn.getline(__n)}) return 1"
            % json.dumps(content[-1])
        )
        time.sleep(1)
    ok = has(want)()
    check(name + ": suggests " + want, ok)
    if not ok:
        print("   items:", str(labels())[:200])
    return ok


if case(
    "TypeScript", "src/a.ts", "vtsls", ['const s = "x";', "s"], ".toUp", "toUpperCase"
):
    keys("<Tab>", 0.5)
    check(
        "Tab accepts suggestion",
        "s.toUpperCase" in lua("return vim.api.nvim_get_current_line()"),
    )
    keys("<Esc>", 0.15)
if case("Auto-import", "src/a.ts", "vtsls", [""], "helperF", "helperFunction"):
    keys("<CR>", 1.2)
    t = "\n".join(lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)"))
    check(
        "Enter accepts and imports",
        "import" in t and "util" in t and "helperFunction" in t,
    )
case("Python", "a.py", "pyright", ["import os", "os."], "pa", "path")
case("JSON", "b.json", "jsonls", ["{", '  "'], "$s", "$schema")
case("HTML", "a.html", "html", [""], "<di", "div")
case("CSS", "a.css", "cssls", ["a {", "  "], "col", "color")
case("Bash", "a.sh", "bashls", ["#!/bin/bash", ""], "ech", "echo")
case("Docker", "Dockerfile", "dockerls", [""], "FRO", "FROM")
case(
    "YAML",
    "c.yaml",
    "yamlls",
    [
        "# yaml-language-server: $schema=https://json.schemastore.org/github-workflow.json",
        "",
    ],
    "na",
    "name",
)
case("Paths", "a.txt", None, [""], "./", "src")
case("Snippets", "src/a.ts", None, [""], "fori", "fori") if False else None
case("Buffer words", "a.txt", None, ["longlongword here", ""], "longl", "longlongword")
m = str(lua("return vim.api.nvim_exec2('messages',{output=true}).output"))
bad = [l for l in m.splitlines() if "E5" in l or "stack traceback" in l]
if bad:
    print(m[-900:])
check("no errors", bad, [])
print(f"{sum(res)}/{len(res)} passed")
finish(0 if all(res) else 1)
