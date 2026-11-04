# BrickCraft world API v1

This opt-in API lets an authenticated external client inspect worlds and edit ordinary
bricks through the running Luanti server. The server checks permissions, inventory,
occupied cells, and strict LEGO rules. Python provides HTTP transport; it does not edit
map SQLite files. This version supports one piece per edit.

## What clients can and cannot do

| Capability | v1 behavior |
| --- | --- |
| List worlds | Read built worlds, IDs, centers, bounds, strict mode, ownership, permitted writers, and whether your account can write. |
| Read a region | Read up to 32,768 loaded cells in one world. Returns logical placed pieces, their footprints, terrain, and a content revision. Air is omitted. |
| Read private worlds | All authenticated API accounts can read all worlds. “Private” restricts writing, not reading or visiting. |
| Place ordinary bricks | Preview and place one catalog brick, plate, tile, round brick, or slope, in an owned/permitted/shared world. Uses one piece from your connected account's current inventory. |
| Remove ordinary bricks | Preview and collect one piece, returning it to your inventory. Clicking either end of a long brick selects the whole piece. |
| Rotate ordinary bricks | Preview and rotate one piece 90 degrees, including its footprint. |
| Preview | Checks access, inventory, occupied cells, and strict rules without changing the world. Valid for 60 seconds; applying checks again. |
| Undo | Undo your latest API edit by its operation ID, if it is still your latest build action and the world/inventory/support conditions allow reversal. |
| Manage write access | Owners and world admins can grant/revoke accounts, switch shared/private, and transfer ownership. ACL changes persist. |
| Edit while offline | **Unsupported.** Read and access-management commands work offline, but piece edits and undo require the token's account to be connected with `interact` privilege. |
| Edit through a family profile name | **Unsupported.** Tokens and grants identify exact Luanti account names. Selecting “Dad” or another family profile does not grant world access. Your account's active profile still determines its existing inventory, as in-game. |
| Spawn or operate trains, carts, machines, gears, models, creatures, weapons, or kingdom resources | **Unsupported.** Some placed feature nodes may appear in snapshots, but there are no API commands to edit or control them. |
| Edit terrain, baseplates, protected floors, or arbitrary node types | **Unsupported.** v1 removal targets ordinary pieces, not scenery. |
| Bulk build plans / atomic batches | **Unsupported.** Each preview/apply edits one logical piece. Clients can sequence edits, but the sequence is not atomic. |
| Load/generate distant map regions | **Unsupported.** Visit the region in-game first. Reads fail explicitly for unloaded cells. |
| Create/delete worlds or modify world bounds | **Unsupported.** Create worlds through the game's world picker. |
| Change inventory directly, move players, run chat commands, execute Lua, read server files, change settings, or administer tokens over HTTP | **Unsupported.** Token provisioning is a local operator command. |
| Live event subscriptions / global world revision | **Unsupported.** Poll bounded region snapshots. Their revision is a content hash of that region, not a global counter. |

World access does not bypass stricter restrictions inside individual game modes.
World write permissions also guard in-game construction callbacks, collection, rotation,
undo, feature item/entity interactions, and feature control commands/menus. AI builders
inherit their connected owner's account permission. The server's autonomous simulation
(trains already running, creatures, weather, combat and scripted world generation)
continues; the ACL is not a freeze-world switch or a terrain boundary for simulation.
Server mods are trusted code and can still modify the map internally.

## Ownership and permissions

New worlds created from the world picker have:

- `owner`: the creator's exact Luanti account name;
- `writers`: explicitly permitted account names;
- `public_write`: false.

Existing worlds and server-created shared worlds, including Workshop, remain shared
until an administrator assigns an owner. Existing family-profile ownership is retained
as `legacy_owner` for display; it does not prove account identity. There is no first-visitor
claiming of existing worlds.

`world_admin` permits owner assignment and bypasses the world ACL. Existing protection
from other mods is still honored for piece edits. Singleplayer receives this privilege;
on a multiplayer server, an operator can grant it with `/grant ACCOUNT world_admin`.
An ordinary owner can manage their own world's ACL but cannot assign themselves other
worlds. Ownership transfer clears prior writer grants and makes the world private.
Revocation affects subsequent edits, already-issued previews, and undo immediately.

In-game, visit the world and use:

```text
/worldaccess
/worldaccess grant FriendsLaptop
/worldaccess revoke FriendsLaptop
/worldaccess public
/worldaccess private
/worldaccess owner NewOwnerAccount
```

The first command shows the ACL. An admin uses `owner` to assign an existing shared world.
Use actual connection/account names, not display labels. The current family setup allows
profile switching and shared profile inventories; ACLs do not change that inventory model.
Use distinct, password-protected Luanti accounts when account separation matters.

## Enable and authenticate

1. Add `brickcraft_world_api = true` to the configuration used by the **server**, then
   restart that server. The default is disabled. No live world is changed by installing
   these source files.
2. Provision a token for an exact Luanti account. From the repository root:

   ```sh
   python3 tools/world_api.py token \
     --users /private/path/brickcraft-api-users.json \
     --user FriendsLaptop \
     --out /private/path/FriendsLaptop.token
   ```

   The command writes a new token file with mode 0600 and stores only its SHA-256 hash
   in the users file, also mode 0600. It never prints the token. The output token path
   must not already exist. Repeating for an account with a new output path rotates its
   token. Remove an account from the users JSON file to revoke API authentication.
   The HTTP service rereads this file for each request. Account provisioning is an
   operator action and can impersonate that account; protect these local files.
3. Start the local HTTP service against the **same physical Luanti save directory**:

   ```sh
   python3 tools/world_api.py serve \
     --world /absolute/path/to/BrickCraft/worlds/workshop \
     --users /private/path/brickcraft-api-users.json \
     --port 8772
   ```

The service binds only to `127.0.0.1`. For a client on another computer, use an SSH tunnel
(or a separately managed authenticated TLS proxy). Bearer tokens authorize requests;
do not expose this plain HTTP listener directly. Browser-origin requests are rejected;
v1 is intended for native tools/scripts, not cross-origin browser JavaScript.

The local service and game exchange JSON under `<save>/world_api/{inbox,outbox,jobs}`.
These directories are local control files, not a client-editable API. The service restricts
them to mode 0700. Start one HTTP service per save directory. No server restart or launcher
integration is performed automatically.

## HTTP contract

Every request needs `Authorization: Bearer TOKEN`. The token determines the account;
clients cannot submit an `actor`, account override, or admin role.

- `POST /v1/commands`: JSON body containing exactly `method` and `args`.
- `GET /v1/requests/REQUEST_ID`: poll a submitted request as the same account.
- `Idempotency-Key`: **required** for `apply`, `undo`, and access changes. Use a fresh key
  per intended mutation, and reuse that key only to retry the identical request. Optional
  for reads and previews. Keys contain 1–128 letters, numbers, `_`, `.`, `:`, or `-`.

Success is `{"ok":true,"result":...,"request_id":"..."}`. The service waits up to two
seconds for the game. If still pending, HTTP 202 returns:

```json
{"ok":true,"pending":true,"request_id":"...","poll":"/v1/requests/..."}
```

Poll that URL until it returns a final result. A pending response is not confirmation
that an edit happened. With the game stopped or the setting disabled, commands remain
pending. Restarting the game may process queued commands; previews expire across game
restarts. A disconnected HTTP client does not cancel a command already submitted.

Results and idempotency records are retained in the save's `world_api` directory across
service/game restarts. Retrying an identical key returns the original result; changing
its request returns HTTP 400. Keys are account-scoped. A crash between a map write and
recording its response cannot guarantee exactly-once execution: inspect the world before
retrying an uncertain edit under a new key. Never delete queued requests to cancel them
while the game is running. With both processes stopped, operators can clear the bridge
directory when old request history is no longer needed; this also discards retry history.

Encoded commands are limited to 65,536 bytes. At most 128 requests can be queued, eight
are processed per game tick (at most every 0.1 seconds), and active previews are capped
at 32 per account / 256 total. Apply/undo run on the game thread. Previews reserve neither
space nor inventory. Support, inventory, and permissions are checked again at apply time.

## Command reference

All positions use absolute server coordinates: integer `{x,y,z}` within ±30,000, with Y
up. Use the center and bounds returned by `worlds`; worlds occupy different map squares.
All commands except `worlds` require `world_id`. Piece edits require Y ≥ 0.

### `worlds`

```json
{"method":"worlds","args":{}}
```

Returns `worlds`, each with `id`, `name`, `center`, horizontal `bounds`, `strict`, `access`,
and `can_write`. Unbuilt worlds are omitted. `access` contains `owner` (absent for legacy
shared worlds), `writers`, `public_write`, and optional `legacy_owner`.

### `region`

```json
{"method":"region","args":{"world_id":0,"min":{"x":10,"y":0,"z":0},"max":{"x":15,"y":4,"z":5}}}
```

Bounds are inclusive, ordered, and within a single world; volume must be ≤32,768 cells.
Returns `pieces`, `terrain`, `min`, `max`, `world_id`, and `revision`. Each ordinary piece
includes `pos`, node name, shape, color, turn, and footprint. A long piece appears once,
even if only its tail intersects the requested region; its origin can be just outside
that region. Feature nodes may lack ordinary color/shape semantics. This endpoint does
not return entities, node metadata, inventories, player positions, or train state.
Empty Lua collections may serialize as `{}`; treat these as empty collections.

### `access`

Read the ACL:

```json
{"method":"access","args":{"world_id":1}}
```

Change it (owner/admin only, with `Idempotency-Key`):

```json
{"method":"access","args":{"world_id":1,"action":"grant","user":"FriendsLaptop"}}
```

Actions: `grant`, `revoke`, `owner` require `user`; `public` and `private` do not.
Account names use 1–40 letters, numbers, `_`, or `-`. Making a world private requires an
assigned owner. Grants may name an account that is currently offline.

### `preview`

```json
{"method":"preview","args":{"world_id":1,"operation":{"kind":"place","shape":"2x4","color":"coral","pos":{"x":140,"y":0,"z":0},"turn":0}}}
```

Returns `preview_id`, normalized `operation`, and `expires_in:60`. `turn` is 0–3, default
0, in Luanti horizontal facedir order. Places at the specified origin cell; existing
buildable cells can be replaced, while occupied piece footprints cannot.

Ordinary shape IDs: `2x2`, `1x2`, `2x4`, `1x1`, `plate`, `plate_1x2`, `plate_2x4`,
`plate_1x1`, `tile_2x2`, `tile_1x2`, `round_2x2`, `round_1x1`, `slope_2x2`, `slope_2x1`,
`slope_inv_2x2`.

Colors: `coral`, `gold`, `mint`, `sky`, `violet`, `cream`, `navy`, `rose`, `green`, `brown`,
`tan`. Cost is one piece of that exact shape/color, including for long pieces.

To remove or rotate, supply only `kind` and `pos`:

```json
{"method":"preview","args":{"world_id":1,"operation":{"kind":"remove","pos":{"x":140,"y":0,"z":0}}}}
```

`rotate` advances the existing piece by one quarter turn. API edits are authorized editor
commands: they do not require the player's cursor, reach, or line of sight. Inventory,
world protection, space, and strict LEGO support rules still apply.

### `apply`

```json
{"method":"apply","args":{"world_id":1,"preview_id":"FROM_PREVIEW"}}
```

Requires `Idempotency-Key`. Only the same account can apply its preview. Returns
`operation_id` and `operation`. A change to any touched cell makes the preview conflict;
other changes that affect strict support are caught by revalidation. Applying consumes
the preview. It does not accept a region revision as a replacement for a preview.

### `undo`

```json
{"method":"undo","args":{"world_id":1,"operation_id":"FROM_APPLY"}}
```

Requires `Idempotency-Key`. Returns `undone`. Only your latest unchanged action can be
undone. A newer in-game or API build action supersedes it. Undo receipts and previews
are in memory and expire when the game restarts; this is not persistent version history.
Access changes themselves cannot be undone through this command.

## Python client example

This example handles pending responses and never prints the token. The account must
already be connected, own or have write access to world 1, and own the requested piece.
Choose a loaded, empty position within that world's returned bounds.

```python
import json, time, uuid
from pathlib import Path
from urllib.request import Request, urlopen

base = 'http://127.0.0.1:8772'
token = Path('/private/path/FriendsLaptop.token').read_text().strip()
headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}

def command(method, args, key=None):
    h = dict(headers)
    if key:
        h['Idempotency-Key'] = key
    req = Request(base + '/v1/commands',
                  json.dumps({'method': method, 'args': args}).encode(), h)
    while True:
        with urlopen(req, timeout=10) as response:
            result = json.load(response)
        if not result.get('pending'):
            return result['result']
        time.sleep(.2)
        req = Request(base + result['poll'], headers=headers)

print(command('worlds', {}))
preview = command('preview', {'world_id': 1, 'operation': {
    'kind': 'place', 'shape': '2x4', 'color': 'coral',
    'pos': {'x': 140, 'y': 0, 'z': 0}, 'turn': 0}})
edit = command('apply', {'world_id': 1, 'preview_id': preview['preview_id']},
               key=str(uuid.uuid4()))
command('undo', {'world_id': 1, 'operation_id': edit['operation_id']},
        key=str(uuid.uuid4()))
```

Keep an apply's idempotency key if you need to retry after an HTTP failure; do not
regenerate it for a retry. Production clients should bound polling, handle HTTP errors,
and persist the request ID/key until the outcome is known.

## Errors and verification

Errors use `{"ok":false,"error":{"code":"...","message":"..."},"request_id":"..."}`
(request ID may be absent for transport errors).

| HTTP | Meaning |
| --- | --- |
| 400 | `invalid_request`, `unsupported`, `out_of_bounds`, `occupied`, `inventory`, `build_rule`, or preview capacity `busy`; fix the command or wait for previews to expire. |
| 401 | Missing, invalid, or revoked bearer token. |
| 403 | World permission, interact privilege, admin/owner requirement, protected cell, or rejected browser origin. |
| 404 | Missing world, endpoint, or request; another account's request is also hidden as 404. |
| 409 | Stale/expired preview, undo conflict, offline player, or unloaded region. |
| 500 / 503 | Internal game error / local transport unavailable or queue full. |

Run `python3 tools/test_world_api.py` for a dedicated Luanti server, real connected GUI
client, and authenticated HTTP integration checks in a disposable save. It verifies ACLs,
unauthorized clicks, logical footprints, inventory-backed place/remove/rotate/undo,
conflicting previews, retry deduplication across restart, ownership transfer,
permitted-user writes, revoked access, and persistent ACLs.
