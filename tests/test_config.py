import importlib.util
import json
import os
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
        script = (self.ctx.plugin / 'install.sh').read_text().split("python3 - <<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
        for errors in [[], [''], [' ', '\n'], ['', 'invalid rule']]:
            responses = [json.dumps({'tag': 'v0.56.2'}).encode(), json.dumps(errors).encode()]
            with self.subTest(errors=errors), patch('subprocess.check_output', side_effect=responses):
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
        self.assertIn('@0.650', result)

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

    def test_different_shader_contents_use_different_cache_paths(self):
        small = c.render_lua({**c.DEFAULTS, 'enabled':True, 'size':'small'}, self.ctx)
        large = c.render_lua({**c.DEFAULTS, 'enabled':True, 'size':'large'}, self.ctx)
        self.assertNotEqual(small, large)

    def test_cli_install_apply_disable_remove(self):
        import subprocess
        fake = self.home / 'bin'
        fake.mkdir()
        exe = fake / 'hyprctl'
        exe.write_text("#!/usr/bin/env python3\nimport json,sys,os\nargs=sys.argv[1:]\nif args == ['-j','version']: print(json.dumps({'tag':'v0.56.2'}))\nelif args == ['-j','plugin','list']: print(json.dumps([{'name':'HyprWindowShade'}]))\nelif args == ['-j','configerrors']: print('[]')\nelif args == ['reload']: print('ok')\nelse: sys.exit(2)\n")
        exe.chmod(0o755)
        env = {**os.environ, 'HOME':str(self.home), 'PATH':str(fake)+os.pathsep+os.environ['PATH']}
        helper = self.ctx.plugin / 'bin/omarchy-effects'
        def cli(*args):
            result = subprocess.run([str(helper), *args], text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        cli('install')
        cli('install')
        self.assertTrue(cli('status')['ready'])
        active = {**c.DEFAULTS, 'enabled':True, 'effect':'shatter'}
        cli('apply',json.dumps(active))
        self.assertEqual(cli('status')['settings'],active)
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
