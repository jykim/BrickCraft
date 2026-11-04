"""Prepare a <=200 KiB report screenshot and its Markdown; retries reuse the asset."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from render_report_view import render, MAX_IMAGE_BYTES


def prepare(queue, report_id, repo):
    link_file = queue / (report_id + '.image.md')
    if link_file.exists():
        return link_file.read_text()
    image = render(queue, report_id, queue / (report_id + '.jpg'))
    assert image.stat().st_size <= MAX_IMAGE_BYTES
    assert image.read_bytes().startswith(b'\xff\xd8'), 'Invalid JPEG'
    tag = 'report-screenshots'
    result = subprocess.run(['gh', 'release', 'view', tag, '-R', repo, '--json', 'assets'],
                            capture_output=True, text=True)
    if result.returncode:
        subprocess.run(['gh', 'release', 'create', tag, '-R', repo,
            '--title', 'Player report screenshots', '--notes',
            'Small reconstructed views from player-submitted bug and feature reports.',
            '--latest=false'], check=True, capture_output=True, text=True)
    filename = 'report-' + report_id + '.jpg'
    with tempfile.TemporaryDirectory(prefix='brickcraft-report-upload-') as tmp:
        asset = Path(tmp) / filename
        shutil.copyfile(image, asset)
        subprocess.run(['gh', 'release', 'upload', tag, str(asset), '-R', repo, '--clobber'],
                       check=True, capture_output=True, text=True)
    url = f'https://github.com/{repo}/releases/download/{tag}/{filename}'
    text = ('\n\n**Report screenshot — reconstructed view**\n\n'
            f'![Scene at the reported location]({url})\n\n'
            'Rendered from a small scene captured when the report was submitted. '
            'This is not a screenshot from the reporting device; distant terrain, '
            'imported assets, UI and animations may differ.\n')
    link_file.write_text(text)
    return text


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('queue', type=Path)
    parser.add_argument('report_id')
    parser.add_argument('repo')
    args = parser.parse_args()
    assert args.report_id and all(c.isalnum() or c == '-' for c in args.report_id)
    print(prepare(args.queue, args.report_id, args.repo), end='')
