# Contributing

Bug reports and pull requests are welcome.

## Development setup

```sh
git clone https://github.com/pimpoknot/lazycode ~/.config/lazycode
~/.config/lazycode/install.sh
lazycode
```

The repository root is the Neovim config. The LazyCode code lives in `lua/lazycode/`.

## Tests

The tests drive a real editor on a private virtual display, so no window appears on your
desktop. They need `python3`, `tmux` and `xvfb`.

```sh
tests/headless.sh                 # all suites
tests/headless.sh explorer kitty  # only these suites
```

The suites are `editing`, `terminal`, `welcome`, `explorer`, `kitty` and `complete`.

## Updating dependencies

```sh
python3 scripts/update-versions.py
```

This rewrites `runtime/versions.lock` with the latest releases and their checksums.

## Pull requests

- Keep each change focused, and explain how you tested it.
- Run `stylua lua` and `shellcheck install.sh bin/lazycode`.
- For input or layout changes, say whether you tested on Linux, macOS, or both.
