# omarchy-effects

Window open and close effects for Omarchy. Crumble, Shatter, Dissolve and Pixelate, picked from a panel that follows your theme.

<p>
  <img src="docs/previews/panel.png" alt="The omarchy-effects panel with its version and GitHub link in the header: the four effects and the default animation, duration, fragment size, backend status and the Test window, Reset and Apply buttons" width="360">
</p>

![Actual shaders rendered on a synthetic window](docs/previews/effects.gif)

Targets **Omarchy 4.0.5 / Hyprland 0.56.2**. The HyprWindowShade backend is
third-party experimental compositor code, built against your running Hyprland by
hyprpm. Offscreen shader checks are described in `docs/VALIDATION.md`.

## Install

```bash
omarchy plugin add https://github.com/thevideinfra/omarchy-effects.git --enable --yes
```

The widget appears in the bar. Open it and click **Install**. A terminal opens and
runs `install.sh`: it writes one marked Lua loader into `hyprland.lua`, builds the
backend if it is missing, restarts the shell and leaves effects **disabled**.

The backend step checks for `base-devel`, `hyprpm`, `cmake`, `cpio`, `git` and
`pkgconf`, and installs missing packages through pacman. It asks for administrator
authorization through `sudo` in the terminal. Declined or failed package
installation stops setup. It then installs/builds/enables
[HyprWindowShade](https://github.com/ManofJELLO/HyprWindowShade). hyprpm may request
permission to prepare matching headers. Review its output; the installer never
forces a plugin load or upgrades Hyprland. The same steps run from a shell with
`~/.config/omarchy/plugins/videinfra.omarchy-effects/install.sh --backend`
(without `--backend` if the backend is already loaded).

Then select Crumble, switch **ON**, and **Apply**. Choose **Test window** and press
any key inside the window to close it. Tests use applied settings; apply any pending
edits first.

## Controls

- **Effect:** Crumble falls in pieces; Shatter scatters rotating pieces;
  Dissolve removes fine blocks; Pixelate enlarges blocks before fading.
- **Duration:** 150–1500 ms, ±50ms buttons and 250/450/750ms presets.
- **Fragment size:** Small / Medium / Large; also controls dissolve/pixel blocks.
- **Animate:** Closing, Opening or Both. Opening plays the chosen effect in
  reverse: the window starts broken up and assembles itself.
- **OFF or Default:** restores the pre-existing open and close animations.
- **Reset:** stages disabled, Crumble, 450ms, medium. Apply commits it.
- **Keyboard:** arrows or h/j/k/l select; Return applies; Escape closes.

- **Make it yours.** The ⚙ in the panel header opens its settings: a
  **Compact**, **Normal** or **Comfortable** layout, a **Small**, **Normal** or
  **Large** font size, an accent colour (the theme's own, or any colour from its
  palette) and a switch for the version and GitHub link. They are stored in
  `shell.json` and also appear under `omarchy bar set videinfra.omarchy-effects`.

The panel follows the shell's current theme colours, font, border and scaling.
There is no background polling process. The preview uses `foot` and `bash`,
both supplied by Omarchy. No other window is closed by the preview button.

## Behaviour and limitations

Close requests are untouched. The backend animates the compositor's closing
snapshot after the application actually closes, including the close button,
keyboard shortcut and application exit. Unsaved-document prompts remain normal.
No screenshots are stored. Opening, movement and workspace animations are untouched.

The plugin sets **fallback** close and open shaders; explicit per-application shader
rules take priority. It doesn't animate layer surfaces (bar, launcher, popups).
Opening runs on top of Hyprland's own open animation, so a strong `windowsIn`
fade or popin can mask part of it. Hyprland animations must be enabled so a close snapshot exists. Fullscreen,
rotated/scaled monitors, NVIDIA and multiple simultaneous closes need live testing.
Fragment travel is limited and may clip at monitor edges. Shatter uses rotating
rectangular pieces, not a physics simulation or irregular glass mesh.

This release intentionally rejects other Hyprland versions. After an upgrade,
leave effects disabled until compatibility has been checked. `hyprpm update`
rebuilds shared plugins; a compositor restart may also be required after package
updates. The installed version number alone is not proof of matching binary ABI;
never bypass hyprpm's checks or force-load a `.so`.

## Files and recovery

- Plugin: `~/.config/omarchy/plugins/videinfra.omarchy-effects/`
- Settings: `~/.config/omarchy-effects/settings.json`
- Generated shader/config: `~/.config/omarchy-effects/shaders/*.glsl`, `active.lua`
- Backups: `~/.config/omarchy-effects/backups/`
- Integration: one line ending `-- omarchy-effects managed loader` in
  `~/.config/hypr/hyprland.lua`; one widget in `~/.config/omarchy/shell.json`.

Writes are serialized and replaced atomically per file; failed reloads restore
prior files. Backups are retained before editing integration files. Symlinked
configuration files keep their links. Multi-file updates are not power-loss
atomic. No keybindings are changed. Settings use their own file; panel visual
properties come directly from the shell.

If startup is affected, remove the single line ending
`-- omarchy-effects managed loader` from `~/.config/hypr/hyprland.lua` from a TTY.
This prevents the rule and its startup `hyprpm reload` callback from running.
If you have another hyprpm startup hook, also run `hyprpm disable HyprWindowShade`
before restarting the session. Do not delete unrelated configuration.

## Uninstall

Run before deleting the plugin directory:

```bash
~/.config/omarchy/plugins/videinfra.omarchy-effects/uninstall.sh
```

Removes its loader, bar entry and installed plugin files, reloads Hyprland and
restarts the shell. Keeps settings/backups and the shared HyprWindowShade backend.
`omarchy plugin remove` alone cannot remove the Lua loader, so use the script.

## CLI

```bash
~/.config/omarchy/plugins/videinfra.omarchy-effects/bin/omarchy-effects status
~/.config/omarchy/plugins/videinfra.omarchy-effects/bin/omarchy-effects apply \
  '{"enabled":true,"effect":"crumble","duration":450,"size":"medium"}'
~/.config/omarchy/plugins/videinfra.omarchy-effects/bin/omarchy-effects preview
```

The helper uses Python's standard library. Effect and settings input is validated;
commands use argv, never shell interpolation. Homes containing whitespace or `@`
are rejected for shader activation because the backend's shader-tag syntax uses
those characters as separators.

## Development

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh uninstall.sh
python3 tests/render_shaders.py --output /tmp/omarchy-effects-frames
```

The optional shader renderer requires Mesa EGL with OpenGL ES 3.2 and Pillow.
It compiles the actual shipped shaders, checks their endpoints, and renders a
comparison GIF. It does not test the compositor's snapshot integration.

Design reference: [omaudiopanel](https://github.com/thevideinfra/omaudiopanel) and
[Tandem](https://github.com/thevideinfra/tandem). Backend API reference:
HyprWindowShade commit `4414596c2fbb64cb5bb4aa7342900051338fed7a`, with upstream
0.56.2 compatibility pin `a4c6b8af424a189072427c4c90ef2938e1b481d3`.
