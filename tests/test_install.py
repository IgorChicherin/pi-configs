"""Exercise the real Stow installer without touching the user's home or network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('stow') and shutil.which('bash'), 'Bash and Stow required')
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home with spaces'
        self.home.mkdir()
        bin_dir = self.base / 'bin'
        bin_dir.mkdir()
        pi = bin_dir / 'pi'
        pi.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/pi-calls"\nexit "${FAKE_PI_EXIT:-0}"\n')
        pi.chmod(0o755)
        npm = bin_dir / 'npm'
        npm.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$HOME/lsp-args"\nexit "${FAKE_NPM_EXIT:-0}"\n')
        npm.chmod(0o755)
        npx = bin_dir / 'npx'
        npx.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$HOME/skills-args"\nexit "${FAKE_NPX_EXIT:-0}"\n')
        npx.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{bin_dir}:{os.environ["PATH"]}')
        self.env.pop('PI_CODING_AGENT_DIR', None)

    def install(self):
        return subprocess.run(['bash', str(ROOT / 'install.sh')], env=self.env,
                              capture_output=True, text=True)

    def test_links_only_configs_and_installs_plugins(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        agent = self.home / '.pi/agent'
        self.assertFalse((self.home / '.pi').is_symlink())
        self.assertFalse(agent.is_symlink())
        for source in (ROOT / 'pi/.pi/agent').iterdir():
            self.assertTrue((agent / source.name).is_symlink())
            self.assertEqual((agent / source.name).resolve(), source.resolve())
        self.assertEqual((self.home / 'pi-calls').read_text(), 'update --extensions\n')
        self.assertEqual((self.home / 'lsp-args').read_text().splitlines(), [
            'install', '--prefix', str(agent / 'lsp-servers'), '--no-save',
            '--package-lock=false', '--ignore-scripts', 'basedpyright',
            'yaml-language-server', 'vscode-langservers-extracted',
        ])
        self.assertTrue((agent / 'lsp.json').is_symlink())
        self.assertEqual((self.home / 'skills-args').read_text().splitlines(), [
            '--yes', 'skills', 'add', 'mattpocock/skills', '--global',
            '--agent', 'pi', '--skill', '*', '--yes',
            '--yes', 'skills', 'add', 'evgenyigumnov/subtask4llm', '--global',
            '--agent', 'pi', '--skill', '*', '--yes',
        ])
        (agent / 'runtime-check').write_text('local')
        self.assertFalse((ROOT / 'pi/.pi/agent/runtime-check').exists())

    def test_conflict_preserves_existing_config_before_installing(self):
        agent = self.home / '.pi/agent'
        agent.mkdir(parents=True)
        config = agent / 'settings.json'
        config.write_text('{"keep":true}')
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(config.read_text()), {'keep': True})
        self.assertEqual(list(agent.iterdir()), [config])
        self.assertFalse((self.home / 'pi-calls').exists())
        self.assertFalse((self.home / 'skills-args').exists())

    def test_plugin_failure_is_reported_and_configs_remain(self):
        self.env['FAKE_PI_EXIT'] = '7'
        result = self.install()
        self.assertEqual(result.returncode, 7)
        self.assertTrue((self.home / '.pi/agent/settings.json').is_symlink())
        self.assertFalse((self.home / 'skills-args').exists())

    def test_lsp_failure_is_reported_and_configs_remain(self):
        self.env['FAKE_NPM_EXIT'] = '9'
        result = self.install()
        self.assertEqual(result.returncode, 9)
        self.assertTrue((self.home / '.pi/agent/lsp.json').is_symlink())
        self.assertFalse((self.home / 'skills-args').exists())

    def test_skill_failure_is_reported_and_configs_remain(self):
        self.env['FAKE_NPX_EXIT'] = '8'
        result = self.install()
        self.assertEqual(result.returncode, 8)
        self.assertTrue((self.home / '.pi/agent/settings.json').is_symlink())

    def test_custom_config_directory_is_rejected(self):
        self.env['PI_CODING_AGENT_DIR'] = str(self.base / 'other')
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / '.pi').exists())


if __name__ == '__main__':
    unittest.main()
