#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/videinfra.omarchy-winfx"
[[ $(id -u) -ne 0 ]] || { echo 'Run as your desktop user, not root.' >&2; exit 1; }
"$HERE/bin/omarchy-winfx" uninstall
# The integration is removed and checked before deleting its installed code.
if [[ -d $DEST && ! -L $DEST ]]; then rm -rf -- "$DEST"; fi
omarchy restart shell
printf 'WinFX removed. Settings/backups retained in ~/.config/omarchy-winfx. HyprWindowShade remains installed.\n'
