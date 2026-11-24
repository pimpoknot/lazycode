"""Drives the LazyCode app on the test display with real X keyboard and mouse events.

`App.kc` takes the same commands the suites once sent to `kitty @`: send-key, send-text
(including SGR mouse sequences) and get-text.
"""
import os
import re
import shutil
import subprocess
import tempfile
import time

KEYS = {"escape": "Escape", "enter": "Return", "up": "Up", "down": "Down", "left": "Left",
        "right": "Right", "backspace": "BackSpace", "tab": "Tab", "delete": "Delete", "`": "grave",
        "space": "space", **{f"f{n}": f"F{n}" for n in range(1, 13)}}
CONTROL = {"\r": "Return", "\n": "Return", "\x15": "ctrl+u", "\x1b": "Escape", "\t": "Tab"}
SGR = re.compile(r"\\x1b\[<(\d+);(\d+);(\d+)([Mm])")


def binary():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return (os.environ.get("LAZYCODE_APP") or shutil.which("lazycode-app")
            or os.path.join(data, "lazycode-runtime", "bin", "lazycode-app"))


def xdotool(*args):
    return subprocess.run(["xdotool"] + [str(a) for a in args], capture_output=True, text=True).stdout


class App:
    def __init__(self, args, cwd, env=None, size=None, stderr=subprocess.DEVNULL):
        self.file = os.path.join(tempfile.mkdtemp(prefix="lazycode-screen-"), "screen")
        env = dict(env or os.environ, LAZYCODE_APP_SCREEN=self.file)
        self.proc = subprocess.Popen([binary()] + args, cwd=cwd, env=env,
                                     stdout=subprocess.DEVNULL, stderr=stderr, text=True)
        self.window = None
        for _ in range(240):
            time.sleep(.125)
            if self.proc.poll() is not None:
                return
            self.window = self.window or xdotool("search", "--pid", self.proc.pid).split()[-1:]
            if self.window and os.path.exists(self.file):
                break
        self.window = self.window[0] if self.window else None
        if not self.window:
            return
        xdotool("windowfocus", "--sync", self.window)
        if size:
            w, h, pad, _ = self.header()
            xdotool("windowsize", "--sync", self.window, int(pad * 2 + size[0] * w), int(pad * 2 + size[1] * h))
            time.sleep(.5)

    def read(self):
        try:
            with open(self.file, encoding="utf8") as f:
                return f.read()
        except OSError:
            return "0 0 0 1\n"

    def header(self):
        return [float(x) for x in self.read().split("\n", 1)[0].split()]

    def screen(self, cursor=False):
        head, _, text = self.read().partition("\n")
        hidden = head.split()[-1:] == ["0"]
        return ("\x1b[?25l" if cursor and hidden else "") + text

    def point(self, row, col):
        w, h, pad, _ = self.header()
        return int(pad + col * w + w / 2), int(pad + row * h + h / 2)

    def mouse(self, code, row, col, press):
        x, y = self.point(row, col)
        xdotool("mousemove", "--window", self.window, x, y)
        if code >= 64:
            xdotool("click", 4 + (code & 1))
        elif code & 32:
            return  # motion while a button is held: the move above is the drag
        else:
            xdotool("mousedown" if press else "mouseup", {0: 1, 1: 2, 2: 3}[code & 3])

    def key(self, name):
        parts = name.split("+")
        xdotool("key", "--clearmodifiers", "+".join(KEYS.get(p, p) for p in parts))

    def text(self, s):
        for chunk in re.split(r"([\r\n\x15\x1b\t])", s):
            if chunk in CONTROL:
                self.key(CONTROL[chunk])
            elif chunk:
                xdotool("type", "--delay", 8, "--", chunk)

    def kc(self, args):
        """The subset of `kitty @` the suites used, so they read the same as before."""
        if args[0] == "send-key":
            for name in args[1:]:
                self.key(name)
        elif args[0] == "send-text":
            s = args[1]
            mouse = SGR.fullmatch(s)
            if mouse:
                code, col, row, kind = mouse.groups()
                self.mouse(int(code), int(row) - 1, int(col) - 1, kind == "M")
            else:
                self.text(s)
        elif args[0] == "get-text":
            return self.screen(cursor="--add-cursor" in args)
        return ""

    def close(self):
        self.proc.terminate()
        shutil.rmtree(os.path.dirname(self.file), ignore_errors=True)
