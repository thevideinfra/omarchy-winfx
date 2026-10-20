#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/videinfra.omarchy-effects"
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
  missing=()
  for package in base-devel hyprpm cmake cpio git pkgconf; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  if (( ${#missing[@]} )); then
    echo "Installing missing backend build tools: ${missing[*]}"
    if [[ -t 0 && -t 1 ]]; then
      sudo pacman -S --needed "${missing[@]}"
    else
      pkexec pacman -S --needed "${missing[@]}"
    fi
  fi
  echo 'Building HyprWindowShade for your running compositor with hyprpm…'
  # hyprpm owns header matching and upstream commit pins. Never force-load a .so.
  hyprpm update
  if ! hyprpm list | grep -Fq 'HyprWindowShade'; then
    hyprpm add https://github.com/ManofJELLO/HyprWindowShade
  fi
  hyprpm enable HyprWindowShade
  hyprpm reload -n
fi
if [[ $SRC != "$DEST" ]]; then
  [[ ! -L $DEST ]] || { echo 'Refusing to replace a symlinked plugin directory.' >&2; exit 1; }
  if [[ -e $DEST ]]; then
    BACKUP="$HOME/.config/omarchy-effects/backups/plugin.$(date +%s%N)"
    mkdir -p "$(dirname -- "$BACKUP")"
    cp -a -- "$DEST" "$BACKUP"
  fi
  mkdir -p "$DEST"
  cp -a "$SRC/manifest.json" "$SRC/Panel.qml" "$SRC/Model.js" "$SRC/AccentSource.qml" "$SRC/bin" "$SRC/lib" "$SRC/shaders" \
    "$SRC/install.sh" "$SRC/uninstall.sh" "$SRC/README.md" "$SRC/LICENSE" "$DEST/"
fi
"$DEST/bin/omarchy-effects" install
omarchy restart shell
printf '\nomarchy-effects installed, initially disabled. Open its bar panel, choose an effect, switch ON and Apply.\n'
if (( ! backend )); then
  printf 'If the panel reports a missing backend, run: %q --backend\n' "$DEST/install.sh"
fi
