#!/bin/sh
# LazyCode installer for Linux and macOS. No sudo, nothing outside your home.
#   curl -fsSL https://raw.githubusercontent.com/pimpoknot/lazycode/main/install.sh | sh
# Options (environment): LAZYCODE_VERSION=v0.1.0, LAZYCODE_SKIP_TOOLS=1
set -eu

REPO="${LAZYCODE_REPO:-pimpoknot/lazycode}"
VERSION="${LAZYCODE_VERSION:-latest}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/lazycode"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
RUNTIME="${LAZYCODE_RUNTIME:-$DATA/lazycode-runtime}"
BIN_DIR="$HOME/.local/bin"
WORK=""

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then
    rm -rf -- "$WORK"
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required. $2"
}

detect_platform() {
  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=macos ;;
    *) die "Unsupported system: $(uname -s). LazyCode runs on Linux and macOS." ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) die "Unsupported architecture: $(uname -m)." ;;
  esac
}

check_requirements() {
  hint="Install it with your package manager."
  need curl "$hint"
  need tar "$hint"
  need git "$hint"
  need gzip "$hint"
  if [ "$OS" = linux ]; then
    need xz "Install the xz package (xz-utils on Debian/Ubuntu)."
  fi
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
    die "sha256sum or shasum is required."
  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
    if [ "$OS" = macos ]; then
      warn "No C compiler. For full syntax highlighting run: xcode-select --install"
    else
      warn "No C compiler. For full syntax highlighting install gcc (build-essential on Debian/Ubuntu)."
    fi
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

locate_source() {
  if [ -n "${LAZYCODE_SOURCE:-}" ]; then
    SOURCE=$LAZYCODE_SOURCE
    return
  fi
  case "$0" in
    */install.sh | install.sh)
      here=$(cd "$(dirname "$0")" && pwd)
      if [ -f "$here/.lazycode" ] && [ -f "$here/runtime/versions.lock" ]; then
        SOURCE=$here
        return
      fi
      ;;
  esac
  case "$REPO" in
    */*) ;;
    *) die "Invalid repository: $REPO." ;;
  esac
  tag=$VERSION
  if [ "$tag" = latest ]; then
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") ||
      die "Could not reach GitHub."
    tag=${url##*/}
    case "$tag" in
      "" | latest | releases) tag="" ;; # no stable release yet
    esac
  fi
  mkdir -p "$WORK/source"
  if [ -n "$tag" ]; then
    info "Downloading LazyCode $tag"
    archive="https://github.com/$REPO/archive/refs/tags/$tag.tar.gz"
  else
    warn "No stable release yet. Installing the development version from main."
    archive="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
  fi
  curl -fsSL "$archive" -o "$WORK/source.tar.gz" || die "Could not download LazyCode."
  tar -xzf "$WORK/source.tar.gz" -C "$WORK/source" --strip-components=1
  SOURCE=$WORK/source
}

link_tool() {
  ln -sf "$1" "$RUNTIME/bin/$2"
}

install_tool() {
  tool=$1 tool_version=$2 expected=$3 url=$4
  target="$RUNTIME/$tool"
  if [ -f "$target/.lazycode-version" ] && [ "$(cat "$target/.lazycode-version")" = "$tool_version" ]; then
    return
  fi
  info "Installing $tool $tool_version"
  file="$WORK/${url##*/}"
  curl -fL --retry 3 --progress-bar "$url" -o "$file" || die "Could not download $tool."
  actual=$(sha256 "$file")
  [ "$actual" = "$expected" ] || die "Checksum mismatch for $tool: expected $expected, got $actual."
  staging="$RUNTIME/.staging-$tool"
  rm -rf -- "$staging"
  mkdir -p "$staging"
  case "$tool:$OS" in
    fonts:*) tar -xJf "$file" -C "$staging" ;;
    font-*:*)
      # Each archive has every Nerd Font variant: keep the Mono ones the window uses, with ligatures.
      tar -xJf "$file" -C "$staging"
      find "$staging" -name '*.[ot]tf' \( ! -name '*NerdFontMono-*' -o -name '*NLNerdFontMono-*' \) -exec rm -f {} +
      ;;
    lazygit:*) tar -xzf "$file" -C "$staging" ;;
    *) tar -xzf "$file" -C "$staging" --strip-components=1 ;;
  esac
  printf '%s\n' "$tool_version" >"$staging/.lazycode-version"
  rm -rf -- "$target"
  mv "$staging" "$target"
  rm -f -- "$file"
}

install_runtime() {
  mkdir -p "$RUNTIME/bin"
  lock="$SOURCE/runtime/versions.lock"
  [ -f "$lock" ] || die "Missing $lock."
  found=0
  while read -r tool tool_version entry_os entry_arch checksum url; do
    case "$tool" in "#"* | "") continue ;; esac
    if [ "$entry_os" = "$OS" ] && [ "$entry_arch" = "$ARCH" ]; then
      install_tool "$tool" "$tool_version" "$checksum" "$url"
      found=$((found + 1))
    fi
  done <"$lock"
  [ "$found" -gt 0 ] || die "No runtime available for $OS $ARCH."

  link_tool "$RUNTIME/nvim/bin/nvim" nvim
  link_tool "$RUNTIME/lazygit/lazygit" lazygit
  link_tool "$RUNTIME/ripgrep/rg" rg
  link_tool "$RUNTIME/fd/fd" fd
  link_tool "$RUNTIME/node/bin/node" node
  link_tool "$RUNTIME/node/bin/npm" npm
  link_tool "$RUNTIME/node/bin/npx" npx
  rm -rf -- "$RUNTIME/kitty" "$RUNTIME/bin/kitty" # left by LazyCode 0.1
  install_window
}

# The native window: built by Homebrew, downloaded from the matching release, or built here.
install_window() {
  target="$RUNTIME/bin/lazycode-app"
  version=$(cat "$SOURCE/VERSION")
  if [ -x "$SOURCE/bin/lazycode-app" ]; then
    cp "$SOURCE/bin/lazycode-app" "$target.new"
  elif [ ! -d "$SOURCE/.git" ] && download_window "$version"; then
    :
  elif command -v cargo >/dev/null 2>&1; then
    info "Building the LazyCode window (this can take a few minutes)"
    cargo build --release --locked --quiet --manifest-path "$SOURCE/app/Cargo.toml" \
      --target-dir "$WORK/target" || die "Could not build the LazyCode window."
    cp "$WORK/target/release/lazycode-app" "$target.new"
  else
    die "No LazyCode window for $OS $ARCH in version $version. Install Rust from https://rustup.rs and run again."
  fi
  chmod +x "$target.new"
  mv -f "$target.new" "$target"
}

download_window() {
  name="lazycode-app-$1-$OS-$ARCH.tar.gz"
  base="https://github.com/$REPO/releases/download/v$1"
  curl -fsSL "$base/SHA256SUMS" -o "$WORK/SHA256SUMS" 2>/dev/null || return 1
  expected=$(awk -v n="$name" '$2 == n { print $1 }' "$WORK/SHA256SUMS")
  [ -n "$expected" ] || return 1
  info "Downloading the LazyCode window"
  curl -fL --retry 3 --progress-bar "$base/$name" -o "$WORK/$name" || die "Could not download the LazyCode window."
  actual=$(sha256 "$WORK/$name")
  [ "$actual" = "$expected" ] || die "Checksum mismatch for $name: expected $expected, got $actual."
  tar -xzf "$WORK/$name" -C "$WORK"
  mv "$WORK/lazycode-app" "$target.new"
}

install_app() {
  source_real=$(cd "$SOURCE" && pwd -P)
  if [ -d "$CONFIG" ] && [ "$(cd "$CONFIG" && pwd -P)" = "$source_real" ]; then
    return
  fi
  if [ -d "$CONFIG/.git" ]; then
    warn "$CONFIG is a Git checkout. Keeping it as is."
    return
  fi
  OLD_EXTRAS=""
  if [ -e "$CONFIG" ]; then
    if [ -f "$CONFIG/.lazycode" ]; then
      OLD_EXTRAS="$WORK/old-lazyvim.json"
      cp "$CONFIG/lazyvim.json" "$OLD_EXTRAS" 2>/dev/null || OLD_EXTRAS=""
      rm -rf -- "$CONFIG"
    else
      backup="$CONFIG.backup.$(date +%Y%m%d%H%M%S)"
      warn "$CONFIG belongs to something else. Moved it to $backup"
      mv "$CONFIG" "$backup"
    fi
  fi
  info "Installing LazyCode to $CONFIG"
  staging="$CONFIG.staging"
  rm -rf -- "$staging"
  mkdir -p "$staging"
  (cd "$SOURCE" && tar --exclude=./.git --exclude=./tests --exclude=./.github --exclude=./app/target --exclude=./bin/lazycode-app -cf - .) | (cd "$staging" && tar -xf -)
  mv "$staging" "$CONFIG"
  chmod +x "$CONFIG/bin/lazycode" "$CONFIG/install.sh"
  if [ -n "$OLD_EXTRAS" ]; then
    NVIM_APPNAME=lazycode "$RUNTIME/bin/nvim" --clean -l "$CONFIG/scripts/merge-extras.lua" \
      "$OLD_EXTRAS" "$CONFIG/lazyvim.json" || warn "Could not keep your extra languages."
  fi
}

install_launchers() {
  mkdir -p "$BIN_DIR"
  ln -sf "$CONFIG/bin/lazycode" "$BIN_DIR/lazycode"
  : >"$RUNTIME/manifest"
  printf '%s\n' "$BIN_DIR/lazycode" >>"$RUNTIME/manifest"
  if [ "$OS" = linux ]; then
    apps="$DATA/applications"
    icons="$DATA/icons/hicolor/scalable/apps"
    mkdir -p "$apps" "$icons"
    cp "$CONFIG/assets/lazycode.svg" "$icons/lazycode.svg"
    sed "s|@LAZYCODE@|$BIN_DIR/lazycode|g" "$CONFIG/packaging/linux/lazycode.desktop" >"$apps/lazycode.desktop"
    printf '%s\n%s\n' "$apps/lazycode.desktop" "$icons/lazycode.svg" >>"$RUNTIME/manifest"
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$apps" >/dev/null 2>&1 || true
    fi
  else
    bundle="$HOME/Applications/LazyCode.app"
    rm -rf -- "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    mkdir -p "$bundle/Contents/Resources"
    cp "$CONFIG/packaging/macos/Info.plist" "$bundle/Contents/Info.plist"
    cp "$CONFIG/packaging/macos/LazyCode.icns" "$bundle/Contents/Resources/LazyCode.icns"
    # The window itself lives in the bundle, so the Dock shows LazyCode.
    cp "$RUNTIME/bin/lazycode-app" "$bundle/Contents/MacOS/LazyCode"
    printf '%s\n' "$bundle" >>"$RUNTIME/manifest"
  fi
}

install_plugins() {
  info "Installing plugins"
  PATH="$RUNTIME/bin:$PATH" NVIM_APPNAME=lazycode nvim --headless "+Lazy! restore" +qa </dev/null >/dev/null 2>&1 ||
    die "Could not install the plugins."
  if [ "${LAZYCODE_SKIP_TOOLS:-}" = 1 ]; then
    return
  fi
  info "Installing language servers and syntax parsers (this can take a few minutes)"
  PATH="$RUNTIME/bin:$PATH" NVIM_APPNAME=lazycode nvim --headless "+LazyCodeInstallTools" +qa </dev/null >/dev/null 2>&1 ||
    warn "Some language tools failed to install. They will retry the next time you open LazyCode."
}

finish() {
  info "LazyCode $(cat "$CONFIG/VERSION") is ready"
  case ":$PATH:" in
    *":$BIN_DIR:"*) echo "Run: lazycode" ;;
    *)
      echo "Add this to your shell profile, then open a new terminal:"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo "Then run: lazycode"
      ;;
  esac
}

main() {
  [ "$(id -u)" -ne 0 ] || die "Do not run the installer as root."
  detect_platform
  check_requirements
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lazycode-install.XXXXXX")
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  locate_source
  install_runtime
  install_app
  install_launchers
  install_plugins
  finish
}

main "$@"
