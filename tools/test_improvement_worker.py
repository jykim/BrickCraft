"""Exercise the real worker with local Git and fake GitHub/Claude; no external writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


class ImprovementTests(unittest.TestCase):
    def test_merge_gate(self):
        for passed, protected, gameplay in ((False, False, False), (True, False, False),
                                           (True, True, False), (True, False, True)):
            with self.subTest(passed=passed, protected=protected, gameplay=gameplay), tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                repo, bare, mocks = tmp / 'repo', tmp / 'origin.git', tmp / 'bin'
                repo.mkdir()
                mocks.mkdir()
                (repo / 'tools').mkdir()
                shutil.copy(ROOT / 'tools/improve_issues.zsh', repo / 'tools')
                (repo / 'README.md').write_text('Original\n')
                (repo / '.gitignore').write_text('runtime/\n')
                (repo / 'runtime/luanti.app').mkdir(parents=True)
                (repo / 'tools/example').write_text('Original\n')
                (repo / 'game/mods/brickcraft').mkdir(parents=True)
                (repo / 'game/mods/brickcraft/init.lua').write_text('-- Original\n')
                (repo / 'tools/test_integration.py').write_text('raise SystemExit(1)\n')
                run('git', 'init', '--bare', str(bare))
                run('git', 'init', '-b', 'main', str(repo))
                for key, value in (('user.name', 'Test'), ('user.email', 'test@example.test')):
                    run('git', '-C', str(repo), 'config', key, value)
                run('git', '-C', str(repo), 'add', '.')
                run('git', '-C', str(repo), 'commit', '-m', 'Fixture')
                run('git', '-C', str(repo), 'remote', 'add', 'origin', str(bare))
                run('git', '-C', str(repo), 'push', '-u', 'origin', 'main')
                (mocks / 'gh').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['MOCK_CALLS'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[:2] == ['repo', 'view']:
    print('main')
elif args[:2] == ['issue', 'list']:
    print(json.dumps({'number': 1, 'title': 'Fixture report', 'url': 'https://example.test/issues/1'}))
elif args[:2] == ['issue', 'view']:
    print('{}')
elif args[:2] == ['pr', 'create']:
    print('https://example.test/pull/1')
''')
                (mocks / 'claude').write_text('''#!/usr/bin/env python3
import json, os
from pathlib import Path
assert Path('runtime/luanti.app').is_dir()
Path('README.md').write_text('Fixed typo\\n')
if os.environ['MOCK_GAMEPLAY'] == '1':
    Path('game/mods/brickcraft/init.lua').write_text('-- Changed gameplay\\n')
if os.environ['MOCK_PROTECTED'] == '1':
    Path('tools/example').write_text('Changed tool\\n')
print(json.dumps({'structured_output': {'decision': 'trivial', 'summary': 'Fix typo',
    'tests_passed': os.environ['MOCK_PASSED'] == '1', 'tests': [], 'risk': 'low'}}))
''')
                for script in mocks.iterdir():
                    script.chmod(0o755)
                calls = tmp / 'calls.jsonl'
                env = {**os.environ, 'PATH': str(mocks) + os.pathsep + os.environ['PATH'],
                       'MOCK_CALLS': str(calls), 'MOCK_PASSED': str(int(passed)),
                       'MOCK_PROTECTED': str(int(protected)), 'MOCK_GAMEPLAY': str(int(gameplay))}
                world = tmp / 'world'
                world.mkdir()
                result = run('zsh', '-f', str(repo / 'tools/improve_issues.zsh'), str(world), env=env, timeout=20)
                commands = [json.loads(line) for line in calls.read_text().splitlines()]
                merged = any(c[:2] == ['pr', 'merge'] for c in commands)
                self.assertEqual(merged, passed and not protected and not gameplay, (result.stdout, result.stderr, commands))
                self.assertEqual((world / 'issues/restart-request').exists(), merged)
                if not merged:
                    self.assertTrue(any(c[:2] == ['pr', 'edit'] and 'needs-review' in c for c in commands), (result.stdout, result.stderr, commands))
                self.assertEqual(run('git', '-C', str(repo), 'status', '--porcelain').stdout, '')

    def test_idle_heartbeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            status = Path(tmp) / 'status.json'
            now = int(time.time())
            for data, accepted in (
                ({'running': True, 'players': 0, 'updated': now}, True),
                ({'running': True, 'players': 1, 'updated': now}, False),
                ({'running': True, 'players': 0, 'updated': now - 60}, False),
                ({'running': False, 'players': 0, 'updated': now}, False),
                ({'running': True, 'players': 0, 'updated': now + 60}, False),
                ({'running': True, 'players': 0}, False),
                ({'running': True, 'players': 0, 'updated': 'invalid'}, False),
            ):
                with self.subTest(data=data):
                    status.write_text(json.dumps(data))
                    result = subprocess.run(['zsh', '-f', '-c', 'source "$1"; idle_heartbeat "$2"',
                                             'test', str(ROOT / 'tools/server_idle.zsh'), str(status)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, accepted)
            status.write_text('{broken')
            result = subprocess.run(['zsh', '-f', '-c', 'source "$1"; idle_heartbeat "$2"',
                                     'test', str(ROOT / 'tools/server_idle.zsh'), str(status)],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
