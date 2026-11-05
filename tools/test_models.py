"""Display models (tests/mods/brickcraft_test/models_test.lua) in a real Luanti GUI session:
the BrickWright samples stand life-size in a strict LEGO world, and a screenshot of the row
is saved to the test folder. Uses a dedicated test world; never edits the user's workshop.
"""
import json, os, subprocess, time, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='models-',dir=testroot))
world=test/'world'
world.mkdir()
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(world/'worldmods').mkdir()
(world/'worldmods'/'brickcraft_test').symlink_to(root/'tests'/'mods'/'brickcraft_test',target_is_directory=True)
user=test/'user'
(user/'games').mkdir(parents=True)
(user/'games'/'brickcraft').symlink_to(root/'game',target_is_directory=True)
config=test/'test.conf'
config.write_text((root/'brickcraft.conf').read_text()+'\nbrickcraft_models_test = true\nscreen_w = 1024\nscreen_h = 720\nwindow_maximized = false\n')
env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
log=test/'models.log'
shot=test/'models.png'
proc=subprocess.Popen([str(root/'runtime/luanti.app/Contents/MacOS/luanti'),'--go','--gameid','brickcraft',
    '--world',str(world),'--config',str(config),'--name','Builder','--port','30019','--logfile',str(log)],
    env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    deadline=time.time()+120
    sent=False
    while True:
        content=log.read_text() if log.exists() else ''
        if 'BRICKCRAFT MODELS SEND' in content and not sent:
            sent=True  # "Send to BrickCraft": into this world's inbox while the game runs
            out=subprocess.run(['python3',str(root/'tools'/'import_brickwright.py'),'--send','20261103-113209-e66a90db',
                '--title','Chick','--world',str(world)],capture_output=True,text=True)
            print('sent: '+(out.stdout.strip() or out.stderr.strip()),flush=True)
            # The same version again isn't converted again, and --status says it's there.
            tool=['python3',str(root/'tools'/'import_brickwright.py')]
            again=json.loads(subprocess.run(tool+['--send','20261103-113209-e66a90db','--world',str(world)],
                capture_output=True,text=True,check=True).stdout)
            assert again['already'] and again['slug']==json.loads(out.stdout)['slug'],again
            state=json.loads(subprocess.run(tool+['--status','20261103-113209-e66a90db','--world',str(world)],
                capture_output=True,text=True,check=True).stdout)
            assert state['sent'] and state['current'] and state['title']=='Chick',state
            print('sent again: same version, not converted again',flush=True)
        if 'BRICKCRAFT MODELS READY' in content and not shot.exists():
            time.sleep(4) # meshes load and the view settles
            # Luanti's own screenshot key (F12, key code 111), sent to the client; it saves
            # into the test's user folder. Needs System Events access, else no picture.
            subprocess.run(['osascript','-e','tell application "System Events" to set frontmost of '
                f'(first process whose unix id is {proc.pid}) to true','-e','delay 0.5','-e',
                'tell application "System Events" to key code 53','-e','delay 0.5','-e',
                'tell application "System Events" to key code 111'],check=False)
            time.sleep(1.5)
            pics=sorted((user/'screenshots').glob('*.png')) if (user/'screenshots').exists() else []
            if pics: pics[-1].rename(shot)
            else: shot.write_text('')
        if 'BRICKCRAFT MODELS PASS' in content:
            time.sleep(2)
            for line in content.splitlines():
                if 'BRICKCRAFT MODELS' in line: print(line.split(': ',1)[1],flush=True)
            break
        if 'ServerError' in content or 'ModError' in content or proc.poll() is not None:
            raise RuntimeError(content[-3000:])
        if time.time()>deadline: raise RuntimeError('timed out: '+content[-3000:])
        time.sleep(.25)
finally:
    proc.terminate()
    try: proc.wait(timeout=8)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
print('PASS. Screenshot: '+str(shot))
print('Walk around the gallery world with:')
print(f'  BRICKCRAFT_WORLD="{world}" ./"Launch BrickCraft.command"')
