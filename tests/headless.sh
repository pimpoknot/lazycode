#!/bin/sh
# Runs the end-to-end suites on a private virtual display, so no window ever
# appears on your desktop.
#   tests/headless.sh                 all suites
#   tests/headless.sh explorer kitty  only these suites
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
command -v xvfb-run >/dev/null 2>&1 || {
  echo "xvfb-run is required (package: xvfb)." >&2
  exit 2
}

[ "$#" -gt 0 ] || set -- editing terminal welcome explorer kitty complete
logs=$(mktemp -d "${TMPDIR:-/tmp}/lazycode-tests.XXXXXX")
failed=0

for suite in "$@"; do
  log="$logs/$suite.log"
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u SWAYSOCK -u NVIM \
    LIBGL_ALWAYS_SOFTWARE=1 \
    timeout 240 xvfb-run -a -s "-screen 0 1600x1000x24 +extension GLX -nolisten tcp" \
    python3 -I -u "$root/tests/e2e_$suite.py" </dev/null >"$log" 2>&1
  code=$?
  printf '%-10s exit=%s  %s\n' "$suite" "$code" "$(tail -n 1 "$log" | cut -c1-40)"
  if [ "$code" -ne 0 ]; then
    failed=1
    grep -E '^(FAIL|HUNG|NOT FOUND|ITEM NOT|LAZYGIT DID|POPUP DID|input did|menu did|dialog did|did not|welcome did|missing item|kitty exited|Traceback)' "$log" | head -n 6 | cut -c1-120
    echo "  log: $log"
  fi
done

[ "$failed" -eq 1 ] || rm -rf -- "$logs"
exit "$failed"
