"""Two real Luanti GUI sessions; assert persisted map and player state after restart.
Uses a dedicated test world; never edits the user's workshop.
"""
import os, subprocess, time, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='session-',dir=testroot))
print('Test artifacts: '+str(test),flush=True)
world=test/'world'
world.mkdir(exist_ok=True)
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
user=test/'user'
(user/'games').mkdir(parents=True,exist_ok=True)
link=user/'games'/'brickcraft'
if not link.exists(): link.symlink_to(root/'game',target_is_directory=True)
config=test/'test.conf'
config.write_text((root/'brickcraft.conf').read_text()+'\nbrickcraft_integration_test = true\nport = 30009\nscreen_w = 1024\nscreen_h = 720\n')
env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
exe=root/'runtime/luanti.app/Contents/MacOS/luanti'
for phase in (1,2):
    log=test/f'phase{phase}.log'
    with (test/f'phase{phase}-stdout.log').open('w') as out:
        proc=subprocess.Popen([str(exe),'--go','--gameid','brickcraft','--world',str(world),'--config',str(config),'--name','TestBuilder','--logfile',str(log)],env=env,stdout=out,stderr=out)
        try:
            deadline=time.time()+40
            marker=f'BRICKCRAFT TEST PHASE {phase} PASS'
            while time.time()<deadline:
                content=log.read_text() if log.exists() else ''
                if marker in content:
                    time.sleep(3) # allow graceful server shutdown/SQLite flush
                    print(next(line for line in content.splitlines() if marker in line),flush=True)
                    break
                if 'ServerError' in content or 'ModError' in content or proc.poll() is not None:
                    raise RuntimeError(content)
                time.sleep(.25)
            else: raise RuntimeError(f'Phase {phase} timed out: '+content)
        finally:
            proc.terminate()
            try: proc.wait(timeout=8)
            except subprocess.TimeoutExpired: proc.kill();proc.wait()
print('PASS: both actual engine sessions completed. See tests/run/phase*.log')
