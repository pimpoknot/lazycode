//! Runs `nvim --embed` and speaks msgpack-RPC with it.
use rmpv::Value;
use std::io::{BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc::{Sender, channel};

pub struct Nvim {
    tx: Sender<Vec<u8>>,
}

/// The isolated runtime that the installer fills, when it exists.
pub fn runtime() -> Option<PathBuf> {
    std::env::var_os("LAZYCODE_RUNTIME")
        .map(PathBuf::from)
        .or_else(|| {
            let data = std::env::var_os("XDG_DATA_HOME")
                .map(PathBuf::from)
                .or_else(|| {
                    std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share"))
                })?;
            Some(data.join("lazycode-runtime"))
        })
        .filter(|r| r.is_dir())
}

fn executable() -> PathBuf {
    runtime()
        .map(|r| r.join("bin/nvim"))
        .filter(|p| p.exists())
        .unwrap_or_else(|| "nvim".into())
}

/// Plugins write terminal sequences to stderr, so it goes to a log instead of the user's shell.
fn log_file() -> Stdio {
    let dir = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .map(|d| d.join("lazycode"));
    dir.filter(|d| std::fs::create_dir_all(d).is_ok())
        .and_then(|d| std::fs::File::create(d.join("app.log")).ok())
        .map_or_else(Stdio::null, Stdio::from)
}

impl Nvim {
    /// `on_notify` gets each notification (`redraw`, `lazycode_cursor`) on the reader thread,
    /// and `on_exit` runs once when Neovim quits.
    pub fn spawn(
        args: Vec<String>,
        on_notify: impl Fn(&str, Value) + Send + 'static,
        on_exit: impl FnOnce() + Send + 'static,
    ) -> std::io::Result<Self> {
        let nvim = executable();
        let mut command = Command::new(&nvim);
        let path = std::env::var_os("PATH").unwrap_or_default();
        command.env("LAZYCODE_USER_PATH", &path);
        if let Some(bin) = nvim.parent().filter(|p| !p.as_os_str().is_empty()) {
            let joined = std::env::join_paths(
                std::iter::once(bin.to_path_buf()).chain(std::env::split_paths(&path)),
            )
            .unwrap_or(path.clone());
            command.env("PATH", joined);
            if let Some(runtime) = bin.parent() {
                command.env("LAZYCODE_RUNTIME", runtime);
            }
        }
        // One folder is a project, anything else starts on Welcome. The tests set their own.
        let (start, args) = match args.as_slice() {
            [dir] if Path::new(dir).is_dir() => {
                command.current_dir(dir);
                ("folder", Vec::new())
            }
            _ => ("welcome", args),
        };
        if std::env::var_os("LAZYCODE_START").is_none() {
            command.env("LAZYCODE_START", start);
        }
        let mut child = command
            .arg("--embed")
            .args(args)
            .env("NVIM_APPNAME", "lazycode")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(log_file())
            .spawn()?;
        let stdin = child.stdin.take().expect("piped stdin");
        let stdout = child.stdout.take().expect("piped stdout");
        Ok(Self::start(stdout, stdin, on_notify, move || {
            let _ = child.wait();
            on_exit();
        }))
    }

    /// Joins the new server that `:restart` (Reload Window) started.
    pub fn connect(
        addr: &str,
        on_notify: impl Fn(&str, Value) + Send + 'static,
        on_exit: impl FnOnce() + Send + 'static,
    ) -> std::io::Result<Self> {
        let stream = std::os::unix::net::UnixStream::connect(addr)?;
        Ok(Self::start(stream.try_clone()?, stream, on_notify, on_exit))
    }

    fn start(
        input: impl Read + Send + 'static,
        mut output: impl Write + Send + 'static,
        on_notify: impl Fn(&str, Value) + Send + 'static,
        on_exit: impl FnOnce() + Send + 'static,
    ) -> Self {
        // Writes live on their own thread so a busy Neovim never stalls the window.
        let (tx, rx) = channel::<Vec<u8>>();
        std::thread::spawn(move || {
            for message in rx {
                if output
                    .write_all(&message)
                    .and_then(|_| output.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
        std::thread::spawn(move || {
            let mut reader = BufReader::new(input);
            while let Ok(message) = rmpv::decode::read_value(&mut reader) {
                let Some(parts) = message.as_array() else {
                    continue;
                };
                if parts.len() == 3
                    && parts[0].as_u64() == Some(2)
                    && let Some(method) = parts[1].as_str()
                {
                    on_notify(method, parts[2].clone());
                }
            }
            on_exit();
        });
        Self { tx }
    }

    pub fn notify(&self, method: &str, args: Vec<Value>) {
        let message = Value::Array(vec![2.into(), method.into(), Value::Array(args)]);
        let mut bytes = Vec::new();
        if rmpv::encode::write_value(&mut bytes, &message).is_ok() {
            let _ = self.tx.send(bytes);
        }
    }

    pub fn attach(&self, cols: u32, rows: u32) {
        let options = Value::Map(vec![
            ("rgb".into(), true.into()),
            ("ext_linegrid".into(), true.into()),
        ]);
        self.notify("nvim_ui_attach", vec![cols.into(), rows.into(), options]);
        // Lua sends the hover pointer only to a UI with this name.
        let empty = || Value::Map(Vec::new());
        self.notify(
            "nvim_set_client_info",
            vec![
                "lazycode-app".into(),
                empty(),
                "ui".into(),
                empty(),
                empty(),
            ],
        );
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        self.notify("nvim_ui_try_resize", vec![cols.into(), rows.into()]);
    }

    pub fn input(&self, keys: &str) {
        self.notify("nvim_input", vec![keys.into()]);
    }

    /// Lets Lua pick the mouse pointer for the cell under it.
    pub fn hover(&self, row: u32, col: u32) {
        let code = "local ok, m = pcall(require, 'lazycode.mouse') if ok and m.hover then m.hover(...) end";
        self.notify(
            "nvim_exec_lua",
            vec![code.into(), Value::Array(vec![row.into(), col.into()])],
        );
    }

    pub fn mouse(&self, button: &str, action: &str, modifiers: &str, row: u32, col: u32) {
        self.notify(
            "nvim_input_mouse",
            vec![
                button.into(),
                action.into(),
                modifiers.into(),
                0.into(),
                row.into(),
                col.into(),
            ],
        );
    }
}
