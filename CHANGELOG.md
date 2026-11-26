# Changelog

## Unreleased

- LazyCode now runs in its own native window instead of kitty. kitty is no longer downloaded,
  and `~/.config/lazycode.local/kitty.conf` is no longer read.
- Icons come from a pinned Nerd Font symbols font, so they show without any font installed.
- On macOS, `LazyCode.app` is the window itself, with its own Dock icon and Retina rendering.
- Icons are drawn two cells wide, like kitty did, and the activity bar is aligned.
- The activity bar opens the terminal and a new Extensions panel (`Ctrl+Shift+X`) to search and
  turn LazyVim extras on or off with a click.
- The mouse pointer is a hand over icons, files, Welcome actions and tabs, an I-beam over text,
  and a resize arrow over panel borders.
- Search is a side panel like VS Code's, with replace and file filters. A click opens a result.
- Reload Window, in the activity bar or as `:LazyCodeReload`, restarts the editor in the same
  window with the same folder and files. It lights up after an Extensions change.
- The cursor blinks with a fade, and scrolling is animated.
- Activity bar icons are spaced out and answer clicks on the rows around them.
- The noice command line popup is gone: messages go to `:messages` and notifications.
- Text uses FiraCode Nerd Font Mono SemiBold at 13 pt, with JetBrains Mono as fallback. Both are
  pinned by the installer, so every machine shows the same font. `Ctrl+=`, `Ctrl+-` and `Ctrl+0`
  change the size, and `guifont` picks another font.
- Text is drawn as bold and bright as kitty drew it.
- The window and the macOS app have the LazyCode icon.
- Tabs start above the editor, after the open side panel.
- Search ignores case for lowercase queries, like VS Code, and `Ctrl+Alt+Enter` replaces all.
- Scrolling is smooth with the Explorer open too, and the cursor blinks faster.
- Files changed in other apps reload when you come back to the window.
- `lazycode doctor` warns on Linux when no clipboard tool is installed.
- Copilot (native), ESLint and Prettier come enabled, with format on save for JavaScript and
  TypeScript. Rust support turns on when `cargo` is installed.

## 0.1.0

First stable release.

- Fix the app not opening on macOS, where kitty has no `--class` option
- Open lazygit across the whole editor area, with the diff on the right
- Keep launcher errors in `~/.local/state/lazycode/launcher.log`

## 0.1.0-rc.1

First public release candidate.

- Welcome screen with New File, Open File, Open Folder, Clone Repository and recent projects
- VS Code style editing, shortcuts, mouse and multiple cursors on top of LazyVim
- Explorer with context menu and file operations
- Source Control sidebar powered by lazygit
- Integrated terminal with mouse selection, copy and paste
- Completion for the most common languages out of the box
- Installer for Linux and macOS with pinned, checksum-verified dependencies
