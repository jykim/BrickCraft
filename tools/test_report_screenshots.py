"""Test screenshot upload/retry and report posting without contacting GitHub."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from prepare_report_screenshot import prepare

ROOT = Path(__file__).resolve().parents[1]


class ReportScreenshotTests(unittest.TestCase):
    def test_upload_post_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            queue = tmp / 'world/issues'
            queue.mkdir(parents=True)
            mocks = tmp / 'bin'
            mocks.mkdir()
            calls = tmp / 'calls'
            issue_body = tmp / 'issue-body'
            gh = mocks / 'gh'
            gh.write_text('''#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['REPORT_TEST_CALLS'],'a') as f:f.write(json.dumps(args)+'\\n')
if args[:2]==['release','view']: print('{"assets":[]}')
elif args[:2]==['issue','create']:
 Path(os.environ['REPORT_TEST_BODY']).write_text(Path(args[args.index('--body-file')+1]).read_text())
 print('https://example.test/issues/1')
''')
            gh.chmod(0o755)
            report_id = '20261104-123456-1234'
            (queue / (report_id + '.jpg')).write_bytes(b'\xff\xd8test image\xff\xd9')
            (queue / (report_id + '.view.json')).write_text('{}')
            (queue / (report_id + '.view.mts')).write_bytes(b'test scene')
            (queue / (report_id + '.title')).write_text('Test report')
            (queue / (report_id + '.label')).write_text('bug')
            (queue / (report_id + '.md')).write_text('World pointer: Workshop #0 at 1,2,3')
            changes = {'PATH': str(mocks)+os.pathsep+os.environ['PATH'],
                       'REPORT_TEST_CALLS': str(calls), 'REPORT_TEST_BODY': str(issue_body)}
            old = {k: os.environ.get(k) for k in changes}
            os.environ.update(changes)
            try:
                first = prepare(queue, report_id, 'jykim/BrickCraft')
                self.assertIn('reconstructed', first)
                self.assertIn('report-'+report_id+'.jpg', first)
                before = calls.read_text()
                self.assertEqual(prepare(queue, report_id, 'jykim/BrickCraft'), first)
                self.assertEqual(calls.read_text(), before, 'retry reuses uploaded image')
                subprocess.run(['zsh', '-f', str(ROOT/'tools/post_issues.zsh'), str(tmp/'world')],
                               check=True, capture_output=True, text=True, timeout=15)
            finally:
                for k, value in old.items():
                    if value is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = value
            body = issue_body.read_text()
            self.assertIn('World pointer: Workshop #0 at 1,2,3', body)
            self.assertIn('![Scene at the reported location]', body)
            commands = [json.loads(line) for line in calls.read_text().splitlines()]
            created = next(c for c in commands if c[:2] == ['issue', 'create'])
            self.assertIn('player-report', created)
            self.assertEqual(sum(c[:2] == ['release', 'upload'] for c in commands), 1)
            self.assertFalse(list(queue.glob('*.title')))
            self.assertFalse(list(queue.glob('*.view.*')), 'temporary scene removed after posting')
            self.assertTrue((queue/'sent'/ (report_id+'.jpg')).exists())


if __name__ == '__main__':
    unittest.main()
