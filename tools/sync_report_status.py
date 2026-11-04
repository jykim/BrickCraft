"""Sync GitHub report lifecycle to small local sidecars for in-game acknowledgments."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess


def gh_json(*args):
    return json.loads(subprocess.run(['gh', *args], check=True, text=True,
                                    capture_output=True, timeout=30).stdout)


def sync(world, repo):
    sent = world/'issues/sent'
    updates = 0
    for pointer in sorted(sent.glob('*.url')):
        url = pointer.read_text().strip()
        match = re.fullmatch(r'https://github\.com/'+re.escape(repo)+r'/issues/(\d+)', url)
        if not match:
            continue
        status_path = pointer.with_suffix('.status.json')
        status = json.loads(status_path.read_text()) if status_path.exists() else {'events': []}
        if status['events'] and status['events'][-1]['state'] in ('merged', 'closed'):
            continue
        issue = gh_json('issue', 'view', match[1], '-R', repo, '--json', 'state,labels,comments')
        labels = {label['name'] for label in issue['labels']}
        comments = [c['body'] for c in issue['comments']]
        pr_urls = re.findall(r'https://github\.com/'+re.escape(repo)+r'/pull/\d+', '\n'.join(comments))
        target_url = url
        if 'claude-working' in labels:
            state = 'working'
        elif pr_urls:
            target_url = pr_urls[-1]
            pr = gh_json('pr', 'view', target_url, '--json', 'state')
            state = 'merged' if pr['state'] == 'MERGED' else 'closed' if pr['state'] == 'CLOSED' else 'review'
        elif 'auto-merged' in labels:
            state = 'merged'
        elif issue['state'] == 'CLOSED':
            state = 'closed'
        elif 'needs-review' in labels:
            state = 'needs_details'
        elif comments and 'could not finish this attempt' in comments[-1]:
            state = 'failed'
        else:
            state = 'posted'
        event = {'state': state, 'url': target_url}
        if any(e['state'] == state and e['url'] == target_url for e in status['events']):
            continue
        if state in ('review', 'merged', 'failed', 'needs_details') and not any(
                e['state'] == 'working' for e in status['events']):
            status['events'].append({'state': 'working', 'url': url,
                                     'at': datetime.now(timezone.utc).isoformat()})
        event['at'] = datetime.now(timezone.utc).isoformat()
        status['events'].append(event)
        temp = status_path.with_suffix('.tmp')
        temp.write_text(json.dumps(status, separators=(',', ':')))
        temp.replace(status_path)
        print(pointer.stem+': '+state+' '+target_url)
        updates += 1
    return updates


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('world', type=Path)
    parser.add_argument('--repo', default='jykim/BrickCraft')
    args = parser.parse_args()
    sync(args.world, args.repo)
