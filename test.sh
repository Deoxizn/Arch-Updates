#!/usr/bin/env bash
# Checks available on this machine. qmllint cannot resolve Quickshell's
# modules here, so only parse errors count as failures.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$root"

fail=0

printf '== node tests ==\n'
node --test tests/*.test.js || fail=1

printf '\n== python tests ==\n'
python3 tests/check_updates.test.py || fail=1

printf '\n== QML parse ==\n'
qmllint_bin=/usr/lib/qt6/bin/qmllint
if [[ -x $qmllint_bin ]]; then
  for file in BarWidget.qml Panel.qml SystemSettings.qml; do
    if "$qmllint_bin" "$file" 2>&1 | grep -E '^Error|Syntax|Expected|Unexpected' >&2; then
      printf 'parse errors in %s\n' "$file" >&2
      fail=1
    else
      printf 'ok  %s\n' "$file"
    fi
  done
else
  printf 'qmllint not installed; skipped\n'
fi

exit "$fail"
