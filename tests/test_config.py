import importlib.util
import json
import os
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('config', Path(__file__).parents[1] / 'lib/config.py')
c = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(c)

class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.ctx = c.Context(self.home, Path(__file__).parents[1])
        # Applying must never build the backend (clone, compile) from a test.
        patcher = patch.object(c, 'ensure_backend_build')
        self.ensure_build = patcher.start()
        self.addCleanup(patcher.stop)
        self.ctx.hypr.parent.mkdir(parents=True)
        self.ctx.hypr.write_text('-- user settings\n')
        self.ctx.shell.parent.mkdir(parents=True)
        self.original = {'bar': {'layout': {'left': [{'id':'keep.me'}], 'right': []}}, 'unrelated': 42}
        self.ctx.shell.write_text(json.dumps(self.original))

    def test_reload_ignores_blank_errors_but_rejects_real_errors(self):
        for errors in [[], [''], [' ', '\n'], ['', 'invalid rule']]:
            with self.subTest(errors=errors), patch.object(c, 'run', side_effect=['ok', json.dumps(errors)]):
                if 'invalid rule' in errors:
                    with self.assertRaisesRegex(RuntimeError, 'invalid rule'):
                        c.reload_checked()
                else:
                    c.reload_checked()

    def test_installer_preflight_ignores_blank_errors_but_rejects_real_errors(self):
        script = (self.ctx.plugin / 'install.sh').read_text().split("python3 - \"$SRC/lib\" <<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
        for errors in [[], [''], [' ', '\n'], ['', 'invalid rule']]:
            responses = [json.dumps({'tag': 'v0.56.2'}).encode(), json.dumps(errors).encode()]
            with self.subTest(errors=errors), patch('subprocess.check_output', side_effect=responses), \
                    patch.object(sys, 'argv', ['-', str(self.ctx.plugin / 'lib')]):
                if 'invalid rule' in errors:
                    with self.assertRaisesRegex(SystemExit, 'invalid rule'):
                        exec(script, {})
                else:
                    exec(script, {})

    def test_strict_validation(self):
        self.assertEqual(c.validate(c.DEFAULTS), c.DEFAULTS)
        for change in [{'duration':True}, {'duration':149}, {'duration':1501},
                       {'enabled':'yes'}, {'effect':'../other'}, {'size':'huge'}, {'extra':1}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                c.validate({**c.DEFAULTS, **change})

    def test_disabled_has_no_rule(self):
        self.assertNotIn('hl.window_rule', c.render_lua(c.DEFAULTS, self.ctx))
        value = {**c.DEFAULTS, 'enabled':True, 'effect':'default'}
        self.assertNotIn('hl.window_rule', c.render_lua(value, self.ctx))

    def test_enabled_uses_fallback_and_duration(self):
        value = {**c.DEFAULTS, 'enabled':True, 'duration':650}
        result = c.render_lua(value, self.ctx)
        self.assertIn('shader_close_default:', result)
        self.assertNotIn('@', result)
        self.assertIn('// @duration 0.650', c.shader_source(self.ctx, value))

    def test_each_direction_with_an_effect_gets_a_rule(self):
        for effect, open_effect, close, opened in [('crumble', 'default', True, False), ('default', 'crumble', False, True),
                                                   ('crumble', 'shatter', True, True), ('default', 'default', False, False)]:
            with self.subTest(effect=effect, open_effect=open_effect):
                result = c.render_lua({**c.DEFAULTS, 'enabled':True, 'effect':effect, 'openEffect':open_effect}, self.ctx)
                self.assertEqual('shader_close_default:' in result, close)
                self.assertEqual('shader_open_default:' in result, opened)
                self.assertEqual(result.count('hl.window_rule'), close + opened)

    def test_opening_plays_the_effect_in_reverse(self):
        for effect in [e for e in c.EFFECTS if e != 'default']:
            with self.subTest(effect=effect):
                value = {**c.DEFAULTS, 'effect':effect, 'openEffect':effect}
                closing = c.shader_source(self.ctx, value)
                opening = c.shader_source(self.ctx, value, opening=True)
                self.assertIn('clamp(progress,0.0,1.0)', closing)
                self.assertIn('clamp(1.0-progress,0.0,1.0)', opening)
                self.assertNotEqual(c.shader_path(self.ctx, value), c.shader_path(self.ctx, value, True))
                self.assertIn('// @duration 0.450', opening)

    def test_sync_mirrors_closing_onto_opening(self):
        value = c.validate({**c.DEFAULTS, 'effect':'shatter', 'duration':900, 'size':'large',
                            'openEffect':'dissolve', 'openDuration':200, 'openSize':'small', 'sync':True})
        self.assertEqual((value['openEffect'], value['openDuration'], value['openSize']), ('shatter', 900, 'large'))
        # Unsynced, opening keeps its own settings.
        solo = c.validate({**c.DEFAULTS, 'sync':False, 'openEffect':'dissolve'})
        self.assertEqual(solo['openEffect'], 'dissolve')

    def test_both_directions_apply_together_whatever_was_edited_last(self):
        value = {**c.DEFAULTS, 'enabled':True, 'effect':'shatter', 'openEffect':'build'}
        result = c.render_lua(value, self.ctx)
        self.assertIn('shader_close_default:', result)
        self.assertIn('shader_open_default:', result)

    def test_unsynced_directions_use_their_own_effect_duration_and_size(self):
        value = c.validate({**c.DEFAULTS, 'enabled':True, 'sync':False, 'effect':'crumble', 'duration':300,
                            'size':'small', 'openEffect':'pixelate', 'openDuration':800, 'openSize':'large'})
        closing = c.shader_source(self.ctx, value)
        opening = c.shader_source(self.ctx, value, opening=True)
        self.assertIn('// @duration 0.300', closing)
        self.assertIn('// @duration 0.800', opening)
        self.assertIn('#define CELLS 28.0', closing)
        self.assertIn('#define CELLS 11.0', opening)
        self.assertNotEqual(closing.replace('28.0', ''), opening.replace('11.0', ''))

    def test_a_default_side_gets_no_rule(self):
        value = {**c.DEFAULTS, 'enabled':True, 'sync':False, 'effect':'default', 'openEffect':'crumble'}
        result = c.render_lua(value, self.ctx)
        self.assertNotIn('shader_close_default', result)
        self.assertIn('shader_open_default', result)
        both_default = {**value, 'openEffect':'default'}
        self.assertNotIn('hl.window_rule', c.render_lua(both_default, self.ctx))

    def test_old_settings_file_makes_opening_follow_closing(self):
        self.ctx.state.mkdir(parents=True, exist_ok=True)
        self.ctx.settings.write_text(json.dumps({'enabled':True,'effect':'shatter','duration':700,'size':'large','when':'both'}))
        value = c.read_settings(self.ctx)
        self.assertTrue(value['sync'])
        self.assertEqual((value['openEffect'], value['openDuration'], value['openSize']), ('shatter', 700, 'large'))

    def test_old_when_choice_becomes_a_default_side(self):
        self.ctx.state.mkdir(parents=True, exist_ok=True)
        base = {'enabled':True,'effect':'shatter','duration':700,'size':'large','sync':False,
                'openEffect':'build','openDuration':500,'openSize':'small'}
        for when, effect, open_effect in [('close', 'shatter', 'default'), ('open', 'default', 'build'), ('both', 'shatter', 'build')]:
            with self.subTest(when=when):
                self.ctx.settings.write_text(json.dumps({**base, 'when':when}))
                value = c.read_settings(self.ctx)
                self.assertEqual((value['effect'], value['openEffect']), (effect, open_effect))
                self.assertNotIn('when', value)
        with self.assertRaises(ValueError):
            c.validate({**c.DEFAULTS, 'when': 'both'})

    def test_startup_loads_the_backend_through_the_helper_not_hyprpm(self):
        result = c.render_lua({**c.DEFAULTS, 'enabled':True}, self.ctx)
        self.assertNotIn('hyprpm', result)
        self.assertIn('omarchy-winfx', result.split('hyprland.start', 1)[1])
        self.assertIn(' load', result)

    def test_header_commit_is_read_from_version_h(self):
        headers = self.home / 'inc'
        (headers / 'src').mkdir(parents=True)
        (headers / 'src/version.h').write_text('#define GIT_COMMIT_HASH    "abc123def"\n#define X 1\n')
        self.assertEqual(c.header_commit(headers), 'abc123def')
        self.assertEqual(c.header_commit(self.home / 'missing'), '')

    def test_backend_is_fresh_only_for_the_pinned_source_and_the_running_commit(self):
        self.assertEqual(c.backend_state(self.ctx, 'run1'), {'built': False, 'fresh': False})
        self.ctx.backend.mkdir(parents=True)
        self.ctx.backend_so.write_text('so')
        self.ctx.backend_stamp.write_text(json.dumps({'source': c.BACKEND_COMMIT, 'hyprland': 'run1'}))
        self.assertEqual(c.backend_state(self.ctx, 'run1'), {'built': True, 'fresh': True})
        # A Hyprland update changes the running commit: the old build must not be trusted.
        self.assertEqual(c.backend_state(self.ctx, 'run2'), {'built': True, 'fresh': False})
        self.ctx.backend_stamp.write_text(json.dumps({'source': 'other', 'hyprland': 'run1'}))
        self.assertFalse(c.backend_state(self.ctx, 'run1')['fresh'])

    def test_a_stale_backend_is_never_loaded(self):
        self.ctx.backend.mkdir(parents=True)
        self.ctx.backend_so.write_text('so')
        self.ctx.backend_stamp.write_text(json.dumps({'source': c.BACKEND_COMMIT, 'hyprland': 'old'}))
        with patch.object(c, 'probe', return_value={'version': c.TARGET_HYPRLAND, 'commit': 'new', 'backend': False}), \
                patch.object(c, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'needs building'):
                c.backend_load(self.ctx)
        run.assert_not_called()

    def test_the_build_refuses_headers_that_do_not_match_the_running_compositor(self):
        with patch.object(c, 'probe', return_value={'version': c.TARGET_HYPRLAND, 'commit': 'running', 'backend': False}), \
                patch.object(c, 'header_commit', return_value='headers'), patch.object(c, 'build_run') as build:
            with self.assertRaisesRegex(RuntimeError, 'do not match the running compositor'):
                c.backend_build(self.ctx)
        build.assert_not_called()

    def test_the_pkg_config_file_points_at_the_system_headers(self):
        pc = c.PC_TEMPLATE.format(version='0.56.2')
        self.assertIn('prefix=/usr/include', pc)
        self.assertIn('Version: 0.56.2', pc)
        self.assertIn('-I${prefix}/hyprland/src', pc)

    def test_install_is_idempotent_preserves_unrelated(self):
        c.integrate(self.ctx)
        c.integrate(self.ctx)
        self.assertEqual(self.ctx.hypr.read_text().count(c.MARKER), 1)
        data = json.loads(self.ctx.shell.read_text())
        self.assertEqual(data['unrelated'], 42)
        self.assertEqual(data['bar']['layout']['left'], [{'id':'keep.me'}])
        self.assertEqual(data['bar']['layout']['right'], [{'id':c.PLUGIN_ID}])
        c.remove_integration(self.ctx)
        self.assertEqual(json.loads(self.ctx.shell.read_text()), self.original)
        self.assertEqual(self.ctx.hypr.read_text(), '-- user settings\n')

    def test_malformed_shell_does_not_modify_hypr(self):
        self.ctx.shell.write_text('{broken')
        with self.assertRaises(ValueError):
            c.integrate(self.ctx)
        self.assertEqual(self.ctx.hypr.read_text(), '-- user settings\n')

    def test_symlink_target_preserved(self):
        target = self.home / 'dotfile.lua'
        target.write_text(self.ctx.hypr.read_text())
        self.ctx.hypr.unlink()
        self.ctx.hypr.symlink_to(target)
        c.integrate(self.ctx)
        self.assertTrue(self.ctx.hypr.is_symlink())
        self.assertIn(c.MARKER, target.read_text())

    def test_failed_reload_rolls_back(self):
        self.ctx.state.mkdir(parents=True)
        self.ctx.settings.write_text(json.dumps(c.DEFAULTS))
        self.ctx.active.write_text('-- previous\n')
        previous = self.ctx.settings.read_bytes()
        with patch.object(c, 'require_backend'), patch.object(c, 'reload_checked', side_effect=RuntimeError('parse failed')):
            with self.assertRaises(RuntimeError):
                c.apply(self.ctx, {**c.DEFAULTS,'enabled':True})
        self.assertEqual(self.ctx.settings.read_bytes(), previous)
        self.assertEqual(self.ctx.active.read_text(), '-- previous\n')
        self.assertFalse(c.shader_path(self.ctx, {**c.DEFAULTS, 'enabled':True}).exists())

    def test_version_gate(self):
        for version in ['0.56.1','0.57.0','0.56.2-dev','']:
            with self.subTest(version=version), patch.object(c, 'probe', return_value={'version':version,'backend':True}):
                with self.assertRaises(RuntimeError):
                    c.require_backend()
        with patch.object(c, 'probe', return_value={'version':'0.56.2','backend':False}):
            with self.assertRaises(RuntimeError):
                c.require_backend()


    def test_failed_install_restores_and_reloads_original_config(self):
        before = self.ctx.shell.read_bytes()
        with patch.object(c, 'reload_checked', side_effect=RuntimeError('bad config')), patch.object(c, 'run', return_value='ok') as run:
            with self.assertRaises(RuntimeError):
                c.install(self.ctx)
            run.assert_called_once_with(['hyprctl', 'reload'])
        self.assertEqual(self.ctx.shell.read_bytes(), before)
        self.assertEqual(self.ctx.hypr.read_text(), '-- user settings\n')
        self.assertFalse(self.ctx.active.exists())

    def test_tags_stay_constant_while_shader_contents_change(self):
        # A changing tag would pile stale tags onto windows that are already open.
        small = {**c.DEFAULTS, 'enabled':True, 'size':'small', 'duration':300}
        large = {**c.DEFAULTS, 'enabled':True, 'size':'large', 'duration':900}
        self.assertEqual(c.render_lua(small, self.ctx), c.render_lua(large, self.ctx))
        self.assertNotEqual(c.shader_source(self.ctx, small), c.shader_source(self.ctx, large))

    def test_cli_install_apply_disable_remove(self):
        import subprocess
        fake = self.home / 'bin'
        fake.mkdir()
        exe = fake / 'hyprctl'
        exe.write_text("#!/usr/bin/env python3\nimport json,sys,os\nargs=sys.argv[1:]\nif args == ['-j','version']: print(json.dumps({'tag':'v0.56.2'}))\nelif args == ['-j','plugin','list']: print(json.dumps([{'name':'HyprWindowShade'}]))\nelif args == ['-j','configerrors']: print('[]')\nelif args == ['reload']: print('ok')\nelse: sys.exit(2)\n")
        exe.chmod(0o755)
        env = {**os.environ, 'HOME':str(self.home), 'PATH':str(fake)+os.pathsep+os.environ['PATH']}
        helper = self.ctx.plugin / 'bin/omarchy-winfx'
        def cli(*args):
            result = subprocess.run([str(helper), *args], text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        cli('install')
        cli('install')
        self.assertTrue(cli('status')['ready'])
        active = {**c.DEFAULTS, 'enabled':True, 'effect':'shatter'}
        cli('apply',json.dumps(active))
        self.assertEqual(cli('status')['settings'],c.validate(active))
        self.assertIn('shader_close_default:',self.ctx.active.read_text())
        cli('apply',json.dumps(c.DEFAULTS))
        self.assertNotIn('hl.window_rule',self.ctx.active.read_text())
        cli('uninstall')
        self.assertEqual(self.ctx.hypr.read_text(),'-- user settings\n')
        self.assertEqual(json.loads(self.ctx.shell.read_text()),self.original)

    def test_uninstall_preserves_other_dofile_lines(self):
        self.ctx.hypr.write_text('-- user settings\ndofile("other.lua") -- user loader\n')
        original=self.ctx.hypr.read_text()
        c.integrate(self.ctx)
        c.remove_integration(self.ctx)
        self.assertEqual(self.ctx.hypr.read_text(),original)

if __name__ == '__main__':
    unittest.main()
