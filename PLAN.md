# LazyCode Plan

The whole plan in one place: what LazyCode is, how it is built, where it stands and what comes
next. Update it when work lands or a decision changes.

Last updated: 2026-11-25 · Released: `0.1.0` (stable) · In progress: `0.2.0`, the native window

## Contents

1. [Vision](#1-vision)
2. [Principles and non-goals](#2-principles-and-non-goals)
3. [Where it stands](#3-where-it-stands)
4. [Architecture](#4-architecture)
5. [Install, update and runtime](#5-install-update-and-runtime)
6. [Testing and CI](#6-testing-and-ci)
7. [Release process](#7-release-process)
8. [Roadmap](#8-roadmap)
9. [Known limitations](#9-known-limitations)
10. [Risks](#10-risks)
11. [Decision log](#11-decision-log)
12. [Working agreements](#12-working-agreements)

## 1. Vision

LazyCode is a lightweight IDE. It has LazyVim's look and power, plus the mouse, shortcuts and
editing people know from VS Code. One command installs it. It opens on a Welcome tab, ready to
type, and Vim is one shortcut away (`Ctrl+Alt+V`).

It is for:

- VS Code users who want a fast editor without learning Vim first.
- Vim and LazyVim users who want friendly defaults for themselves or their team.

What `1.0` means:

- One command installs it on Linux or macOS. It needs no `sudo` and changes nothing outside
  LazyCode's own folders.
- The first launch is quiet: no prompts, downloads or errors.
- Someone who knows VS Code can open a folder, edit, search, commit and use the terminal without
  reading the docs.
- Text input works for every language: input methods (IME), emoji and CJK.
- Nothing that worked in `0.1.0` (inside kitty) is missing from the native window.
- Every release passes all suites on Linux and a manual check on a real Mac.

## 2. Principles and non-goals

Principles:

- Keep LazyVim as the base. Do not fork it, and keep its visual identity.
- Always ready to type. Vim modes stay hidden behind `Ctrl+Alt+V`.
- IDE first. The activity bar opens fixed side panels like VS Code's, not LazyVim pickers and
  popups.
- Opening the app shows the Welcome tab and never loads `$HOME` as a project.
- Runtime dependencies are isolated, pinned and checked against SHA-256 checksums. The installer
  never uses `sudo` and never touches the person's own Neovim config.
- Linux and macOS only. On macOS, `Ctrl` shortcuts are mirrored to `Cmd`.
- All UI, code, comments, docs and tests are in English.
- No VS Code or LazyVim logos. LazyCode is independent of both.

Non-goals:

- Windows.
- Running VS Code extensions. Languages and tools come from the Neovim ecosystem.
- A fork of LazyVim or Neovim.

## 3. Where it stands

| Version | State |
| --- | --- |
| `0.1.0` | Stable, released 2026-11-24 on GitHub and in `homebrew-tap`. A real `brew install` on a Mac passed. |
| `0.2.0` | Branch `feat/native-app`: one commit, not pushed yet. It replaces kitty with LazyCode's own window. 215 of 215 end-to-end checks pass locally on Linux arm64. It is the build in daily use on the development machine. |

Shipped in `0.1.0`:

- **Welcome tab:** New File, Open File, Open Folder, Clone Repository and recent projects.
- **VS Code editing:**
  - Always ready to type.
  - Typing replaces the selection.
  - VS Code shortcuts.
  - Multiple cursors.
- **Mouse:** click, drag, double click, context menus and tabs.
- **Explorer:** create, rename, copy, cut, paste and delete to trash.
- **Source Control:** lazygit.
- **Terminal:** integrated, with mouse selection, copy and paste.
- **Completion:** TypeScript, JavaScript, Python, JSON, YAML, TOML, Markdown, Docker, Tailwind,
  HTML, CSS, Bash and Lua. Other languages come on demand.
- **Lifecycle:** installer, `doctor`, `update`, `uninstall` and a Homebrew formula.
- **Releases:** checksums and build provenance.

On the `0.2.0` branch:

- **Window:**
  - The native window (Rust, wgpu and winit) runs `nvim --embed`. kitty is no longer downloaded.
  - Icons come from a pinned Nerd Font symbols font and are drawn two cells wide.
- **Activity bar:** Explorer, Search, Source Control, Terminal, Extensions and Reload Window.
- **Search:** a side panel (grug-far) with replace and file filters. A click opens a result.
- **Extensions:** a panel to search the LazyVim extras and turn them on or off with a click.
- **Reload Window** (`:LazyCodeReload`): a fresh Neovim in the same window, with the same folder
  and files.
- **Mouse pointer:**
  - A hand over clickable items.
  - An I-beam over text.
  - Resize arrows over panel borders.
- **Motion:** the cursor blinks with a fade, and scrolling is animated.
- **Default tools:**
  - Copilot (native), ESLint and Prettier come on by default.
  - JavaScript and TypeScript are formatted on save.
  - Rust support turns on when `cargo` is installed.
- **noice is disabled:** messages go to `:messages` and notifications.
- **macOS:** `LazyCode.app` is the window itself, with its own Dock icon and Retina rendering.

## 4. Architecture

```
lazycode         launcher (POSIX sh): doctor, update, uninstall, XWayland retry
   │
   ▼
lazycode-app     native window (Rust: winit + wgpu)
   │   ▲         draws the screen, sends keys, mouse and resize
   │   │         msgpack-RPC over stdio (over a Unix socket after Reload Window)
   ▼   │
nvim --embed     Neovim 0.12.4, pinned
   ├─ LazyVim and its plugins, pinned in lazy-lock.json
   ├─ LazyCode Lua (lua/lazycode)
   └─ lazygit, ripgrep, fd, Node and Mason language tools
```

The repository root is the Neovim config. LazyCode's own code lives in:

- `lua/lazycode/`
- `lua/plugins/lazycode.lua`
- `app/`
- `bin/`
- `install.sh`

### Native window (`app/`)

| File | Role |
| --- | --- |
| `main.rs` | winit event loop, window events, frame timing, reconnect after Reload Window, `--version` |
| `nvim.rs` | Starts `nvim --embed` or connects to a socket; RPC reader and writer threads; `attach`, `input`, `hover` |
| `grid.rs` | Screen state from `ext_linegrid` redraw events: cells, highlights, modes, cursor, scrolls, `restart` |
| `render.rs`, `render.wgsl` | GPU text: a glyph atlas and one instanced quad per background, glyph and decoration |
| `input.rs` | winit keys to Neovim key notation |
| `anim.rs` | Smooth scroll and cursor blink timing. Pure logic with unit tests |

How it renders:

- **Text font:** the system monospace font from fontdb at 13 pt, the size `0.1.0` used in kitty.
  `LAZYCODE_FONT_DIR` points it at another font folder.
- **Icon font:** the pinned Symbols Nerd Font Mono, loaded by path before the system is asked.
  Distribution packages lack many icons.
- **Icon width:**
  - An icon from a Private Use Area followed by a space is drawn 1.5 cells wide over 2 cells,
    like kitty does it.
  - Backgrounds are drawn in a first pass, so the next cell cannot cover an icon.
- **Smooth scroll:**
  - Each `grid_scroll` starts an animation that settles exponentially, with a 60 ms time
    constant.
  - The rows that just left the region stay on screen while it moves.
- **Cursor blink:** follows `guicursor` (`blinkwait`, `blinkon`, `blinkoff`) with a 150 ms fade.
- **Frames:** scheduled with `ControlFlow::WaitUntil`, so the window idles when nothing moves.

### Window and Neovim contract

| What | How |
| --- | --- |
| UI options | `rgb` and `ext_linegrid` |
| Client name | `nvim_set_client_info("lazycode-app", …)`, so Lua can find the window's channel |
| Mouse pointer | The window sends the cell under the mouse to `lazycode.mouse.hover(row, col)` with `nvim_exec_lua`. Lua answers with an `rpcnotify` named `lazycode_cursor`. Its value is `pointer`, `text`, `ew-resize`, `ns-resize` or `default` |
| Reload Window | `:restart` sends a `restart` UI event with the new server address. The window joins it over its Unix socket |
| Closing | The close button sends `<Cmd>confirm qa<CR>`, so Neovim asks about unsaved files |
| Environment | `LAZYCODE_RUNTIME` is the runtime folder. `LAZYCODE_START` is what opens first: a folder or the Welcome tab. `LAZYCODE_FONT_DIR` is a font folder. `LAZYCODE_APP_SCREEN` is a screen dump for tests |

### LazyCode Lua (`lua/lazycode/`)

| Module | Role |
| --- | --- |
| `init.lua` | Starts the other modules and maps the global shortcuts |
| `editing.lua` | Always-insert editing, selection, shortcuts, multiple cursors |
| `welcome.lua` | Welcome tab and the "No Folder Opened" panel |
| `project.lua` | Open folder, recents, file choosers, git clone, Reload Window |
| `sidebar.lua` | Activity bar, plus the Explorer, Search, lazygit and Extensions panels |
| `extensions.lua` | Extensions panel |
| `explorer.lua` | Explorer context menu and file operations |
| `terminal.lua` | Integrated terminal |
| `mouse.lua` | Pointer shape for each screen area |
| `languages.lua` | Default language tools and on-demand languages |
| `platform.lua` | Linux and macOS differences |

Other config:

- `lua/plugins/lazycode.lua` holds the plugin overrides.
- `lua/config/` holds the options and the LazyVim setup. It imports Rust support only when
  `cargo` exists.

## 5. Install, update and runtime

| Path | Holds |
| --- | --- |
| `~/.config/lazycode` | The config: a copy of the release, or a Git checkout for development |
| `~/.local/share/lazycode-runtime` | Pinned tools, the window and the uninstall manifest |
| `~/.local/share/lazycode` | Plugins and Mason language tools |
| `~/.local/state/lazycode` | Launcher log, recent projects, Reload Window state |
| `~/.local/bin/lazycode` | The launcher |
| `~/.local/share/applications/lazycode.desktop` | App launcher entry (Linux) |
| `~/Applications/LazyCode.app` | App bundle whose executable is the window (macOS) |

Pinned tools, from `runtime/versions.lock` (generated by `scripts/update-versions.py`):

| Tool | Version |
| --- | --- |
| Neovim | 0.12.4 |
| lazygit | 0.66.3 |
| ripgrep | 16.0.0 |
| fd | 10.5.2 |
| Node | 26.13.1 |
| Nerd Fonts symbols | 3.5.1 |

The window binary comes from the first of these that is available:

1. `$SOURCE/bin/lazycode-app`, as used by Homebrew and CI.
2. The release asset `lazycode-app-<version>-<os>-<arch>.tar.gz`, checked against that release's
   `SHA256SUMS`. Git checkouts skip this step.
3. `cargo build --release`.

Lifecycle commands:

- **Update:** `lazycode update` runs the installer again, after `brew upgrade` for Homebrew
  installs. `scripts/merge-extras.lua` keeps the extras the person turned on. Git checkouts
  update with `git pull`.
- **Uninstall:** `lazycode uninstall` removes what the manifest lists. It asks before deleting
  settings, plugins and language tools.

Language tools:

- **Default tools (22 Mason packages):**

  | Area | Packages |
  | --- | --- |
  | Language servers | `bash-language-server`, `copilot-language-server`, `css-lsp`, `docker-compose-language-service`, `dockerfile-language-server`, `eslint-lsp`, `html-lsp`, `json-lsp`, `lua-language-server`, `marksman`, `pyright`, `tailwindcss-language-server`, `taplo`, `vtsls`, `yaml-language-server` |
  | Formatters | `prettier`, `shfmt`, `stylua` |
  | Linters and tools | `hadolint`, `markdownlint-cli2`, `markdown-toc`, `ruff` |

- **Skipping them:** a full install takes about 1.2 GB. `LAZYCODE_SKIP_TOOLS=1` skips the
  language tools.
- **On demand:** opening a file for one of these languages offers its support, which is also
  available through `:LazyCodeLanguage`:

  | Area | Languages |
  | --- | --- |
  | General | Go, PHP, Java, Ruby, Kotlin, Zig, Elixir, C/C++, C# |
  | Data and infrastructure | SQL, Terraform, Prisma |
  | Web frameworks | Vue, Svelte, Astro |

- **Default extras in `lazyvim.json`:**
  - `ai.copilot-native`
  - `formatting.prettier`
  - `linting.eslint`
  - `lang.docker`, `lang.json`, `lang.markdown`, `lang.python`, `lang.tailwind`, `lang.toml`,
    `lang.typescript`, `lang.yaml`
  - `lang.rust`, imported from `lua/config/lazy.lua` when `cargo` exists.

## 6. Testing and CI

End-to-end suites drive a real window on a private virtual display:

| Suite | Checks | Covers |
| --- | --- | --- |
| `editing` | 45 | Typing, selections, clipboard shortcuts, line moves, undo, multiple cursors |
| `terminal` | 22 | Shell, mouse selection, copy and paste, wheel, context menu, show and hide |
| `welcome` | 31 | Welcome tab, New File, Open File, Open Folder, recents, clone |
| `explorer` | 32 | Hidden files, context menu, create, copy, cut, rename, trash, permanent delete |
| `app` | 62 | Mouse, activity bar, panel resize, focus, Search, Extensions, pointer shapes, tabs, lazygit commit, Reload Window |
| `complete` | 23 | Completion accepted with `Tab` and `Enter`, with auto import |
| **Total** | **215** | |

How the tests run:

- `app/` adds 12 Rust unit tests: scroll and blink timing, the grid, keys and rendering helpers.
- `tests/headless.sh` runs each suite on Xvfb with software GL.
- `tests/appctl.py` drives the window with xdotool and reads its screen dump.
- **Never run the suites outside `tests/headless.sh`**: they would open windows on the desktop.
- Lint: `cargo fmt`, `cargo clippy -D warnings`, `stylua`, `shellcheck`, a Python syntax check and
  a check that the logo is up to date.

CI (`.github/workflows/`):

| Job | Runners | What it does |
| --- | --- | --- |
| Lint | `ubuntu-latest` | Shell, Lua and Python checks, logo |
| App (`app.yml`) | `ubuntu-22.04` x86_64 and arm64, `macos-latest`, `macos-15-intel` | fmt and clippy, `cargo test`, release build, artifacts for the other jobs |
| E2E ×6 | `ubuntu-latest` | Installs from a clean home with the prebuilt window, then runs one suite |
| Install | Debian, Ubuntu 24.04, Fedora, Arch containers; `ubuntu-24.04-arm`; both macOS runners | Install, `doctor` and uninstall as a regular user |
| Homebrew | `macos-latest` | Builds, installs and tests the formula |
| CI OK | | The required check: every job passed |

CI runs on push, on pull requests, weekly on Monday at 06:00 UTC, and by hand.

Gaps:

- No test drives the window on macOS. The macOS jobs only install.
- No test covers Wayland.
- In CI, the E2E suites run on Linux x86_64 only.

## 7. Release process

1. Open a PR that updates `VERSION`, `CHANGELOG.md`, `packaging/macos/Info.plist` and
   `app/Cargo.toml`. Merge it after `CI OK`.
2. Push tag `vX.Y.Z` from `main`. The Release workflow then does the rest:
   1. Builds the window for 4 platforms with `app.yml`.
   2. Validates the release.
   3. Builds the package, `SHA256SUMS` and the provenance attestation.
   4. Publishes the GitHub Release.
   5. Updates `homebrew-tap` with a deploy key from the `release` environment.
3. A tag with a suffix, like `v0.2.0-rc.1`, makes a prerelease and does not update Homebrew.
4. After each release, check by hand:
   1. Run the real `curl | sh` install on Linux and macOS.
   2. Run `brew install` on a Mac.
   3. Run `lazycode doctor`.
   4. Do a short smoke test in the window.

## 8. Roadmap

### `0.2.0`: the native window (now)

Done before the PR:

- [x] **Stray extras:** two extras an Extensions click had saved into `lazyvim.json` and
  `lazy-lock.json` (`lang.rust`, `util.mini-hipatterns`) are gone. Rust stays tied to `cargo`.
- [x] **Focus events:** the window sends `nvim_ui_set_focus`, so LazyVim's `FocusGained` check
  reloads files changed outside LazyCode, as it did in kitty.
- [x] **Clipboard on Linux:** copying to and pasting from other apps needs `xclip`, `xsel` or
  `wl-clipboard`, since the native window has no terminal for OSC 52. `lazycode doctor` warns and
  the README says so.
- [x] **Resize test:** the `app` suite drags a panel border and checks the Explorer width.

Then:

- [ ] **PR:** push `feat/native-app`, open the PR and get `CI OK`. This is the first run of
  `app.yml` on all four runners.
- [ ] **Release candidate:** tag `v0.2.0-rc.1` and test the real `curl | sh` install on Linux
  x86_64, Linux arm64 and macOS. The window download (release asset plus `SHA256SUMS`) has never
  run for real.
- [ ] **Mac check:** test the native window on a real Mac:
  - `Cmd` shortcuts, and `Option` as `Alt`.
  - Retina rendering and the Dock icon.
  - Pointer shapes and Reload Window.
  - Closing with unsaved files.
- [ ] **Release:** release `v0.2.0`, then confirm `brew install pimpoknot/tap/lazycode` on a Mac.

### `0.2.x`: native window polish

- [ ] **Smooth scroll with the Explorer open.**
  - Today: any floating window stops Neovim from sending `grid_scroll`, and the Explorer is made of
    floats. It is open most of the time, so the pixel scroll seldom runs, and Snacks scroll
    animates instead.
  - Fix: move to `ext_multigrid`, where each window has its own grid and `win_viewport` reports
    scroll deltas even while floats are open (Neovide works this way).
  - Cost: per-grid state in `grid.rs`, float positions, and composing the grids in `render.rs`.
- [ ] **Neovim left running.** After Reload Window, the window is only a socket client, so
  killing the window leaves Neovim running (a normal close is fine). Stop the server when the
  window exits.
- [ ] **Font settings.** The `0.1.0` kitty.conf override is gone, so the font cannot be changed
  today.
  - Read `guifont` (family and size) from the `option_set` UI event.
  - Add `Ctrl+=`, `Ctrl+-` and `Ctrl+0` zoom like VS Code.
- [ ] **Window title.** It is always "LazyCode". Use Neovim's `set_title` event to show the folder
  and file.
- [ ] **Undercurl.** Diagnostics are drawn with a straight underline. Draw a wave like VS Code.
- [ ] **The person's Extensions choices.** They live in the tracked `lazyvim.json`.
  - In a Git checkout, that leaves the repository dirty. This is how the stray extras got into
    the commit.
  - `lazycode update` brings back a default extra the person turned off, because
    `merge-extras.lua` keeps the union of the old and new lists.
  - Fix: keep both on and off choices in a file of the person's own and merge it at startup.
- [ ] **Copilot sign-in from the UI.** Today it only works with `:LspCopilotSignIn`.
- [ ] **Dropped files.** Files dropped on the window should open (`WindowEvent::DroppedFile`).

### `0.3.0`: text input for every language

- [ ] **IME:** winit `Ime` events, with the preedit text drawn at the cursor and committed text
  sent with `nvim_input`.
- [ ] **Emoji and CJK:** a font fallback chain through fontdb, with wide characters drawn over two
  cells.

### Later (ideas, not scheduled)

- **`lazycode --here`:** run inside an existing terminal (iTerm2, Warp) instead of the window.
- **Packages:** `.deb` and AUR.
- **Missing VS Code features:** debugger panel (the LazyVim `dap` extras), Remote/SSH and tab
  dragging.
- **`Ctrl+Shift+L`:** select every match in the file, not only the matches on screen.
- **More CI:** a macOS end-to-end run in CI, and a Wayland run.

## 9. Known limitations

As of the `0.2.0` branch:

- **Scope:**
  - VS Code extensions do not run.
  - There is no debugger panel, Remote/SSH or tab dragging.
  - Windows is not supported.
- **Editing:** `Ctrl+Shift+L` selects only the matches visible on screen.
- **Text:**
  - Emoji and CJK characters show as boxes.
  - Input methods (IME) are not supported.
- **Scrolling:** the pixel scroll rarely runs while the Explorer is open (see the roadmap).
- **Window:**
  - The title is fixed and the font cannot be changed.
  - Undercurl is drawn straight.
- **Clipboard:** on Linux, copy and paste with other apps needs a clipboard tool.
- **Reload Window:** killing the window afterwards leaves Neovim running.
- **Copilot:** it needs a subscription and `:LspCopilotSignIn`.
- **Not tested yet:**
  - The native window on a real Mac.
  - The window download from a release.

## 10. Risks

| Risk | Effect | Mitigation |
| --- | --- | --- |
| LazyVim or a plugin changes upstream | Broken behavior after an update | Plugins pinned in `lazy-lock.json`, update checker off, E2E suites in CI |
| A Neovim upgrade changes input handling | Keyboard or mouse bugs (0.12.6 made the suite unstable) | Neovim pinned to 0.12.4; upgrade only with all suites green |
| GPU, driver or Wayland trouble | The window does not open | XWayland retry in the launcher, software GL in tests, prebuilt window for 4 platforms |
| macOS is never driven in CI | Mac-only regressions | A manual check on a real Mac before each release |
| CI cost, mostly macOS runners | Slow or expensive runs | One PR per batch of changes; `app.yml` is shared by CI and Release |
| Supply chain | A tampered download | Pinned versions with SHA-256, Actions pinned by commit, provenance attestations, Dependabot, secret scanning |
| One maintainer | Work stops when they are away | Tests, `CONTRIBUTING.md` and this plan |
| Trademarks | Legal trouble | No VS Code or LazyVim logos; the README says LazyCode is independent |

## 11. Decision log

| When | Decision | Why |
| --- | --- | --- |
| 0.1.0 | Build on LazyVim; do not fork it | Keep its look and plugin ecosystem with little upkeep |
| 0.1.0 | Isolated, pinned runtime | Same versions everywhere, no `sudo`, the person's own Neovim untouched |
| 0.1.0 | Neovim pinned to 0.12.4 | The keyboard and mouse suite was unstable on 0.12.6 |
| 0.1.0 | Right-click menus open on release | Opening on press lets the release close them |
| 2026-11-23 | Repository recreated with one clean commit; `v0.1.0-rc.1` published | |
| 2026-11-24 | `v0.1.0` stable, Homebrew tap | The release candidate passed the real install test and the Mac test |
| 0.2.0 | Native window replaces kitty | One app with its own pointer shapes, animation, Dock icon and Reload Window, and one less dependency |
| 0.2.0 | Side panels instead of LazyVim pickers | The Search picker behaved like the LazyVim menu; the IDE avoids LazyVim's own UI to prevent bugs |
| 0.2.0 | Hover goes through an RPC notification | `mousemoveevent` breaks clicks in `:popup` menus |
| 0.2.0 | Reload Window uses `:restart` | Neovim 0.12 restarts the server and the window joins it again, keeping the folder and files |
| 0.2.0 | noice disabled | It fails on the `restart` event |
| 0.2.0 | Icon font pinned and loaded by path | Distribution fonts lack many icons |
| 0.2.0 | Copilot, ESLint, Prettier on; Rust only with `cargo` | Common needs out of the box, without Rust tools for people who do not use Rust |

## 12. Working agreements

- **Branches:**
  - `main` is protected. Work on a branch, open a PR and wait for `CI OK`.
  - PRs are squash-merged, and their branches are deleted automatically.
  - Batch related changes into one PR, and hold pushes until the batch is ready. This saves CI
    runners.
- **Commits:**
  - Commit with the GitHub `noreply` email, so no personal address becomes public.
  - Never add AI attribution to commits or PRs.
- **Writing:** English only, in code and docs.
- **Before a PR:**
  - Run `stylua lua`, `shellcheck install.sh bin/lazycode tests/headless.sh`, and
    `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` in `app/`.
  - Run the suites with `tests/headless.sh`.
- **Releases:** follow [section 7](#7-release-process). Update this plan and `CHANGELOG.md` in the
  same PR.
