"""jms, the AI builder, in a real Luanti GUI session on a dedicated test world.
  python3 tools/test_ai_builder.py           built-in blueprints only (no AI calls)
  python3 tools/test_ai_builder.py --claude  one real design from Claude Code via the Local AI API
Never edits the user's workshop.
"""
import os, subprocess, sys, time, tempfile
from pathlib import Path
live='--claude' in sys.argv
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='ai-',dir=testroot))
print('Test artifacts: '+str(test),flush=True)
world=test/'world'
world.mkdir()
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
user=test/'user'
(user/'games').mkdir(parents=True)
(user/'games'/'brickcraft').symlink_to(root/'game',target_is_directory=True)
config=test/'test.conf'
config.write_text((root/'brickcraft.conf').read_text()+'\nbrickcraft_ai_test = true\nbrickcraft_ai_builder = true\n'
    'brickcraft_ai_step = 0.03\nbrickcraft_ai_idle = 100000\nsecure.http_mods = brickcraft\n'
    f'brickcraft_ai_llm = {"true" if live else "false"}\nscreen_w = 1024\nscreen_h = 720\nwindow_maximized = false\n')
env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
log=test/'ai.log'
proc=subprocess.Popen([str(root/'runtime/luanti.app/Contents/MacOS/luanti'),'--go','--gameid','brickcraft',
    '--world',str(world),'--config',str(config),'--name','Builder','--port','30012','--logfile',str(log)],
    env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    deadline=time.time()+(900 if live else 600)
    while True:
        content=log.read_text() if log.exists() else ''
        if 'BRICKCRAFT AI PASS' in content:
            for line in content.splitlines():
                if '[ai]' in line or 'BRICKCRAFT AI' in line: print(line.split(': ',1)[1],flush=True)
            break
        if 'ServerError' in content or 'ModError' in content or 'timed out:' in content or proc.poll() is not None:
            raise RuntimeError(content[-3000:])
        if time.time()>deadline: raise RuntimeError('timed out: '+content[-3000:])
        time.sleep(.25)
finally:
    proc.terminate()
    try: proc.wait(timeout=8)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
print('PASS')
