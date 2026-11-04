"""Bunnyland colony balance: virtual players raise colonies against the same predators
and disasters (tests/mods/brickcraft_test/habitat_sim.lua). Server only, no client.
Usage: python3 tools/sim_habitat.py [minutes] [tune] [seed] [runs]
  tune: "wolf.speed=3.5 colony.birth=40 flood.duration=40" (quoted, space separated)
  runs: "none;chase;reasonable;strong"
A dedicated test world and port 30022; never touches the user's workshop.
"""
import os, subprocess, sys, time, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='hsim-',dir=testroot))
print('Test artifacts: '+str(test),flush=True)
exe=root/'runtime/luanti.app/Contents/MacOS/luanti'
minutes=sys.argv[1] if len(sys.argv)>1 else '12'
tune=sys.argv[2] if len(sys.argv)>2 else ''
seed=sys.argv[3] if len(sys.argv)>3 else '1'
runs=sys.argv[4] if len(sys.argv)>4 else 'none;chase;reasonable;strong'
port=sys.argv[5] if len(sys.argv)>5 else '30022'
world=test/'world'
world.mkdir()
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(world/'worldmods').mkdir()
(world/'worldmods'/'brickcraft_test').symlink_to(root/'tests'/'mods'/'brickcraft_test',target_is_directory=True)
user=test/'server'
(user/'games').mkdir(parents=True)
(user/'games'/'brickcraft').symlink_to(root/'game',target_is_directory=True)
env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
server_conf=test/'server.conf'
server_conf.write_text((root/'server.conf').read_text()+
    f'\nbrickcraft_habitat_sim = true\nbrickcraft_habitat_sim_minutes = {minutes}\nbrickcraft_habitat_sim_tune = {tune}\n'
    f'brickcraft_habitat_sim_seed = {seed}\nbrickcraft_habitat_sim_runs = {runs}\nmax_forceloaded_blocks = 4000\n')
log=test/'server.log'
proc=subprocess.Popen([str(exe),'--server','--config',str(server_conf),'--world',str(world),
    '--gameid','brickcraft','--port',port,'--logfile',str(log)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    deadline=time.time()+float(minutes)*60+240
    shown=0
    while True:
        content=log.read_text() if log.exists() else ''
        lines=[l for l in content.splitlines() if 'BRICKCRAFT HSIM' in l]
        for l in lines[shown:]: print(l.split('BRICKCRAFT HSIM ',1)[1],flush=True)
        shown=len(lines)
        if 'BRICKCRAFT HSIM PASS' in content: break
        if 'ServerError' in content or 'ModError' in content or proc.poll() is not None:
            raise RuntimeError(content[-3000:])
        if time.time()>deadline: raise RuntimeError('timed out')
        time.sleep(1)
finally:
    proc.terminate()
    try: proc.wait(timeout=8)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
