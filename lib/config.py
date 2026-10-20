"""Validated settings and reversible Omarchy integration. Standard library only."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

PLUGIN_ID = 'videinfra.omarchy-effects'
MARKER = '-- omarchy-effects managed loader'
DEFAULTS = {'enabled': False, 'effect': 'crumble', 'duration': 450, 'size': 'medium'}
EFFECTS = ('crumble', 'shatter', 'dissolve', 'pixelate', 'default')
SIZES = {'small': 28, 'medium': 18, 'large': 11}

class Context:
    def __init__(self, home=None, plugin=None):
        self.home = Path(home) if home is not None else Path.home()
        self.plugin = Path(plugin) if plugin is not None else Path(__file__).resolve().parents[1]
        self.state = self.home / '.config/omarchy-effects'
        self.settings = self.state / 'settings.json'
        self.active = self.state / 'active.lua'
        self.hypr = self.home / '.config/hypr/hyprland.lua'
        self.shell = self.home / '.config/omarchy/shell.json'


def validate(value):
    if not isinstance(value, dict) or set(value) != set(DEFAULTS):
        raise ValueError('Settings require exactly enabled, effect, duration and size.')
    if type(value['enabled']) is not bool:
        raise ValueError('enabled must be true or false.')
    if value['effect'] not in EFFECTS:
        raise ValueError('Unknown effect.')
    if type(value['duration']) is not int or not 150 <= value['duration'] <= 1500:
        raise ValueError('Duration must be an integer from 150 to 1500 milliseconds.')
    if not isinstance(value['size'], str) or value['size'] not in SIZES:
        raise ValueError('Fragment size must be small, medium or large.')
    return dict(value)


def read_settings(ctx):
    return validate(json.loads(ctx.settings.read_text())) if ctx.settings.exists() else dict(DEFAULTS)


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
    if data['version'] != '0.56.2':
        raise RuntimeError('Requires running Hyprland 0.56.2; detected ' + (data['version'] or 'no compositor') + '.')
    if not data['backend']:
        raise RuntimeError('HyprWindowShade is not loaded. Run install.sh --backend, then reopen this panel.')


def lua_string(value):
    # ASCII JSON strings are valid Lua for these paths, except \u escapes.
    # Reject control characters rather than emitting ambiguous config.
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in value):
        raise ValueError('Paths containing control characters are not supported.')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def shader_source(ctx, value):
    source = (ctx.plugin / 'shaders' / (value['effect'] + '.glsl')).read_text()
    return source.replace('#define CELLS 18.0', f"#define CELLS {SIZES[value['size']]}.0")


def shader_path(ctx, value):
    digest = hashlib.sha256(shader_source(ctx, value).encode()).hexdigest()[:16]
    return ctx.state / 'shaders' / (value['effect'] + '-' + digest + '.glsl')


def render_lua(value, ctx):
    lines = ['-- Generated by omarchy-effects. Change settings through the panel.']
    if value['enabled'] and value['effect'] != 'default':
        # The backend's path@duration protocol reserves @ and tag parsing uses whitespace.
        path = str(shader_path(ctx, value))
        if '@' in path or any(ch.isspace() for ch in path):
            raise ValueError('The shader backend requires a home path without whitespace or @.')
        shader = lua_string(path + f"@{value['duration'] / 1000:.3f}")
        lines += ['hl.on("hyprland.start", function()',
                  '    hl.exec_cmd("hyprpm reload -n")', 'end)',
                  'hl.window_rule({', '    name = "omarchy-effects-close",',
                  '    match = { class = ".*" },',
                  '    tag = "+shader_close_default:" .. ' + shader + ',', '})']
    return '\n'.join(lines) + '\n'


def reload_checked():
    run(['hyprctl', 'reload'])
    errors = json.loads(run(['hyprctl', '-j', 'configerrors']))
    errors = [error for error in errors if error.strip()]
    if errors:
        raise RuntimeError('Hyprland configuration error: ' + str(errors))


def apply(ctx, value):
    value = validate(value)
    active = value['enabled'] and value['effect'] != 'default'
    if active:
        require_backend()
    lua = render_lua(value, ctx)
    shader = shader_source(ctx, value) if active else None
    target = shader_path(ctx, value) if active else None
    with locked(ctx):
        try:
            with transaction([ctx.active, ctx.settings] + ([target] if target else [])):
                if shader is not None:
                    atomic_write(target, shader)
                atomic_write(ctx.active, lua)
                reload_checked()
                atomic_write(ctx.settings, json.dumps(value, indent=2) + '\n')
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
    if not shutil.which('foot'):
        raise RuntimeError('The test window requires foot (included with Omarchy).')
    # No captured desktop image or close request to any existing window.
    subprocess.Popen(['foot', '--app-id=omarchy-effects-preview', '--title=omarchy-effects test window',
                      'bash', '-c', 'printf "\\n  omarchy-effects\\n\\n  Press any key to close this test window.\\n  This tests your APPLIED effect.\\n\\n"; read -r -n 1'],
                     start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def status(ctx):
    result = probe()
    result['settings'] = read_settings(ctx)
    result['installed'] = ctx.hypr.exists() and loader(ctx) in ctx.hypr.read_text()
    result['ready'] = result['version'] == '0.56.2' and result['backend'] and result['installed']
    return result


def main():
    parser = argparse.ArgumentParser(description='omarchy-effects settings and integration')
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
