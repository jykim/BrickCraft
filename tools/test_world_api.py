"""End-to-end HTTP and real Luanti engine checks in a disposable world."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
import urllib.error

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('world_api', root / 'tools/world_api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
testroot = root / 'tests/run'
testroot.mkdir(parents=True, exist_ok=True)
test = Path(tempfile.mkdtemp(prefix='world-api-', dir=testroot))
world = test / 'world'
world.mkdir()
(world / 'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
(world / 'worldmods').mkdir()
(world / 'worldmods/brickcraft_test').symlink_to(root / 'tests/mods/brickcraft_test', target_is_directory=True)
user = test / 'user'
(user / 'games').mkdir(parents=True)
(user / 'games/brickcraft').symlink_to(root / 'game', target_is_directory=True)
config = test / 'test.conf'
config.write_text((root / 'brickcraft.conf').read_text() + '\nbrickcraft_world_api_test = true\nbrickcraft_world_api = true\nscreen_w = 1024\nscreen_h = 720\nwindow_maximized = false\ndefault_privs = interact, shout\n')
users = test / 'users.json'
for account in ('ApiOwner', 'Visitor'):
    subprocess.run(['python3', str(root / 'tools/world_api.py'), 'token', '--users', str(users), '--user', account, '--out', str(test / (account + '.token'))], check=True, stdout=subprocess.DEVNULL)
service = api.Service(world, users)
server = api.ThreadingHTTPServer(('127.0.0.1', 0), api.handler_for(service))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
url = f'http://127.0.0.1:{server.server_port}'
env = dict(os.environ, LUANTI_USER_PATH=str(user))
log = test / 'engine.log'
proc = subprocess.Popen([str(root / 'runtime/luanti.app/Contents/MacOS/luanti'), '--server', '--gameid', 'brickcraft', '--world', str(world), '--config', str(config), '--port', '30028', '--logfile', str(log)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
client = None
visitor_client = None
# Dedicated-server mode ensures the owner is tested without singleplayer admin privileges.
time.sleep(1)
client = subprocess.Popen([str(root / 'runtime/luanti.app/Contents/MacOS/luanti'), '--go', '--address', '127.0.0.1', '--name', 'ApiOwner', '--port', '30028', '--config', str(config), '--logfile', str(test / 'client.log')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('Test artifacts:', test, flush=True)


def request(method, args, actor='ApiOwner', key=None, expected=200, token=None):
    headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (token if token is not None else (test / (actor + '.token')).read_text().strip())}
    if key:
        headers['Idempotency-Key'] = key
    req = urllib.request.Request(url + '/v1/commands', json.dumps({'method': method, 'args': args}).encode(), headers)
    try:
        response = urllib.request.urlopen(req, timeout=6)
    except urllib.error.HTTPError as exc:
        response = exc
    data = json.load(response)
    assert response.status == expected, (response.status, data)
    return data


try:
    deadline = time.monotonic() + 60
    while not (world / 'api_ready.json').exists():
        content = log.read_text() if log.exists() else ''
        if 'ServerError' in content or 'ModError' in content or proc.poll() is not None:
            raise RuntimeError(content[-6000:])
        if time.monotonic() > deadline:
            raise RuntimeError('Timed out: ' + content[-6000:])
        time.sleep(.2)
    ready = json.loads((world / 'api_ready.json').read_text())
    wid, pos = ready['world_id'], ready['pos']
    base = {'world_id': wid}
    region = dict(base, min=pos, max=dict(pos, z=pos['z'] + 1))
    operation = {'kind': 'place', 'pos': pos, 'shape': '2x4', 'color': 'coral'}
    request('worlds', {}, token='invalid', expected=401)
    assert len(request('worlds', {}, actor='Visitor')['result']['worlds']) >= 2
    assert not request('region', region, actor='Visitor')['result']['pieces']
    request('preview', dict(base, operation=operation), actor='Visitor', expected=403)
    request('access', dict(base, action='grant', user='Visitor'), actor='Visitor', key='escalate', expected=403)
    preview = request('preview', dict(base, operation=operation))['result']['preview_id']
    applied = request('apply', dict(base, preview_id=preview), key='place-long')
    assert request('apply', dict(base, preview_id=preview), key='place-long') == applied, 'retry must return original result'
    request('apply', dict(base, preview_id='different'), key='place-long', expected=400)
    snapshot = request('region', region)['result']
    assert len(snapshot['pieces']) == 1 and len(snapshot['pieces'][0]['footprint']) == 2, snapshot
    receipt = applied['result']['operation_id']
    rotate = request('preview', dict(base, operation={'kind': 'rotate', 'pos': pos}))['result']['preview_id']
    rotated = request('apply', dict(base, preview_id=rotate), key='rotate-long')['result']['operation_id']
    request('undo', dict(base, operation_id=receipt), key='undo-old', expected=409)
    request('undo', dict(base, operation_id=rotated), key='undo-rotate')
    # Two previews for one empty cell: the later apply must detect the first write.
    p2 = dict(pos, x=pos['x'] + 4)
    op2 = dict(operation, pos=p2, shape='2x2')
    a = request('preview', dict(base, operation=op2))['result']['preview_id']
    b = request('preview', dict(base, operation=op2))['result']['preview_id']
    request('apply', dict(base, preview_id=a), key='place-single')
    request('apply', dict(base, preview_id=b), key='stale', expected=409)
    remove = request('preview', dict(base, operation={'kind': 'remove', 'pos': p2}))['result']['preview_id']
    removed = request('apply', dict(base, preview_id=remove), key='remove-single')['result']['operation_id']
    request('undo', dict(base, operation_id=removed), key='undo-remove')
    request('access', dict(base, action='grant', user='Visitor'), key='grant')
    access = request('access', base)['result']
    assert access['writers'] == ['Visitor'] and access['owner'] == 'ApiOwner'
    # A grant does not impersonate an online player or bypass inventory ownership.
    request('preview', dict(base, operation=op2), actor='Visitor', expected=409)
    visitor_client = subprocess.Popen([str(root / 'runtime/luanti.app/Contents/MacOS/luanti'), '--go', '--address', '127.0.0.1', '--name', 'Visitor', '--port', '30028', '--config', str(config), '--logfile', str(test / 'visitor.log')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 20
    while not (world / 'api_visitor_ready').exists():
        if time.monotonic() > deadline:
            raise RuntimeError('Visitor did not join: ' + (test / 'visitor.log').read_text()[-3000:])
        time.sleep(.1)
    visitor_op = dict(op2, pos=dict(p2, x=p2['x'] + 8))
    visitor_preview = request('preview', dict(base, operation=visitor_op), actor='Visitor')['result']['preview_id']
    visitor_edit = request('apply', dict(base, preview_id=visitor_preview), actor='Visitor', key='permitted-write')['result']['operation_id']
    request('access', dict(base, action='revoke', user='Visitor'), key='revoke')
    request('undo', dict(base, operation_id=visitor_edit), actor='Visitor', key='revoked-visitor-undo', expected=403)
    request('access', dict(base, action='grant', user='Visitor'), key='grant-again')
    request('undo', dict(base, operation_id=visitor_edit), actor='Visitor', key='permitted-undo')
    request('access', dict(base, action='revoke', user='Visitor'), key='final-revoke')
    request('preview', dict(base, operation=op2), actor='Visitor', expected=403)
    request('region', dict(base, min=pos, max=dict(pos, y=pos['y'] + 32768)), expected=400)
    request('preview', dict(base, operation=dict(operation, shape='cart')), expected=400)
    # Changing the ACL between preview/apply is rechecked, including for the former owner.
    fresh = request('preview', dict(base, operation=dict(op2, pos=dict(p2, x=p2['x'] + 4))))['result']['preview_id']
    request('apply', dict(base, preview_id=fresh), expected=400)  # required retry key
    request('access', dict(base, action='owner', user='Visitor'), key='transfer')
    request('apply', dict(base, preview_id=fresh), key='revoked-preview', expected=403)
    request('undo', dict(base, operation_id=removed), key='revoked-undo', expected=403)
    request('access', dict(base, action='grant', user='ApiOwner'), actor='Visitor', key='regrant')
    request('access', dict(base, action='owner', user='ApiOwner'), actor='Visitor', key='transfer-back')
    # A permitted account can edit with its own online inventory; disconnect is tested above.
    request('apply', dict(base, preview_id=fresh), key='restored-access')
    visitor_client.terminate(); visitor_client.wait(timeout=8); visitor_client=None
    client.terminate(); client.wait(timeout=8); client=None
    proc.terminate(); proc.wait(timeout=8)
    restart_log = test / 'restart.log'
    proc = subprocess.Popen([str(root / 'runtime/luanti.app/Contents/MacOS/luanti'), '--server', '--gameid', 'brickcraft', '--world', str(world), '--config', str(config), '--port', '30028', '--logfile', str(restart_log)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 20
    while True:
        content = restart_log.read_text() if restart_log.exists() else ''
        if 'BRICKCRAFT API PERSISTENCE PASS' in content:
            break
        if 'ServerError' in content or 'ModError' in content or proc.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError('Persistence check failed: ' + content[-4000:])
        time.sleep(.1)
    assert request('apply', dict(base, preview_id=preview), key='place-long') == applied, 'retry survives restart'
    print('PASS: HTTP auth, ACLs and persistence, denied clicks, engine protection, logical footprints, place/rotate/remove/undo, stale/revoked previews, retries across restart, validation.', flush=True)
finally:
    if visitor_client:
        visitor_client.terminate()
        try:
            visitor_client.wait(timeout=8)
        except subprocess.TimeoutExpired:
            visitor_client.kill(); visitor_client.wait()
    if client:
        client.terminate()
        try:
            client.wait(timeout=8)
        except subprocess.TimeoutExpired:
            client.kill(); client.wait()
    proc.terminate()
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    server.shutdown()
    server.server_close()
