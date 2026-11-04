"""Check language coverage and launch arguments without downloading servers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'pi/.pi/agent/lsp.json').read_text())


class LspTests(unittest.TestCase):
    def test_language_coverage_and_plugin(self):
        settings = json.loads((ROOT / 'pi/.pi/agent/settings.json').read_text())
        self.assertIn('npm:pi-lsp', settings['packages'])
        self.assertEqual(CONFIG['version'], 1)
        servers = {server['id']: server for server in CONFIG['servers']}
        self.assertEqual(set(servers), {'gopls', 'basedpyright', 'clangd', 'yaml', 'json'})
        for server_id, extension, language in [
            ('gopls', '.go', 'go'), ('basedpyright', '.py', 'python'),
            ('basedpyright', '.pyi', 'python'), ('clangd', '.c', 'c'),
            ('clangd', '.cpp', 'cpp'), ('clangd', '.hpp', 'cpp'),
            ('yaml', '.yaml', 'yaml'), ('yaml', '.yml', 'yaml'),
            ('json', '.json', 'json'), ('json', '.jsonc', 'jsonc'),
        ]:
            server = servers[server_id]
            self.assertIn('**/*' + extension, server['include'])
            self.assertEqual(server['languageIdByExtension'][extension], language)

    @unittest.skipUnless(shutil.which('node'), 'Node required')
    def test_node_entry_points_keep_stdio_argument(self):
        with tempfile.TemporaryDirectory(prefix='lsp home ') as temp:
            home = Path(temp)
            modules = home / '.pi/agent/lsp-servers/node_modules'
            entries = {
                'basedpyright': 'basedpyright/langserver.index.js',
                'yaml': 'yaml-language-server/bin/yaml-language-server',
                'json': 'vscode-langservers-extracted/bin/vscode-json-language-server',
            }
            for server in CONFIG['servers']:
                if server['id'] not in entries:
                    continue
                entry = modules / entries[server['id']]
                entry.parent.mkdir(parents=True)
                if server['id'] == 'yaml':
                    # Match the real YAML entry point: ESM with top-level await.
                    (entry.parent.parent / 'package.json').write_text('{"type":"module"}')
                    prefix = 'await Promise.resolve();\n'
                else:
                    prefix = ''
                entry.write_text(prefix + 'console.log(JSON.stringify(process.argv.slice(2)));\n')
                env = dict(os.environ, HOME=temp, USERPROFILE=temp)
                result = subprocess.run([server['bin'], *server['args']], env=env,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), ['--stdio'])


if __name__ == '__main__':
    unittest.main()
