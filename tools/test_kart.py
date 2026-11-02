"""The Kart Circuit world with a real Luanti GUI client on a dedicated server.
Uses a dedicated test world and port 30018; never touches the user's workshop.
"""
import os, subprocess, time, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
testroot=root/'tests'/'run'
testroot.mkdir(parents=True,exist_ok=True)
test=Path(tempfile.mkdtemp(prefix='kart-',dir=testroot))
print('Test artifacts: '+str(test),flush=True)
exe=root/'runtime/luanti.app/Contents/MacOS/luanti'
PORT="30018"
world=test/'world'
world.mkdir()
(world/'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(world/'worldmods').mkdir()
(world/'worldmods'/'brickcraft_test').symlink_to(root/'tests'/'mods'/'brickcraft_test',target_is_directory=True)
def user_dir(name):
    user=test/name
    (user/'games').mkdir(parents=True)
    (user/'games'/'brickcraft').symlink_to(root/'game',target_is_directory=True)
    env=os.environ.copy();env['LUANTI_USER_PATH']=str(user)
    return env
server_conf=test/'server.conf'
server_conf.write_text((root/'server.conf').read_text()+'\nbrickcraft_kart_test = true\n')
client_conf=(root/'brickcraft.conf').read_text()+'\nenable_register_confirmation = false\nscreen_w = 800\nscreen_h = 560\nwindow_maximized = false\n'
log=test/'server.log'
procs=[]
try:
    procs.append(subprocess.Popen([str(exe),'--server','--config',str(server_conf),'--world',str(world),
        '--gameid','brickcraft','--port',PORT,'--logfile',str(log)],env=user_dir('server'),
        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
    deadline=time.time()+20
    while 'listening on' not in (log.read_text() if log.exists() else ''):
        if time.time()>deadline or procs[0].poll() is not None: raise RuntimeError('server did not start')
        time.sleep(.25)
    for name in ('KartDad',):
        conf=test/f'{name}.conf'; conf.write_text(client_conf)
        procs.append(subprocess.Popen([str(exe),'--config',str(conf),'--address','127.0.0.1','--port',PORT,
            '--name',name,'--go','--logfile',str(test/f'{name}.log')],env=user_dir(name),
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
        time.sleep(2)
    deadline=time.time()+300
    while True:
        content=log.read_text()
        if 'BRICKCRAFT KART PASS' in content:
            for line in content.splitlines():
                if 'BRICKCRAFT KART' in line: print(line.split(': ',1)[1],flush=True)
            time.sleep(6) # leave the scene up for a look
            break
        if 'ServerError' in content or 'ModError' in content or procs[0].poll() is not None:
            raise RuntimeError(content[-3000:])
        if time.time()>deadline: raise RuntimeError('timed out: '+content[-3000:])
        time.sleep(.25)
finally:
    for p in procs:
        p.terminate()
    for p in procs:
        try: p.wait(timeout=8)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
print('PASS: the Kart Circuit races. Logs in '+str(test))
