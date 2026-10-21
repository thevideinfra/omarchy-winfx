# Validation — 2026-10-21

Target: Omarchy 4.0.5, Hyprland 0.56.2.

## Checked

- 25 Python tests: strict settings validation, separate and synced open/close
  settings, version and backend gating, disabling, per-direction rule generation,
  constant rule tags, reverse playback of every effect, repeat integration,
  unrelated config preservation, symlink preservation, malformed JSON refusal,
  failed apply and failed install rollback, and a real CLI install/apply/disable/remove
  run using an isolated HOME and a fake hyprctl boundary.
- Bash syntax checks for `install.sh` and `uninstall.sh`.
- All ten shipped GLSL ES 3.20 shaders compile and link on Mesa OpenGL ES 3.2
  (`tests/render_shaders.py`). Each renders 31 frames against a synthetic
  monitor-sized texture with a smaller window sub-rectangle. Starting pixels match the
  original exactly, final alpha is zero, and premultiplied colour never exceeds alpha.
- Clean installs on fresh Omarchy VMs: add the plugin from the GitHub URL, click Install
  (no `sudo` prompt when `base-devel`, `pkgconf` and `git` are present), the backend builds
  and loads from `~/.config/omarchy-winfx/backend/`, and an effect applies.
- Live on one Omarchy 4.0.5 / Hyprland 0.56.2 session: install from the panel,
  applying every effect, opening and closing windows in Alacritty with the effects
  captured frame by frame, the panel at each density and font size, and migration
  from the plugin's earlier name. Nautilus, Strata and Brave were reported working
  by the author.

`docs/previews/panel.png` is a screenshot of the panel in the Omarchy shell.
`docs/previews/effects.gif` renders the shipped shaders on a synthetic window; it is
not a recording of the desktop.

## Known limitation

`foot` exits without leaving window content in Hyprland's close snapshot, so its close
cannot animate, with or without WinFX. Opening works.

## Not yet checked

1. Fullscreen windows, and monitor scaling or rotation at the window edges.
2. Concurrent closes and GPU cost across NVIDIA, AMD and Intel.
3. A cancelled unsaved-document prompt never animating or destroying the window.
4. Disabling, restarting the session and uninstalling on a second machine.
