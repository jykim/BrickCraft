#!/usr/bin/env python3
"""Authenticated, local HTTP transport for BrickCraft. See docs/WORLD_API.md."""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

MAX_BODY = 65536


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.' + secrets.token_hex(8) + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, separators=(',', ':'))
    os.replace(temporary, path)


class Service:
    def __init__(self, world, users):
        self.root = world.resolve() / 'world_api'
        self.users = users.resolve()
        for name in ('inbox', 'outbox', 'jobs'):
            (self.root / name).mkdir(parents=True, exist_ok=True, mode=0o700)
            (self.root / name).chmod(0o700)
        self.root.chmod(0o700)
        self.lock = threading.Lock()

    def authenticate(self, header):
        if not header.startswith('Bearer ') or len(header) > 256:
            return None
        digest = hashlib.sha256(header[7:].encode()).hexdigest()
        # Read each time so revoking/rotating a token takes effect immediately.
        accounts = json.loads(self.users.read_text())
        for name, expected in accounts.items():
            if isinstance(expected, str) and hmac.compare_digest(digest, expected):
                return name
        return None

    def submit(self, actor, body, key=None):
        request = {'actor': actor, 'method': body['method'], 'args': body['args']}
        if len(json.dumps(request).encode()) > MAX_BODY:
            raise ValueError('Encoded command exceeds 65536 bytes.')
        fingerprint = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
        job_id = hashlib.sha256((actor + '\0' + key).encode()).hexdigest()[:32] if key else secrets.token_hex(16)
        job = self.root / 'jobs' / (job_id + '.json')
        with self.lock:
            if job.exists():
                saved = json.loads(job.read_text())
                if saved['actor'] != actor or saved['fingerprint'] != fingerprint:
                    raise ValueError('Idempotency-Key was already used for a different request.')
                if not (self.root / 'inbox' / job.name).exists() and not (self.root / 'outbox' / job.name).exists():
                    atomic_json(self.root / 'inbox' / job.name, request)
            else:
                if sum(1 for _ in (self.root / 'inbox').glob('*.json')) >= 128:
                    raise OSError('Command queue full')
                # Store the owner before publishing the request to the game thread.
                atomic_json(job, {'actor': actor, 'fingerprint': fingerprint})
                atomic_json(self.root / 'inbox' / job.name, request)
        return job_id

    def result(self, actor, job_id):
        if not re.fullmatch(r'[0-9a-f]{32}', job_id):
            return 404, {'ok': False, 'error': {'code': 'not_found', 'message': 'Unknown request.'}}
        job = self.root / 'jobs' / (job_id + '.json')
        if not job.exists() or json.loads(job.read_text())['actor'] != actor:
            return 404, {'ok': False, 'error': {'code': 'not_found', 'message': 'Unknown request.'}}
        output = self.root / 'outbox' / job.name
        if not output.exists():
            return 202, {'ok': True, 'pending': True, 'request_id': job_id, 'poll': '/v1/requests/' + job_id}
        data = json.loads(output.read_text())
        code = (data.get('error') or {}).get('code')
        status = 200 if data.get('ok') else {'forbidden': 403, 'not_found': 404, 'internal': 500,
            'conflict': 409, 'expired_preview': 409, 'player_offline': 409, 'unloaded_region': 409}.get(code, 400)
        return status, dict(data, request_id=job_id)


def handler_for(service):
    class Handler(BaseHTTPRequestHandler):
        server_version = 'BrickCraftWorldAPI/1'

        def log_message(self, *_):
            pass  # Never log Authorization headers, tokens, or submitted bodies.

        def reply(self, status, data):
            encoded = json.dumps(data, separators=(',', ':')).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(encoded)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(encoded)

        def handle_request(self):
            self.connection.settimeout(5)
            # Browsers cannot use this local control API cross-origin.
            if self.headers.get('Origin'):
                self.reply(403, {'ok': False, 'error': {'code': 'forbidden', 'message': 'Browser origins are not supported.'}})
                return
            actor = service.authenticate(self.headers.get('Authorization', ''))
            if not actor:
                self.reply(401, {'ok': False, 'error': {'code': 'unauthorized', 'message': 'Bearer token required.'}})
                return
            path = urlsplit(self.path).path
            if self.command == 'GET' and path.startswith('/v1/requests/'):
                self.reply(*service.result(actor, path.removeprefix('/v1/requests/')))
                return
            if self.command != 'POST' or path != '/v1/commands':
                self.reply(404, {'ok': False, 'error': {'code': 'not_found', 'message': 'Unknown endpoint.'}})
                return
            if self.headers.get('Transfer-Encoding'):
                raise ValueError('Transfer-Encoding is not supported.')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_BODY:
                raise ValueError('Body must be 1..65536 bytes.')
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError('Incomplete body.')
            body = json.loads(raw)
            if not isinstance(body, dict) or set(body) != {'method', 'args'} or not isinstance(body['args'], dict):
                raise ValueError('Body must contain only method and args; identity comes from the token.')
            if body['method'] not in {'worlds', 'region', 'access', 'preview', 'apply', 'undo'}:
                raise ValueError('Unknown method.')
            key = self.headers.get('Idempotency-Key')
            if key and not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}', key):
                raise ValueError('Invalid Idempotency-Key.')
            if (body['method'] in {'apply', 'undo'} or (body['method'] == 'access' and body['args'].get('action'))) and not key:
                raise ValueError('Mutations require Idempotency-Key.')
            job_id = service.submit(actor, body, key)
            deadline = time.monotonic() + 2
            while True:
                status, result = service.result(actor, job_id)
                if status != 202 or time.monotonic() >= deadline:
                    self.reply(status, result)
                    return
                time.sleep(.05)

        def guarded(self):
            try:
                self.handle_request()
            except (ValueError, TypeError, KeyError) as exc:
                self.reply(400, {'ok': False, 'error': {'code': 'invalid_request', 'message': str(exc)}})
            except (BrokenPipeError, ConnectionResetError, TimeoutError):
                pass
            except OSError:
                self.reply(503, {'ok': False, 'error': {'code': 'unavailable', 'message': 'API files or account configuration unavailable.'}})
        do_GET = guarded
        do_POST = guarded
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    provision = commands.add_parser('token', help='Create/rotate a token without printing it')
    provision.add_argument('--users', type=Path, required=True)
    provision.add_argument('--user', required=True, help='Exact Luanti account name')
    provision.add_argument('--out', type=Path, required=True, help='New private file receiving the bearer token')
    serve = commands.add_parser('serve')
    serve.add_argument('--world', type=Path, required=True)
    serve.add_argument('--users', type=Path, required=True)
    serve.add_argument('--port', type=int, default=8772)
    args = parser.parse_args()
    if args.command == 'token':
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,40}', args.user):
            parser.error('Invalid account name.')
        if args.users.resolve() == args.out.resolve():
            parser.error('--users and --out must be different files.')
        accounts = json.loads(args.users.read_text()) if args.users.exists() else {}
        token = secrets.token_urlsafe(32)
        fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(token + '\n')
        accounts[args.user] = hashlib.sha256(token.encode()).hexdigest()
        atomic_json(args.users, accounts)
        print('Token saved to', args.out, '(mode 0600). Existing token for this account revoked.')
    else:
        if not (args.world / 'world.mt').is_file():
            parser.error('--world must be an existing Luanti world directory.')
        json.loads(args.users.read_text())
        service = Service(args.world, args.users)
        server = ThreadingHTTPServer(('127.0.0.1', args.port), handler_for(service))
        print(f'World API listening on http://127.0.0.1:{server.server_port}; enable brickcraft_world_api in the game.', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == '__main__':
    main()
