#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/videinfra.omarchy-winfx"
backend=0
case "${1:-}" in
  --backend) backend=1 ;;
  '') ;;
  *) echo 'Usage: ./install.sh [--backend]' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Too many arguments' >&2; exit 2; }
[[ $(id -u) -ne 0 ]] || { echo 'Run as your desktop user, not root.' >&2; exit 1; }
for tool in python3 hyprctl omarchy; do
  command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }
done
[[ -f $HOME/.config/hypr/hyprland.lua && -f $HOME/.config/omarchy/shell.json ]] || {
  echo 'Requires Omarchy 4 with hyprland.lua and shell.json.' >&2; exit 1;
}
python3 - "$SRC/lib" <<'PY'
import json, subprocess, sys
sys.path.insert(0, sys.argv[1])
from config import TARGET_HYPRLAND
v = json.loads(subprocess.check_output(['hyprctl', '-j', 'version']))
if str(v.get('tag', '')).removeprefix('v') != TARGET_HYPRLAND:
    sys.exit(f'This release targets Hyprland {TARGET_HYPRLAND}. Nothing installed.')
errors = json.loads(subprocess.check_output(['hyprctl', '-j', 'configerrors']))
errors = [error for error in errors if error.strip()]
if errors:
    sys.exit('Fix existing Hyprland configuration errors before installing: ' + str(errors))
PY
if (( backend )); then
  # The backend is built from source against the headers the hyprland package already
  # installed, so the only packages needed are the compiler, make, git and pkgconf.
  missing=()
  for package in base-devel pkgconf git; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  if (( ${#missing[@]} )); then
    echo "Installing missing backend build tools: ${missing[*]}"
    if [[ -t 0 && -t 1 ]]; then
      sudo pacman -S --needed "${missing[@]}" || fail=1
    else
      pkexec pacman -S --needed "${missing[@]}" || fail=1
    fi
    if [[ ${fail:-0} == 1 ]]; then
      echo 'Installing the build tools failed. If pacman says a target was not found, the package' >&2
      echo 'database may be stale: run `sudo pacman -Syu`, then click Install again.' >&2
      exit 1
    fi
  fi
fi
if [[ $SRC != "$DEST" ]]; then
  [[ ! -L $DEST ]] || { echo 'Refusing to replace a symlinked plugin directory.' >&2; exit 1; }
  if [[ -e $DEST ]]; then
    BACKUP="$HOME/.config/omarchy-winfx/backups/plugin.$(date +%s%N)"
    mkdir -p "$(dirname -- "$BACKUP")"
    cp -a -- "$DEST" "$BACKUP"
  fi
  mkdir -p "$DEST"
  cp -a "$SRC/manifest.json" "$SRC/Panel.qml" "$SRC/Model.js" "$SRC/AccentSource.qml" "$SRC/bin" "$SRC/lib" "$SRC/shaders" \
    "$SRC/install.sh" "$SRC/uninstall.sh" "$SRC/README.md" "$SRC/LICENSE" "$DEST/"
fi
"$DEST/bin/omarchy-winfx" install
if (( backend )); then
  echo 'Building HyprWindowShade against the installed Hyprland headers…'
  "$DEST/bin/omarchy-winfx" backend
fi
# The panel runs this itself and re-reads its state, so it sets WINFX_NO_RESTART.
[[ -n ${WINFX_NO_RESTART:-} ]] || omarchy restart shell
printf '\nWinFX installed, initially disabled. Open its bar panel, choose an effect, switch ON and Apply.\n'
if (( ! backend )); then
  printf 'If the panel reports a missing backend, click Build backend or run: %q --backend\n' "$DEST/install.sh"
fi
