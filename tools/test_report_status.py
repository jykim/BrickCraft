"""Check GitHub-to-game lifecycle transitions without GitHub writes."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from sync_report_status import sync


class StatusTests(unittest.TestCase):
    def test_work_review_merge_and_deduplication(self):
        with tempfile.TemporaryDirectory() as tmp:
            world = Path(tmp)
            sent = world/'issues/sent'
            sent.mkdir(parents=True)
            (sent/'report1.url').write_text('https://github.com/jykim/BrickCraft/issues/7')
            def issue(state='OPEN', labels=(), comments=()):
                return {'state': state, 'labels': [{'name': s} for s in labels],
                        'comments': [{'body': s} for s in comments]}
            with patch('sync_report_status.gh_json', return_value=issue(labels=['claude-working'])):
                self.assertEqual(sync(world, 'jykim/BrickCraft'), 1)
                self.assertEqual(sync(world, 'jykim/BrickCraft'), 0)
            comments = ['Claude prepared https://github.com/jykim/BrickCraft/pull/8 for review.']
            with patch('sync_report_status.gh_json', side_effect=[issue(comments=comments), {'state': 'OPEN'}]):
                self.assertEqual(sync(world, 'jykim/BrickCraft'), 1)
            with patch('sync_report_status.gh_json', side_effect=[issue('CLOSED', comments=comments), {'state': 'MERGED'}]):
                self.assertEqual(sync(world, 'jykim/BrickCraft'), 1)
            data = json.loads((sent/'report1.status.json').read_text())
            self.assertEqual([e['state'] for e in data['events']], ['working', 'review', 'merged'])
            with patch('sync_report_status.gh_json') as api:
                self.assertEqual(sync(world, 'jykim/BrickCraft'), 0)
                api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
