#!/bin/bash
# Regenerate stats.json, both card PNGs, and freeze any newly-completed month.
# Called on a schedule by launchd (com.claude-counter) and safe to run by hand.
#
# NOT `set -e`: a failure in one step must not silently skip the rest. Each step
# is run explicitly and its exit code recorded, so a partial failure is visible in
# the log instead of the script vanishing mid-run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

ROOT="$(cd "$HERE/.." && pwd)"

# launchd gives a minimal PATH; python3 and Chrome both need a real one.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LOG="$ROOT/out/refresh.log"
mkdir -p "$(dirname "$LOG")"

# Dependencies live in a repo-local venv, not in whatever site-packages the
# system python happens to have today. On 2026-09-09 Homebrew moved python3 from
# 3.13 to 3.14, which swapped in an empty site-packages: count.py and archive.py
# died on `import yaml` every run for the next eight days while render.py happily
# re-published the last good card. A venv pins the deps to this project, and
# rebuilding it whenever its imports stop resolving means the next interpreter
# bump repairs itself on the following run instead of quietly freezing the card.
VENV="$ROOT/.venv"
PY="$VENV/bin/python3"

venv_ok () { [ -x "$PY" ] && "$PY" -c 'import yaml, PIL' >/dev/null 2>&1; }

bootstrap_venv () {
  echo "--- venv (missing or broken: rebuilding)"
  rm -rf "$VENV"
  python3 -m venv "$VENV" \
    && "$PY" -m pip install --quiet --upgrade pip \
    && "$PY" -m pip install --quiet -r "$ROOT/requirements.txt"
  if venv_ok; then
    echo "  venv ready: $("$PY" --version 2>&1)"
  else
    echo "!!! venv bootstrap FAILED - falling back to system python3"
    PY="$(command -v python3)"
  fi
}

run () {   # run <label> <cmd...>
  local label="$1"; shift
  echo "--- $label"
  "$@"
  local rc=$?
  [ $rc -ne 0 ] && echo "!!! $label FAILED rc=$rc"
  return $rc
}

status=0
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') === python3=$(command -v python3)"
  venv_ok || bootstrap_venv
  run count   "$PY" count.py   || status=1
  run archive "$PY" archive.py || status=1
  run render  "$PY" render.py  || status=1
  echo "=== done, status=$status"
  echo
} >>"$LOG" 2>&1

tail -n 500 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
exit $status
