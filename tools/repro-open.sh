#!/bin/sh
# Checks that the panel opens complete right after a shell restart.
# It restarts the shell, opens the panel and captures it 0.45 s and 3.45 s
# after opening; if more than 100 pixel rows differ between the two, sections
# arrived late and the run is RED (exit 1).
#
#   tools/repro-open.sh [reopen]
#
# "reopen" opens and closes the panel once first, then measures the second
# opening. PANEL_GEOMETRY ("x,y wxh", grim syntax) sets the captured area;
# point it at where the panel opens on your monitor.
set -eu
geometry=${PANEL_GEOMETRY:-"1100,0 820x700"}
out=$(mktemp -d "${TMPDIR:-/tmp}/logitech-repro.XXXXXX")
here=$(dirname "$0")
ipc() { omarchy-shell com.aeonarc.logitech-panel "$1" >/dev/null 2>&1; }
pause() { timeout 10 sh -c "sleep $1"; }
cap() { grim -g "$geometry" -t ppm "$out/$1.ppm"; }

omarchy restart shell >/dev/null 2>&1
timeout 30 sh -c 'until omarchy-shell com.aeonarc.logitech-panel close >/dev/null 2>&1; do sleep 0.3; done'
pause 2
if [ "${1:-}" = reopen ]; then
  ipc open; pause 3
  ipc close; pause 1
fi
ipc open
pause 0.45; cap early
pause 3; cap late
ipc close
echo "captures: $out"
python3 -I "$here/rowdiff.py" "$out/early.ppm" "$out/late.ppm"
