# Validation — 2026-10-19

Target: Omarchy 4.0.5, Hyprland 0.56.2. This is a source release candidate.

## Checked here

- 12 Python tests: strict settings validation, version/backend gating, disabling,
  fallback rule generation, unique shader cache keys, repeat integration,
  unrelated config preservation, symlink preservation, malformed JSON refusal,
  failed apply and failed install rollback, real CLI install/apply/disable/remove
  using an isolated HOME and a fake hyprctl boundary.
- Bash syntax checks for install.sh and uninstall.sh.
- All four shipped GLSL ES 3.20 shaders compile/link on Mesa OpenGL ES 3.2.
  31 frames per shader rendered against a synthetic monitor-sized texture with
  a smaller window sub-rectangle. Starting pixels match the original exactly;
  final alpha is zero; premultiplied colour never exceeds alpha in every frame.
- QML instantiation, visual inspection and qmllint with explicit stubs for
  Quickshell/Omarchy interfaces. Zero lint diagnostics with those stubs. This
  checks QML syntax and layout, not live shell imports, IPC or focus behaviour.

`previews/panel.png` is the actual QML rendered with a sample theme and interface
stubs. `previews/effects.gif` renders the actual shaders on a synthetic window.
Neither is a recording from a running Omarchy desktop.

## Must still be checked on the target desktop

1. Build/load pinned HyprWindowShade with hyprpm; confirm no config errors.
2. Install disabled; confirm the panel appears and theme changes update it.
3. Test each effect with the disposable foot window at all fragment sizes.
4. Close a window by shortcut, close button and app exit. Confirm a cancelled
   unsaved-document prompt never animates or destroys the window.
5. Test tiled/floating/fullscreen windows, monitor scaling/rotation and edges;
   confirm fragment clipping, direction, reflow and damage behave acceptably.
6. Test concurrent closes, GPU usage and NVIDIA/AMD/Intel as applicable.
7. Disable, restart the session, and uninstall; confirm defaults and unrelated
   configuration remain intact.

The container has no live Hyprland/Omarchy session. The upstream C++ renderer was
inspected but not compiled or loaded here. Actual compatibility and performance
remain unverified until the above checks pass.
