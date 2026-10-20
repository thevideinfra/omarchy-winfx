#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/videinfra.omarchy-effects"
[[ $(id -u) -ne 0 ]] || { echo 'Run as your desktop user, not root.' >&2; exit 1; }
"$HERE/bin/omarchy-effects" uninstall
# The integration is removed and checked before deleting its installed code.
if [[ -d $DEST && ! -L $DEST ]]; then rm -rf -- "$DEST"; fi
omarchy restart shell
printf 'omarchy-effects removed. Settings/backups retained in ~/.config/omarchy-effects. HyprWindowShade remains installed.\n'
