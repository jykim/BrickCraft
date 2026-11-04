"""Check compact report location and scene capture in a disposable real headless engine."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
(root/'tests/run').mkdir(parents=True, exist_ok=True)
test = Path(tempfile.mkdtemp(prefix='report-context-', dir=root/'tests/run'))
world, user = test/'world', test/'user'
mod = world/'worldmods/report_check'
mod.mkdir(parents=True)
(user/'games').mkdir(parents=True)
(user/'games/brickcraft').symlink_to(root/'game')
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(mod/'mod.conf').write_text('name = report_check\ndepends = brickcraft_ai\n')
shutil.copy2(root/'tests/report_capture.lua', mod/'init.lua')
conf = test/'server.conf'
conf.write_text((root/'server.conf').read_text()+'\nbrickcraft_integration_test = true\nbrickcraft_ai_llm = false\n')
log = test/'server.log'
r = subprocess.run([str(root/'runtime/luanti.app/Contents/MacOS/luanti'), '--server',
    '--config', str(conf), '--world', str(world), '--port', '30178', '--logfile', str(log)],
    env={**os.environ, 'LUANTI_USER_PATH': str(user)}, capture_output=True, text=True, timeout=30)
assert r.returncode == 0 and 'REPORT CAPTURE PASS' in log.read_text(), log.read_text()[-3000:]
print('PASS: world identity, fractional position, immutable location and bounded scene capture.')
print('Test artifacts:', test)
