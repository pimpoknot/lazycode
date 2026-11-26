<p align="center">
  <img src="assets/logo.svg" alt="LazyCode" width="660">
</p>

<p align="center">
  <strong>The power and look of LazyVim, with the mouse and shortcuts you know from VS Code.</strong>
</p>

<p align="center">
  <a href="https://github.com/pimpoknot/lazycode/actions/workflows/ci.yml"><img src="https://github.com/pimpoknot/lazycode/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/pimpoknot/lazycode" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-7aa2f7" alt="Linux and macOS">
  <img src="https://img.shields.io/badge/Neovim-0.12-57A143?logo=neovim&logoColor=white" alt="Neovim 0.12">
</p>

> **Status: stable.** Linux and macOS are tested.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/pimpoknot/lazycode/main/install.sh | sh
```

The installer needs `curl`, `tar`, `git` and, on Linux, `xz`. A C compiler is recommended for
syntax highlighting. On Linux, copy and paste with other apps needs `wl-clipboard`, `xclip` or `xsel`. It does not use `sudo` and does not touch your Neovim setup.
LazyCode runs in its own native window. That window, Neovim, lazygit, ripgrep, fd, Node and the
fonts (FiraCode and JetBrains Mono Nerd Font, plus icons) are downloaded at pinned versions, verified with SHA-256 and kept in
`~/.local/share/lazycode-runtime`. Without a prebuilt window for your system, the installer
builds it with Rust when `cargo` is available.

A full install uses about 1.2 GB, most of it language servers. To skip them:

```sh
curl -fsSL https://raw.githubusercontent.com/pimpoknot/lazycode/main/install.sh | LAZYCODE_SKIP_TOOLS=1 sh
```

On macOS and Linux you can also use Homebrew:

```sh
brew install pimpoknot/tap/lazycode
```

## Use

```sh
lazycode              # Welcome screen
lazycode .            # open a folder as a project
lazycode file.py      # open a file
lazycode doctor       # check the installation
lazycode update       # update
lazycode uninstall    # remove LazyCode
```

You can also open **LazyCode** from your app launcher (Linux) or `~/Applications` (macOS).

## Features

- Welcome screen with New File, Open File, Open Folder, Clone Repository and recent projects
- Always ready to type, with selections that are replaced as you type
- Full mouse support: click, drag, double click, context menus, tabs and multiple cursors
- Explorer with create, rename, copy, cut, paste and delete to trash
- Source Control sidebar powered by lazygit
- Integrated terminal with mouse selection, copy and paste
- Completion for TypeScript, JavaScript, Python, JSON, YAML, TOML, Markdown, Docker, Tailwind,
  HTML, CSS, Bash and Lua out of the box
- Other languages on demand: `:LazyCodeLanguage go`
- Vim is one shortcut away: `Ctrl+Alt+V`, or click `CODE` in the status bar

## Shortcuts

On macOS, use `Cmd` in place of `Ctrl`, except for `` Ctrl+` ``, `Ctrl+Tab` and `Ctrl+J`.

| Area | Shortcuts |
| --- | --- |
| Files | `Ctrl+N` new, `Ctrl+O` open, `Ctrl+K Ctrl+O` open folder, `Ctrl+S` save, `Ctrl+W` close |
| Editing | `Ctrl+Z`, `Ctrl+Y`, `Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+A`, `Ctrl+/` |
| Lines | `Alt+Up/Down` move, `Shift+Alt+Up/Down` duplicate, `Ctrl+Shift+K` delete |
| Cursors | `Ctrl+D`, `Ctrl+Shift+L`, `Ctrl+Alt+Up/Down`, `Alt+Click` |
| Navigate | `Ctrl+P`, `Ctrl+Shift+P`, `Ctrl+G`, `F12`, `Shift+F12`, `Alt+Left/Right` |
| Search | `Ctrl+F`, `Ctrl+H`, `Ctrl+Shift+F`, `Ctrl+Shift+H` |
| Code | `Ctrl+Space`, `Ctrl+.`, `F2`, `Shift+Alt+F`, `F8` |
| Panels | `Ctrl+B`, `Ctrl+Shift+E`, `Ctrl+Shift+G`, `Ctrl+Shift+X`, `` Ctrl+` ``, `Ctrl+Shift+M` |
| Terminal | `Ctrl+Shift+C` copy, `Ctrl+Shift+V` paste |
| Help | `Ctrl+K Ctrl+S` lists every shortcut |

## Customize

- Extensions: the puzzle icon or `Ctrl+Shift+X` lists every LazyVim extra. Search, then click one
  to turn it on or off, and restart LazyCode.
- Copilot suggestions are on by default and accepted with `Tab`. Sign in once with `:LspCopilotSignIn`.
- ESLint and Prettier fix and format JavaScript and TypeScript (React included) on save.
- Rust support turns on by itself when `cargo` is installed.
- Reload Window (the last activity bar icon, or `:LazyCodeReload`) applies extension changes
  without closing LazyCode.
- More languages and plugins: `:LazyExtras`
- Font size: `Ctrl+=`, `Ctrl+-` and `Ctrl+0`, like VS Code. The size is remembered.
- Font: FiraCode Nerd Font Mono SemiBold, or JetBrains Mono where FiraCode is missing. Try another
  one with `:set guifont=Hack:h14:w500` (name as `fc-list : family` shows it, size, weight).

## Known limitations

- VS Code extensions do not run. Languages and tools come from the Neovim ecosystem.
- No debugger panel, Remote/SSH, or tab dragging yet.
- `Ctrl+Shift+L` selects the matches visible on screen.
- Emoji and CJK characters show as boxes, and input methods (IME) are not supported yet.
- Windows is not supported.

## Uninstall

```sh
lazycode uninstall
```

It asks before deleting your settings, plugins and language tools.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run the test suites with `tests/headless.sh`.

## Credits and license

LazyCode is an independent project. It is not affiliated with or endorsed by LazyVim, Neovim or
Microsoft. Visual Studio Code is a trademark of Microsoft.

Licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party credits.
