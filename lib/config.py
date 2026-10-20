"""Validated settings and reversible Omarchy integration. Standard library only."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

PLUGIN_ID = 'videinfra.omarchy-winfx'
TARGET_HYPRLAND = '0.56.2'
MARKER = '-- omarchy-winfx managed loader'
# effect/duration/size belong to closing, the open* keys to opening. With sync on,
# opening mirrors closing and the open* keys are rewritten to match on every Apply.
DEFAULTS = {'enabled': False, 'effect': 'crumble', 'duration': 450, 'size': 'medium', 'when': 'close',
            'sync': True, 'openEffect': 'crumble', 'openDuration': 450, 'openSize': 'medium'}
EFFECTS = ('crumble', 'shatter', 'dissolve', 'pixelate', 'explode', 'build', 'blinds', 'glitch', 'default')
WHEN = ('close', 'open', 'both')
SIZES = {'small': 28, 'medium': 18, 'large': 11}

class Context:
    def __init__(self, home=None, plugin=None):
        self.home = Path(home) if home is not None else Path.home()
        self.plugin = Path(plugin) if plugin is not None else Path(__file__).resolve().parents[1]
        self.state = self.home / '.config/omarchy-winfx'
        self.settings = self.state / 'settings.json'
        self.active = self.state / 'active.lua'
        self.hypr = self.home / '.config/hypr/hyprland.lua'
        self.shell = self.home / '.config/omarchy/shell.json'


def side(value, opening=False):
    """(effect, duration, size) for one direction."""
    if opening:
        return value['openEffect'], value['openDuration'], value['openSize']
    return value['effect'], value['duration'], value['size']


def directions(value):
    """Directions with a shader to play: (opening, rule name, rule tag)."""
    if not value['enabled']:
        return []
    return [(opening, name, tag)
            for opening, name, tag in ((False, 'close', 'shader_close_default'), (True, 'open', 'shader_open_default'))
            if value['when'] in (name, 'both') and side(value, opening)[0] != 'default']


def validate(value):
    if not isinstance(value, dict) or set(value) != set(DEFAULTS):
        raise ValueError('Settings require exactly ' + ', '.join(DEFAULTS) + '.')
    if type(value['enabled']) is not bool or type(value['sync']) is not bool:
        raise ValueError('enabled and sync must be true or false.')
    for opening in (False, True):
        effect, duration, size = side(value, opening)
        if effect not in EFFECTS:
            raise ValueError('Unknown effect.')
        if type(duration) is not int or not 150 <= duration <= 1500:
            raise ValueError('Duration must be an integer from 150 to 1500 milliseconds.')
        if not isinstance(size, str) or size not in SIZES:
            raise ValueError('Fragment size must be small, medium or large.')
    if value['when'] not in WHEN:
        raise ValueError('when must be close, open or both.')
    value = dict(value)
    if value['sync'] and value['when'] == 'both':
        value['openEffect'], value['openDuration'], value['openSize'] = side(value)
    return value


def read_settings(ctx):
    if not ctx.settings.exists():
        return dict(DEFAULTS)
    saved = json.loads(ctx.settings.read_text())
    # Files from before opening had its own settings: opening follows closing.
    for key in ('effect', 'duration', 'size'):
        saved.setdefault('open' + key.capitalize(), saved.get(key, DEFAULTS[key]))
    return validate({**DEFAULTS, **saved})


def atomic_write(path, content):
    # Preserve symlinked dotfiles by replacing the target, not the link itself.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content.encode() if isinstance(content, str) else content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def locked(ctx):
    ctx.state.mkdir(parents=True, exist_ok=True)
    with (ctx.state / '.lock').open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


@contextmanager
def transaction(paths):
    previous = {p: p.read_bytes() if p.exists() else None for p in paths}
    try:
        yield
    except Exception:
        for path, content in previous.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, content)
        raise


def run(args, timeout=15):
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'{args[0]} failed')
    return result.stdout


def probe():
    result = {'version': '', 'backend': False, 'error': ''}
    try:
        data = json.loads(run(['hyprctl', '-j', 'version']))
        result['version'] = str(data.get('tag', '')).removeprefix('v')
        plugins = json.loads(run(['hyprctl', '-j', 'plugin', 'list']))
        result['backend'] = any(p.get('name') == 'HyprWindowShade' for p in plugins)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, AttributeError, TypeError) as error:
        result['error'] = str(error)
    return result


def require_backend():
    data = probe()
    if data['version'] != TARGET_HYPRLAND:
        raise RuntimeError('Requires running Hyprland ' + TARGET_HYPRLAND + '; detected ' + (data['version'] or 'no compositor') + '.')
    if not data['backend']:
        raise RuntimeError('HyprWindowShade is not loaded. Run install.sh --backend, then reopen this panel.')


def lua_string(value):
    # ASCII JSON strings are valid Lua for these paths, except \u escapes.
    # Reject control characters rather than emitting ambiguous config.
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in value):
        raise ValueError('Paths containing control characters are not supported.')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def shader_source(ctx, value, opening=False):
    effect, duration, size = side(value, opening)
    source = (ctx.plugin / 'shaders' / (effect + '.glsl')).read_text()
    if opening:
        # Opening plays the closing effect backwards: the window starts fully
        # broken up and assembles itself as progress runs 0 to 1.
        forward = 'float p=clamp(progress,0.0,1.0);'
        if forward not in source:
            raise ValueError('Shader ' + effect + ' cannot play in reverse.')
        source = source.replace(forward, 'float p=clamp(1.0-progress,0.0,1.0);')
    # The duration lives in the shader, not the rule tag, so the tag never changes.
    source, count = re.subn(r'// @duration [0-9.]+', f"// @duration {duration / 1000:.3f}", source)
    if count != 1:
        raise ValueError('Shader ' + effect + ' must declare one @duration.')
    return source.replace('#define CELLS 18.0', f"#define CELLS {SIZES[size]}.0")


def shader_path(ctx, value, opening=False):
    # One fixed file per direction, rewritten in place. A window keeps the tags
    # it was given, so a path that changed with every Apply would pile up
    # stale tags on open windows and the backend would pick between them by name.
    return ctx.state / 'shaders' / ('open.glsl' if opening else 'close.glsl')


def shader_tags(ctx, value):
    """(rule name, tag) per animation the settings ask for. Opening is a separate rule."""
    tags = []
    for opening, name, tag in directions(value):
        # Tag parsing uses whitespace as a separator and the backend reserves @.
        path = str(shader_path(ctx, value, opening))
        if '@' in path or any(ch.isspace() for ch in path):
            raise ValueError('The shader backend requires a home path without whitespace or @.')
        tags.append(('omarchy-winfx-' + name, '+' + tag + ':' + path))
    return tags


def render_lua(value, ctx):
    lines = ['-- Generated by WinFX. Change settings through the panel.']
    tags = shader_tags(ctx, value)
    if tags:
        lines += ['hl.on("hyprland.start", function()',
                  '    hl.exec_cmd("hyprpm reload -n")', 'end)']
        for name, tag in tags:
            lines += ['hl.window_rule({', f'    name = "{name}",', '    match = { class = ".*" },',
                      '    tag = ' + lua_string(tag) + ',', '})']
    return '\n'.join(lines) + '\n'


def reload_checked():
    run(['hyprctl', 'reload'])
    errors = json.loads(run(['hyprctl', '-j', 'configerrors']))
    errors = [error for error in errors if error.strip()]
    if errors:
        raise RuntimeError('Hyprland configuration error: ' + str(errors))


def prune_shaders(ctx):
    """Delete shaders from releases that named them by content hash."""
    for old in (ctx.state / 'shaders').glob('*-*.glsl'):
        old.unlink(missing_ok=True)


def apply(ctx, value):
    value = validate(value)
    active = directions(value)
    if active:
        require_backend()
    lua = render_lua(value, ctx)
    shaders = {shader_path(ctx, value, opening): shader_source(ctx, value, opening)
               for opening, _, _ in active}
    with locked(ctx):
        try:
            with transaction([ctx.active, ctx.settings] + list(shaders)):
                for target, shader in shaders.items():
                    atomic_write(target, shader)
                atomic_write(ctx.active, lua)
                reload_checked()
                atomic_write(ctx.settings, json.dumps(value, indent=2) + '\n')
            prune_shaders(ctx)
        except Exception:
            # Best effort reload of restored config; keep the original error.
            try:
                run(['hyprctl', 'reload'])
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                pass
            raise
    return value


def loader(ctx):
    return 'dofile(' + lua_string(str(ctx.active)) + ') ' + MARKER


def shell_layout(ctx):
    data = json.loads(ctx.shell.read_text())
    try:
        layout = data['bar']['layout']
        if not isinstance(layout, dict) or not isinstance(layout.get('right'), list):
            raise ValueError()
    except (KeyError, TypeError, ValueError):
        raise ValueError('shell.json must contain bar.layout.right as an array.')
    return data, layout


def backup(ctx, path):
    folder = ctx.state / 'backups'
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, folder / (path.name + '.' + str(time.time_ns())))


def integrate(ctx):
    # Validate both files before changing either.
    data, layout = shell_layout(ctx)
    before = ctx.hypr.read_text()
    after = before if MARKER in before else before + ('' if before.endswith('\n') else '\n') + loader(ctx) + '\n'
    present = any(isinstance(e, dict) and e.get('id') == PLUGIN_ID
                  for section in layout.values() if isinstance(section, list) for e in section)
    if not present:
        layout['right'].append({'id': PLUGIN_ID})
    with transaction([ctx.hypr, ctx.shell]):
        if after != before:
            backup(ctx, ctx.hypr)
            atomic_write(ctx.hypr, after)
        if not present:
            backup(ctx, ctx.shell)
            atomic_write(ctx.shell, json.dumps(data, indent=2) + '\n')


def remove_integration(ctx):
    data, layout = shell_layout(ctx)
    before = ctx.hypr.read_text()
    cleaned = ''.join(line for line in before.splitlines(keepends=True)
                      if line.rstrip('\r\n') != loader(ctx))
    for key, section in layout.items():
        if isinstance(section, list):
            layout[key] = [e for e in section if not (isinstance(e, dict) and e.get('id') == PLUGIN_ID)]
    with transaction([ctx.hypr, ctx.shell]):
        backup(ctx, ctx.hypr)
        backup(ctx, ctx.shell)
        atomic_write(ctx.hypr, cleaned)
        atomic_write(ctx.shell, json.dumps(data, indent=2) + '\n')


def install(ctx):
    with locked(ctx):
        value = read_settings(ctx)
        # Install disabled; explicit Apply enables after the backend is ready.
        value['enabled'] = False
        try:
            with transaction([ctx.active, ctx.settings, ctx.hypr, ctx.shell]):
                atomic_write(ctx.active, render_lua(value, ctx))
                atomic_write(ctx.settings, json.dumps(value, indent=2) + '\n')
                integrate(ctx)
                reload_checked()
        except Exception:
            try:
                run(['hyprctl', 'reload'])
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                pass
            raise
    return value


def uninstall(ctx):
    with locked(ctx):
        try:
            with transaction([ctx.hypr, ctx.shell]):
                remove_integration(ctx)
                reload_checked()
        except Exception:
            try:
                run(['hyprctl', 'reload'])
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                pass
            raise


def preview():
    # Opens in the user's default terminal, so the effect shows on the app they use.
    terminal = shutil.which('xdg-terminal-exec')
    if not terminal:
        raise RuntimeError('The test window requires xdg-terminal-exec (included with Omarchy).')
    # No captured desktop image or close request to any existing window.
    subprocess.Popen([terminal, '--app-id=omarchy-winfx-preview', '-e', 'bash', '-c',
                      'printf "\\n  WinFX\\n\\n  Press any key to close this test window.\\n  This tests your APPLIED effect.\\n\\n"; read -r -n 1'],
                     start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def status(ctx):
    result = probe()
    result['settings'] = read_settings(ctx)
    result['installed'] = ctx.hypr.exists() and loader(ctx) in ctx.hypr.read_text()
    result['target'] = TARGET_HYPRLAND
    result['ready'] = result['version'] == TARGET_HYPRLAND and result['backend'] and result['installed']
    return result


def main():
    parser = argparse.ArgumentParser(description='WinFX settings and integration')
    parser.add_argument('command', choices=['status','apply','install','uninstall','preview'])
    parser.add_argument('settings', nargs='?', help='Complete JSON object for apply')
    args = parser.parse_args()
    ctx = Context()
    try:
        if args.command == 'status':
            result = status(ctx)
        elif args.command == 'apply':
            if not args.settings:
                raise ValueError('apply requires a JSON settings object.')
            if not ctx.hypr.exists() or loader(ctx) not in ctx.hypr.read_text():
                raise RuntimeError('Run install.sh before applying settings.')
            result = apply(ctx, json.loads(args.settings))
        elif args.command == 'install':
            result = install(ctx)
        elif args.command == 'uninstall':
            uninstall(ctx)
            result = {'removed': True}
        else:
            preview()
            result = {'preview': True}
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
