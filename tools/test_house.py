"""Build a small house with every piece in a real Luanti GUI session and keep the world.
Uses a dedicated test world; never edits the user's workshop.
"""
import os, subprocess, time, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='house-',dir=testroot))
world=test/'world'
world.mkdir()
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(world/'worldmods').mkdir()
(world/'worldmods'/'brickcraft_test').symlink_to(root/'tests'/'mods'/'brickcraft_test',target_is_directory=True)
user=test/'user'
(user/'games').mkdir(parents=True)
(user/'games'/'brickcraft').symlink_to(root/'game',target_is_directory=True)
config=test/'test.conf'
config.write_text((root/'brickcraft.conf').read_text()+'\nbrickcraft_house_test = true\nscreen_w = 1024\nscreen_h = 720\nwindow_maximized = false\n')
env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
log=test/'house.log'
proc=subprocess.Popen([str(root/'runtime/luanti.app/Contents/MacOS/luanti'),'--go','--gameid','brickcraft',
    '--world',str(world),'--config',str(config),'--name','Builder','--port','30011','--logfile',str(log)],
    env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    deadline=time.time()+60
    while True:
        content=log.read_text() if log.exists() else ''
        if 'BRICKCRAFT HOUSE PASS' in content:
            time.sleep(4) # graceful shutdown saves the house
            for line in content.splitlines():
                if 'BRICKCRAFT HOUSE' in line: print(line.split(': ',1)[1],flush=True)
            break
        if 'ServerError' in content or 'ModError' in content or proc.poll() is not None:
            raise RuntimeError(content[-3000:])
        if time.time()>deadline: raise RuntimeError('timed out: '+content[-3000:])
        time.sleep(.25)
finally:
    proc.terminate()
    try: proc.wait(timeout=8)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
print('PASS. Walk around the house with:')
print(f'  BRICKCRAFT_WORLD="{world}" ./"Launch BrickCraft.command"')
