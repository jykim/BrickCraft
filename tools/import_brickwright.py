#!/usr/bin/env python3
"""Bring BrickWright builds into BrickCraft as models made of their real parts.

Reads a build's mesh (`<record>.glb`: one node per LDraw part, metres) from the BrickWright
gallery and writes, per model:

  brickcraft_model_<slug>_<k>.glb  one mesh per distinct part and rotation, around its middle
  brickcraft_model_<slug>_preview.glb  the whole model in one mesh, for the Model Gallery's 3D view
  <slug>.json / model.json         the parts (mesh, colour, middle, half size), which parts
                                   touch, which stand on the ground, and the same build in
                                   game bricks (for "Convert to game bricks")

Samples go into the game (game/mods/brickcraft_models/parts and data/; `parts` isn't a
media folder, so players get a model's files only when they come near it). `--send` puts one
into a world's inbox (<world>/brickwright_models/<slug>/) instead, where the running game
picks it up without a restart; the same version (the same mesh) isn't sent twice. `--status`
says whether a build is there and whether it's the gallery's current version.

Real proportions: a game cell is 16 mm every way, 2 x 2 studs across and five plates tall,
so a real 2 x 2 brick is a game 2 x 2 brick across, three fifths of a cell tall, a plate a
fifth, and the parts look as they do in BrickWright (not stretched up to a cell a brick).
The game-brick version of a model fills the 16 mm cells the model stands in. Models go
down at minifig scale by default (the game's DEFAULT_SCALE), where a minifig is a player's
height; `cell_mm` in the data says these are real proportions.

Coordinates are written in Luanti's (left-handed: the glTF loader turns z round), so the
parts' places agree with their meshes: a model's front faces -z.

Python standard library only, like the other tools.

    python3 tools/import_brickwright.py                        # the samples below
    python3 tools/import_brickwright.py <slug>=<record id> ...  # others, into the game
    python3 tools/import_brickwright.py --send <record id> [--title T] [--world DIR] [--gallery DIR]
    python3 tools/import_brickwright.py --status <record id> [--world DIR] [--gallery DIR]
    python3 tools/import_brickwright.py --previews [--world DIR]  # gallery views for models without one
"""
import hashlib, json, math, os, re, struct, sys, time, zlib
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'game' / 'mods' / 'brickcraft_models'
GALLERY = Path(os.environ.get('BRICKWRIGHT_SITE', '/Volumes/990PRO/lifidea/Projects/dev/brickwright/site'))
CELL_M = 0.016          # a cell is 2 studs = 16 mm, every way (real proportions)
UNITS = 10 / CELL_M     # Luanti mesh units: 10 per cell
MAX_VERTS = 65535       # 16-bit indices per primitive
MAX_INDICES = 65535     # Luanti's glTF loader also counts corners against this ('too many vertices')
TOUCH_M = 0.0005        # parts closer than this touch

SAMPLES = {
    'bonsai': '20261102-143725-prompt-f2aca499',
    'house': '20261103-140000-e9280f16',
    'cat': '20261101-155104-black-cat-100-pieces-c96e2cfe',
    'mech': '20261102-224138-a45a670a',
    'train': '20261103-104004-abcfdf84',
    'car': '20261103-114030-56f63d5a',
}
TITLES = {'bonsai': 'Red Maple Bonsai', 'house': 'Two-Tone House', 'cat': 'Black Cat',
          'mech': 'Humanoid Mech', 'train': 'Train', 'car': 'Car'}
# The game's brick colours (tools/generate_assets.py).
GAME_COLORS = dict(coral=(235, 93, 72), gold=(249, 193, 65), mint=(74, 183, 147), sky=(74, 161, 217),
                   violet=(151, 116, 203), cream=(238, 229, 199), navy=(48, 76, 110), rose=(229, 131, 165),
                   green=(88, 171, 65), brown=(118, 80, 52), tan=(196, 160, 110))


def read_glb(path):
    data = path.read_bytes()
    magic, _, _ = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67, f'{path} is not a .glb'
    off, js, binary = 12, None, None
    while off < len(data):
        length, kind = struct.unpack_from('<II', data, off)
        chunk = data[off + 8:off + 8 + length]
        if kind == 0x4E4F534A: js = json.loads(chunk)
        elif kind == 0x004E4942: binary = chunk
        off += 8 + length
    return js, binary


COMPONENTS = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def accessor(js, binary, i):
    a = js['accessors'][i]
    view = js['bufferViews'][a['bufferView']]
    code, size = COMPONENTS[a['componentType']]
    n = WIDTH[a['type']]
    start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = view.get('byteStride', size * n)
    out = array(code)
    if stride == size * n:
        out.frombytes(binary[start:start + a['count'] * stride])
    else:
        for k in range(a['count']):
            out.extend(struct.unpack_from('<' + code * n, binary, start + k * stride))
    return out


def mat_mul(a, b):  # column-major 4x4
    return [sum(a[r + 4 * k] * b[k + 4 * c] for k in range(4)) for c in range(4) for r in range(4)]


def node_matrix(n):
    if 'matrix' in n: return list(n['matrix'])
    t = n.get('translation', [0, 0, 0]); s = n.get('scale', [1, 1, 1])
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    r = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]
    return [r[0] * s[0], r[1] * s[0], r[2] * s[0], 0, r[3] * s[1], r[4] * s[1], r[5] * s[1], 0,
            r[6] * s[2], r[7] * s[2], r[8] * s[2], 0, t[0], t[1], t[2], 1]


def to_srgb(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))


def glb_bytes(name, pos, nor, idx):
    """One mesh: positions, normals (flat arrays) and triangles, split to the loader's limits.
    UVs all point at the middle of a one-colour texture the entity supplies."""
    out = bytearray()
    views, accessors, prims = [], [], []

    def add_view(blob, target):
        while len(out) % 4: out.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(blob), 'target': target})
        out.extend(blob)
        return len(views) - 1

    tri = 0
    while tri < len(idx):
        remap, local, corners = {}, array('H'), array('I')
        while tri < len(idx):
            new = sum(1 for v in idx[tri:tri + 3] if v not in remap)
            if len(remap) + new > MAX_VERTS or len(local) + 3 > MAX_INDICES: break
            for v in idx[tri:tri + 3]:
                if v not in remap:
                    remap[v] = len(corners); corners.append(v)
                local.append(remap[v])
            tri += 3
        P, N, T = array('f'), array('f'), array('f')
        lo, hi = [math.inf] * 3, [-math.inf] * 3
        for v in corners:
            p3 = pos[3 * v:3 * v + 3]
            P.extend(p3); N.extend(nor[3 * v:3 * v + 3]); T.extend((.5, .5))
            for a in range(3):
                lo[a] = min(lo[a], p3[a]); hi[a] = max(hi[a], p3[a])
        a0 = len(accessors)
        accessors += [
            {'bufferView': add_view(P.tobytes(), 34962), 'componentType': 5126, 'count': len(corners),
             'type': 'VEC3', 'min': lo, 'max': hi},
            {'bufferView': add_view(N.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC3'},
            {'bufferView': add_view(T.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC2'},
            {'bufferView': add_view(local.tobytes(), 34963), 'componentType': 5123, 'count': len(local), 'type': 'SCALAR'},
        ]
        prims.append({'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                      'indices': a0 + 3, 'material': 0, 'mode': 4})
    while len(out) % 4: out.append(0)
    gltf = {
        'asset': {'version': '2.0', 'generator': 'BrickCraft tools/import_brickwright.py'},
        'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': name}],
        'meshes': [{'name': name, 'primitives': prims}],
        'materials': [{'name': 'colour', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                                                   'metallicFactor': 0, 'roughnessFactor': 1}}],
        'samplers': [{'magFilter': 9728, 'minFilter': 9728}],
        'textures': [{'sampler': 0}],
        'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(out)}],
    }
    head = json.dumps(gltf, separators=(',', ':')).encode()
    head += b' ' * (-len(head) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(head) + 8 + len(out))
            + struct.pack('<II', len(head), 0x4E4F534A) + head + struct.pack('<II', len(out), 0x004E4942) + bytes(out))


PREVIEW_MM = (0.8, 3.0)  # the gallery's 3D view: corners closer than this join (a 120th of the model)
PREVIEW_LIGHT = (0.35, 0.85, 0.40)  # glTF axes: from above, the front and the right


def glb_groups(name, groups):
    """One mesh of several one-colour groups (pos, uv, idx), each split to the loader's
    limits; returns the bytes and, per primitive in order, its group (its texture)."""
    out = bytearray()
    views, accessors, prims, owner = [], [], [], []

    def add_view(blob, target):
        while len(out) % 4: out.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(blob), 'target': target})
        out.extend(blob)
        return len(views) - 1

    for g, (pos, nor, uv, idx) in enumerate(groups):
        tri = 0
        while tri < len(idx):
            remap, local, corners = {}, array('H'), array('I')
            while tri < len(idx):
                new = sum(1 for v in idx[tri:tri + 3] if v not in remap)
                if len(remap) + new > MAX_VERTS or len(local) + 3 > MAX_INDICES: break
                for v in idx[tri:tri + 3]:
                    if v not in remap:
                        remap[v] = len(corners); corners.append(v)
                    local.append(remap[v])
                tri += 3
            P, N, T = array('f'), array('f'), array('f')
            lo, hi = [math.inf] * 3, [-math.inf] * 3
            for v in corners:
                p3 = pos[3 * v:3 * v + 3]
                P.extend(p3); N.extend(nor[3 * v:3 * v + 3]); T.extend(uv[2 * v:2 * v + 2])
                for a in range(3):
                    lo[a] = min(lo[a], p3[a]); hi[a] = max(hi[a], p3[a])
            a0 = len(accessors)
            accessors += [
                {'bufferView': add_view(P.tobytes(), 34962), 'componentType': 5126, 'count': len(corners),
                 'type': 'VEC3', 'min': lo, 'max': hi},
                {'bufferView': add_view(N.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC3'},
                {'bufferView': add_view(T.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC2'},
                {'bufferView': add_view(local.tobytes(), 34963), 'componentType': 5123, 'count': len(local), 'type': 'SCALAR'},
            ]
            prims.append({'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                          'indices': a0 + 3, 'material': g, 'mode': 4})
            owner.append(g)
    while len(out) % 4: out.append(0)
    gltf = {
        'asset': {'version': '2.0', 'generator': 'BrickCraft tools/import_brickwright.py'},
        'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': name}],
        'meshes': [{'name': name, 'primitives': prims}],
        # Luanti gives out textures in the order of this file's `textures`: one per colour.
        'materials': [{'name': f'colour{g}', 'pbrMetallicRoughness': {'baseColorTexture': {'index': g},
                       'metallicFactor': 0, 'roughnessFactor': 1}} for g in range(len(groups))],
        'samplers': [{'magFilter': 9729, 'minFilter': 9729}],
        'textures': [{'sampler': 0} for _ in groups],
        'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(out)}],
    }
    head = json.dumps(gltf, separators=(',', ':')).encode()
    head += b' ' * (-len(head) % 4)
    blob = (struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(head) + 8 + len(out))
            + struct.pack('<II', len(head), 0x4E4F534A) + head + struct.pack('<II', len(out), 0x004E4942) + bytes(out))
    return blob, owner


def glb_parse(blob):
    magic, _, _ = struct.unpack_from('<III', blob, 0)
    off, js, binary = 12, None, None
    while off < len(blob):
        length, kind = struct.unpack_from('<II', blob, off)
        chunk = blob[off + 8:off + 8 + length]
        if kind == 0x4E4F534A: js = json.loads(chunk)
        elif kind == 0x004E4942: binary = chunk
        off += 8 + length
    return js, binary


def preview(model, meshes):
    """The whole model as one mesh for the gallery's 3D view (a formspec model[] shows one
    mesh): every part where it stands, a group per colour, corners closer than PREVIEW_MM
    merged (a big model has hundreds of thousands), and its light baked into the texture
    coordinates (u across a grey ramp, brickcraft_model_shade.png), since the view has no
    light of its own. Returns the bytes and the colours, in the order of its textures."""
    # A finer grid than a few pixels of the view wastes the player's download.
    mm = min(PREVIEW_MM[1], max(PREVIEW_MM[0], max(model['w'], model['h'], model['d']) * 16 / 120))
    grid = mm / 16 * 10  # mesh units: 10 a cell
    ln = math.sqrt(sum(v * v for v in PREVIEW_LIGHT)); L = [v / ln for v in PREVIEW_LIGHT]
    parsed = {}
    groups, colors = {}, []
    for p in model['parts']:
        k, color = p[0], p[1]
        if k not in parsed:
            js, binary = glb_parse(meshes[k - 1])
            tris = []
            for prim in js['meshes'][0]['primitives']:
                P = accessor(js, binary, prim['attributes']['POSITION'])
                I = accessor(js, binary, prim['indices'])
                tris.append((P, I))
            parsed[k] = tris
        # Its middle, in the mesh's glTF axes (z turned round).
        ox, oy, oz = p[2] * 10, p[3] * 10, -p[4] * 10
        if color not in groups:
            groups[color] = {'cells': {}, 'pos': array('f'), 'nor': array('f'), 'uv': array('f'),
                             'idx': array('I'), 'seen': set()}
            colors.append(color)
        g = groups[color]
        for P, I in parsed[k]:
            for t in range(0, len(I), 3):
                A = [P[3 * I[t + j] + a] + (ox, oy, oz)[a] for j in range(3) for a in range(3)]
                u = (A[3] - A[0], A[4] - A[1], A[5] - A[2]); v = (A[6] - A[0], A[7] - A[1], A[8] - A[2])
                n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
                nl = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
                if nl == 0: continue
                n = (n[0] / nl, n[1] / nl, n[2] / nl)
                # Corners join only on faces facing about the same way (sharp edges stay).
                facing = (round(n[0] * 2), round(n[1] * 2), round(n[2] * 2))
                corner = []
                for j in range(3):
                    c = (round(A[3 * j] / grid), round(A[3 * j + 1] / grid), round(A[3 * j + 2] / grid), facing)
                    if c not in g['cells']:
                        g['cells'][c] = len(g['pos']) // 3
                        g['pos'].extend((c[0] * grid, c[1] * grid, c[2] * grid))
                        g['nor'].extend(n)
                        light = .38 + .62 * max(0.0, n[0] * L[0] + n[1] * L[1] + n[2] * L[2])
                        g['uv'].extend((light, .5))
                    corner.append(g['cells'][c])
                if len(set(corner)) < 3: continue
                tkey = tuple(sorted(corner))
                if tkey in g['seen']: continue
                g['seen'].add(tkey)
                g['idx'].extend(corner)
    blob, owner = glb_groups(f'{model["slug"]}_preview',
                             [(groups[c]['pos'], groups[c]['nor'], groups[c]['uv'], groups[c]['idx']) for c in colors])
    return blob, colors


def shade_ramp(path):
    """The grey ramp the gallery's view is lit by: dark on the left, white on the right."""
    png(path, 64, 1, [[c for x in range(64) for c in (round(255 * x / 63),) * 3 + (255,)]])


def nearest_game_color(rgb):
    return min(GAME_COLORS, key=lambda c: sum((a - b) ** 2 for a, b in zip(GAME_COLORS[c], rgb)))


def convert(slug, record, gallery=GALLERY):
    """The model as parts (metres, Luanti axes), meshes per distinct part and rotation,
    touching pairs, grounded parts and its game-brick version."""
    js, binary = read_glb(gallery / 'models' / f'{record}.glb')
    colors = []
    for m in js['materials']:
        r, g, b, a = m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])
        colors.append((to_srgb(r), to_srgb(g), to_srgb(b), round(255 * a)))

    parts = []  # per part: key, colour, flat world positions, normals, triangles
    cache = {}
    uprights = {}  # (mesh, rotation of the parent) -> the part standing as in its own file

    def geom(mesh, m):
        """A part's triangles under matrix m: positions in Luanti's axes, glTF normals."""
        flip = (m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2])
                + m[8] * (m[1] * m[6] - m[5] * m[2])) < 0
        pos, nor, idx = array('f'), array('f'), array('I')
        material = 0
        for p in js['meshes'][mesh]['primitives']:
            assert p.get('mode', 4) == 4
            key = (p['attributes']['POSITION'], p['attributes'].get('NORMAL'), p['indices'])
            if key not in cache:
                cache[key] = (accessor(js, binary, key[0]),
                              accessor(js, binary, key[1]) if key[1] is not None else None,
                              accessor(js, binary, key[2]))
            P, N, I = cache[key]
            material = p.get('material', 0)
            base = len(pos) // 3
            for k in range(0, len(P), 3):
                x, y, z = P[k], P[k + 1], P[k + 2]
                # Luanti's axes: z turned round (the glTF loader does the same to meshes).
                pos.extend((m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
                            -(m[2] * x + m[6] * y + m[10] * z + m[14])))
                if N is not None:
                    a, b, c = N[k], N[k + 1], N[k + 2]
                    nx, ny, nz = m[0] * a + m[4] * b + m[8] * c, m[1] * a + m[5] * b + m[9] * c, m[2] * a + m[6] * b + m[10] * c
                    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
                    nor.extend((nx / l, ny / l, nz / l))  # glTF axes: for the mesh only
                else:
                    nor.extend((0, 1, 0))
            for k in range(0, len(I), 3):
                a, b, c = I[k] + base, I[k + 1] + base, I[k + 2] + base
                idx.extend((a, c, b) if flip else (a, b, c))
        return pos, nor, idx, material

    def rot_of(m):
        return tuple(round(v, 3) for v in (m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]))

    def walk(ni, parent):
        n = js['nodes'][ni]
        m = mat_mul(parent, node_matrix(n))
        if 'mesh' in n:
            pos, nor, idx, material = geom(n['mesh'], m)
            ukey = (n['mesh'], rot_of(parent))
            if ukey not in uprights:  # unturned: the parent's turn only, no move
                uprights[ukey] = geom(n['mesh'], parent[:12] + [0, 0, 0, 1])[:3]
            part = re.sub(r'\.dat$', '', js['meshes'][n['mesh']].get('name', '?'))
            cname = js['materials'][material].get('name', '').replace('_', ' ') if js.get('materials') else ''
            parts.append({'key': (n['mesh'], rot_of(m)), 'ukey': ukey, 'color': colors[material], 'pos': pos,
                          'nor': nor, 'idx': idx, 'part': part, 'cname': cname})
        for c in n.get('children', []):
            walk(c, m)

    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for ni in js['scenes'][js.get('scene', 0)]['nodes']:
        walk(ni, identity)

    lo, hi = [math.inf] * 3, [-math.inf] * 3
    for p in parts:
        plo, phi = [math.inf] * 3, [-math.inf] * 3
        P = p['pos']
        for k in range(0, len(P), 3):
            for a in range(3):
                v = P[k + a]
                if v < plo[a]: plo[a] = v
                if v > phi[a]: phi[a] = v
        p['lo'], p['hi'] = plo, phi
        for a in range(3):
            lo[a] = min(lo[a], plo[a]); hi[a] = max(hi[a], phi[a])
    origin = ((lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2)  # the middle of the model's foot

    # One mesh per distinct part and rotation, around the part's own middle, in mesh units.
    meshes, mesh_of, icons = [], {}, {}
    out_parts = []

    def add_mesh(key, pos, nor, idx, lo_, hi_):
        mid = [(lo_[a] + hi_[a]) / 2 for a in range(3)]
        if key not in mesh_of:
            P = array('f', pos)
            # The mesh is written in glTF's axes (z back round); the loader turns it again.
            for k in range(0, len(P), 3):
                P[k] = (P[k] - mid[0]) * UNITS
                P[k + 1] = (P[k + 1] - mid[1]) * UNITS
                P[k + 2] = -(P[k + 2] - mid[2]) * UNITS
            meshes.append(glb_bytes(f'{slug}_{len(meshes) + 1}', P, array('f', nor), idx))
            mesh_of[key] = len(meshes)
        return mesh_of[key], mid

    unit = (CELL_M, CELL_M, CELL_M)
    for p in parts:
        k, mid = add_mesh(p['key'], p['pos'], p['nor'], p['idx'], p['lo'], p['hi'])
        upos, unor, uidx = uprights[p['ukey']]
        ulo, uhi = [math.inf] * 3, [-math.inf] * 3
        for j in range(0, len(upos), 3):
            for a in range(3):
                ulo[a] = min(ulo[a], upos[j + a]); uhi[a] = max(uhi[a], upos[j + a])
        uk, umid = add_mesh(p['ukey'], upos, unor, uidx, ulo, uhi)
        if uk not in icons:  # its picture for the inventory: standing, from the front right
            icons[uk] = part_picture(upos, uidx, umid)
        r, g, b, a = p['color']
        out_parts.append([k, f'#{r:02x}{g:02x}{b:02x}{a:02x}',
                          *(round((mid[i] - origin[i]) / unit[i], 4) for i in range(3)),
                          *(round((p['hi'][i] - p['lo'][i]) / 2 / unit[i], 4) for i in range(3)),
                          p['part'], p['cname'], uk,
                          *(round((uhi[i] - ulo[i]) / 2 / unit[i], 4) for i in range(3))])

    # Touching parts (boxes within TOUCH_M), and the ones standing on the ground.
    links = []
    for i in range(len(parts)):
        a = parts[i]
        for j in range(i + 1, len(parts)):
            b = parts[j]
            if all(a['lo'][k] - TOUCH_M <= b['hi'][k] and b['lo'][k] - TOUCH_M <= a['hi'][k] for k in range(3)):
                links.append([i + 1, j + 1])
    ground = [i + 1 for i, p in enumerate(parts) if p['lo'][1] - lo[1] < TOUCH_M]

    # Game bricks: a cell is 16 mm every way. Surfaces are sampled
    # every 4 mm; each cell takes the game colour with the most area in it.
    votes = {}
    for p in parts:
        if p['color'][3] < 128: continue  # see-through parts (windows) stay open
        color = nearest_game_color(p['color'][:3])
        P, I = p['pos'], p['idx']
        for t in range(0, len(I), 3):
            A, B, C = (P[3 * I[t]:3 * I[t] + 3], P[3 * I[t + 1]:3 * I[t + 1] + 3], P[3 * I[t + 2]:3 * I[t + 2] + 3])
            e1 = [B[k] - A[k] for k in range(3)]; e2 = [C[k] - A[k] for k in range(3)]
            cx = e1[1] * e2[2] - e1[2] * e2[1]; cy = e1[2] * e2[0] - e1[0] * e2[2]; cz = e1[0] * e2[1] - e1[1] * e2[0]
            area = math.sqrt(cx * cx + cy * cy + cz * cz) / 2
            if area <= 0: continue
            n = max(1, min(12, int(math.sqrt(area) / 0.004) + 1))
            w = area / (n * (n + 1) / 2)
            for u in range(n):
                for v in range(n - u):
                    s, q = (u + 1 / 3) / n, (v + 1 / 3) / n
                    x = A[0] + s * e1[0] + q * e2[0] - origin[0]
                    y = A[1] + s * e1[1] + q * e2[1] - origin[1]
                    z = A[2] + s * e1[2] + q * e2[2] - origin[2]
                    cell = (round(x / CELL_M), int(y // CELL_M), round(z / CELL_M))
                    d = votes.setdefault(cell, {})
                    d[color] = d.get(color, 0) + w
    min_area = (CELL_M * CELL_M) * 0.06  # a cell needs a bit of surface, not one grazing corner
    bricks = sorted([[x, y, z, max(d, key=d.get)] for (x, y, z), d in votes.items() if sum(d.values()) >= min_area],
                    key=lambda b: (b[1], b[0], b[2]))

    return {
        'slug': slug, 'record': record,
        'w': round((hi[0] - lo[0]) / CELL_M, 2), 'h': round((hi[1] - lo[1]) / CELL_M, 2), 'd': round((hi[2] - lo[2]) / CELL_M, 2),
        'cell_mm': 16, 'alpha': any(c[3] < 255 for c in colors),
        'parts': out_parts, 'links': links, 'ground': ground, 'bricks': bricks,
    }, meshes, icons


ICON = 32


def part_picture(pos, idx, mid):
    """A light grey picture of a part (real proportions), lit from above, for its icon."""
    S = ICON * 2  # drawn twice as big, then halved: smooth edges
    cy, sy = math.cos(math.radians(35)), math.sin(math.radians(35))
    cp, sp = math.cos(math.radians(28)), math.sin(math.radians(28))
    pts = []
    for k in range(0, len(pos), 3):
        x, y, z = (pos[k] - mid[0]) / CELL_M, (pos[k + 1] - mid[1]) / CELL_M, (pos[k + 2] - mid[2]) / CELL_M
        x, z = x * cy - z * sy, x * sy + z * cy  # turned a little
        y, z = y * cp - z * sp, y * sp + z * cp  # seen from a little above
        pts.append((x, y, z))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) or 1
    f = (S - 6) / span
    ox, oy = (S - (max(xs) - min(xs)) * f) / 2 - min(xs) * f, (S - (max(ys) - min(ys)) * f) / 2 + max(ys) * f
    scr = [(p[0] * f + ox, oy - p[1] * f, p[2]) for p in pts]
    depth = [[-1e9] * S for _ in range(S)]
    shade = [[None] * S for _ in range(S)]
    L = (-.35, .8, .5)
    ln = math.sqrt(sum(v * v for v in L)); L = tuple(v / ln for v in L)
    for t in range(0, len(idx), 3):
        A, B, C = pts[idx[t]], pts[idx[t + 1]], pts[idx[t + 2]]
        u = [B[i] - A[i] for i in range(3)]; v = [C[i] - A[i] for i in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        nl = math.sqrt(sum(c * c for c in n))
        if nl == 0: continue
        n = tuple(c / nl for c in n)
        if n[2] < 0: n = tuple(-c for c in n)  # the side facing the viewer
        light = .42 + .58 * max(0.0, sum(n[i] * L[i] for i in range(3)))
        a, b, c = scr[idx[t]], scr[idx[t + 1]], scr[idx[t + 2]]
        x0, x1 = max(0, int(min(a[0], b[0], c[0]))), min(S - 1, int(max(a[0], b[0], c[0])) + 1)
        y0, y1 = max(0, int(min(a[1], b[1], c[1]))), min(S - 1, int(max(a[1], b[1], c[1])) + 1)
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9: continue
        for py in range(y0, y1 + 1):
            for px in range(x0, x1 + 1):
                qx, qy = px + .5, py + .5
                w1 = ((b[1] - c[1]) * (qx - c[0]) + (c[0] - b[0]) * (qy - c[1])) / den
                w2 = ((c[1] - a[1]) * (qx - c[0]) + (a[0] - c[0]) * (qy - c[1])) / den
                w3 = 1 - w1 - w2
                if w1 < -1e-6 or w2 < -1e-6 or w3 < -1e-6: continue
                z = w1 * a[2] + w2 * b[2] + w3 * c[2]
                if z > depth[py][px]:
                    depth[py][px] = z; shade[py][px] = light
    rows = []
    for y in range(ICON):
        row = []
        for x in range(ICON):
            cells = [shade[2 * y + dy][2 * x + dx] for dy in (0, 1) for dx in (0, 1)]
            hit = [c for c in cells if c is not None]
            if not hit:
                row.extend((0, 0, 0, 0)); continue
            g = round(255 * sum(hit) / len(hit))
            row.extend((g, g, g, round(255 * len(hit) / 4)))
        rows.append(row)
    return rows


def write_model(model, meshes, mesh_dir, data_path, prefix=None, icons=None, icon_dir=None):
    mesh_dir.mkdir(parents=True, exist_ok=True)
    data_path.parent.mkdir(parents=True, exist_ok=True)
    slug = model['slug']
    prefix = prefix or f'brickcraft_model_{slug}'
    for old in mesh_dir.glob(f'brickcraft_model_{slug}_*.glb'):
        old.unlink()
    for k, blob in enumerate(meshes, 1):
        assert len(blob) < 16_000_000
        (mesh_dir / f'{prefix}_{k}.glb').write_bytes(blob)
    icon_dir = icon_dir or mesh_dir
    icon_dir.mkdir(parents=True, exist_ok=True)
    for old in icon_dir.glob(f'brickcraft_model_{slug}_*.png'):
        old.unlink()
    for k, rows in (icons or {}).items():
        png(icon_dir / f'{prefix}_{k}.png', ICON, ICON, rows)
    model['meshes'] = len(meshes)
    model['mesh_prefix'] = prefix
    add_preview(model, meshes, mesh_dir, prefix)
    # Written last, under a temporary name: a reader that sees the json sees every mesh.
    tmp = data_path.with_suffix('.tmp')
    tmp.write_text(json.dumps(model, ensure_ascii=False, separators=(',', ':')))
    tmp.rename(data_path)


def add_preview(model, meshes, mesh_dir, prefix):
    """The gallery's 3D view of the model (one mesh), next to its parts."""
    blob, colors = preview(model, meshes)
    (mesh_dir / f'{prefix}_preview.glb').write_bytes(blob)
    model['preview'] = f'{prefix}_preview.glb'
    model['preview_colors'] = colors
    return blob


def add_previews(world=None):
    """Gallery views for models imported or sent before there were any (samples, and the
    world's inbox), from their meshes on disk."""
    found = [(MOD / 'data' / f'{s}.json', MOD / 'parts') for s in sorted(p.stem for p in (MOD / 'data').glob('*.json'))]
    found += [(j, j.parent) for j in sorted((world_dir(world) / 'brickwright_models').glob('*/model.json'))]
    for data_path, mesh_dir in found:
        model = json.loads(data_path.read_text())
        prefix = model.get('mesh_prefix') or f'brickcraft_model_{model["slug"]}'
        meshes = [(mesh_dir / f'{prefix}_{k}.glb').read_bytes() for k in range(1, model['meshes'] + 1)]
        blob = add_preview(model, meshes, mesh_dir, prefix)
        tmp = data_path.with_suffix('.tmp')
        tmp.write_text(json.dumps(model, ensure_ascii=False, separators=(',', ':')))
        tmp.rename(data_path)
        print(f'{model["slug"]:24} preview {len(blob) / 1e6:.1f} MB, {len(model["preview_colors"])} colours', flush=True)


def gallery_meta(gallery):
    path = gallery / 'models.json'
    return {m['id']: m for m in json.loads(path.read_text())['models']} if path.exists() else {}


def describe(model, meshes):
    size = sum(len(b) for b in meshes)
    return (f'{model["slug"]:10} {model["record"]}  {len(model["parts"]):>4} parts in {len(meshes)} meshes, '
            f'{size / 1e6:.1f} MB, {model["w"]:.1f} x {model["d"]:.1f} cells, {model["h"]:.1f} tall, '
            f'{len(model["bricks"])} game bricks')


def png(path, w, h, rows):
    raw = b''.join(b'\0' + bytes(row) for row in rows)
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def part_icon(path):
    """A light brick with two studs, tinted per part by the item's colour."""
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            stud = 3 <= y <= 5 and (3 <= x <= 6 or 9 <= x <= 12)
            body = 6 <= y <= 13 and 1 <= x <= 14
            edge = body and (y in (6, 13) or x in (1, 14))
            c = (255, 255, 255, 255) if stud or (body and not edge) else (170, 170, 170, 255) if edge else (0, 0, 0, 0)
            row.extend(c)
        rows.append(row)
    png(path, 16, 16, rows)


def import_samples(picks):
    (MOD / 'textures').mkdir(parents=True, exist_ok=True)
    part_icon(MOD / 'textures' / 'brickcraft_real_part.png')
    shade_ramp(MOD / 'textures' / 'brickcraft_model_shade.png')
    meta = gallery_meta(GALLERY)
    for slug, record in picks.items():
        model, meshes, icons = convert(slug, record)
        m = meta.get(record, {})
        model['title'] = TITLES.get(slug, slug.replace('_', ' ').title())
        model['pieces'] = m.get('brick_count') or len(model['parts'])
        model['prompt'] = (m.get('prompt') or '')[:160]
        write_model(model, meshes, MOD / 'parts', MOD / 'data' / f'{slug}.json', icons=icons)
        print(describe(model, meshes), flush=True)
    # Earlier versions kept model files in the media every player gets on joining.
    for old in list((MOD / 'models').glob('brickcraft_model_*')) + list((MOD / 'textures').glob('brickcraft_model_*')):
        old.unlink()
    if (MOD / 'models').exists() and not any((MOD / 'models').iterdir()): (MOD / 'models').rmdir()
    if (MOD / 'catalog.lua').exists(): (MOD / 'catalog.lua').unlink()


def slug_for(title, record, taken):
    words = re.findall(r'[a-z0-9]+', title.lower())
    base = '_'.join(words[:3])[:24] or 'model_' + record.rsplit('-', 1)[-1][:8]
    if base[0].isdigit(): base = 'model_' + base
    slug, n = base, 2
    while slug in taken:
        slug, n = f'{base}_{n}', n + 1
    return slug


def world_dir(world=None):
    return Path(world or os.environ.get('BRICKCRAFT_WORLD') or ROOT / 'worlds' / 'workshop')


def version_of(record, gallery=GALLERY):
    """Which version of a build: a hash of its mesh, so a rebuilt model counts as new."""
    return hashlib.sha256((gallery / 'models' / f'{record}.glb').read_bytes()).hexdigest()[:16]


def sent_entry(record, inbox):
    """The inbox folder and model.json of a record sent before, if any."""
    for d in inbox.glob('*/model.json'):
        try:
            data = json.loads(d.read_text())
        except ValueError:
            continue
        if data.get('record') == record:
            return d.parent, data
    return None, None


def report(data, world, version):
    return {'slug': data['slug'], 'title': data.get('title'), 'parts': len(data.get('parts') or []),
            'world': str(world), 'version': data.get('version'), 'sent_at': data.get('sent_at'),
            'current': data.get('version') == version}


def status(record, world=None, gallery=GALLERY):
    """Whether a record is in the world's inbox, and whether it's the gallery's current version."""
    world = world_dir(world)
    _, data = sent_entry(record, world / 'brickwright_models')
    if not data:
        return {'sent': False, 'world': str(world)}
    return {'sent': True, **report(data, world, version_of(record, gallery))}


def send(record, title=None, world=None, gallery=GALLERY):
    """Puts one model in the world's inbox for the running game. Returns slug and title.

    The same version sent again (and not renamed) isn't converted again: the report says
    `already`."""
    world = world_dir(world)
    inbox = world / 'brickwright_models'
    meta = gallery_meta(gallery).get(record, {})
    version = version_of(record, gallery)
    folder, before = sent_entry(record, inbox)
    if before and before.get('version') == version and (not title or title[:40].strip() == before.get('title')):
        return {'sent': True, 'already': True, **report(before, world, version)}
    title = title or (before or {}).get('title') or ((meta.get('prompt') or '').strip().splitlines() or [record])[0]
    title = title[:40].strip() or record
    if folder:  # sent before: replace it
        slug = folder.name
    else:
        taken = {p.stem for p in (MOD / 'data').glob('*.json')} | {d.name for d in inbox.glob('*') if d.is_dir()}
        slug = slug_for(title, record, taken)
    model, meshes, icons = convert(slug, record, gallery)
    model['title'] = title
    model['pieces'] = meta.get('brick_count') or len(model['parts'])
    model['prompt'] = (meta.get('prompt') or '')[:160]
    model['version'] = version
    model['sent_at'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
    # A fresh name each time: the game can't swap media it has already sent under a name.
    stamp = format(int(time.time() * 10) % 36 ** 6, 'x')
    write_model(model, meshes, inbox / slug, inbox / slug / 'model.json', f'brickcraft_model_{slug}_{stamp}', icons)
    return {'sent': True, 'already': False, **report(model, world, version)}


def main(argv):
    if argv and argv[0] == '--previews':
        shade_ramp(MOD / 'textures' / 'brickcraft_model_shade.png')
        add_previews(argv[2] if argv[1:2] == ['--world'] else None)
        return
    if argv and argv[0] in ('--send', '--status'):
        args = {'record': None, 'title': None, 'world': None, 'gallery': GALLERY}
        rest = argv[1:]
        while rest:
            a = rest.pop(0)
            if a in ('--title', '--world', '--gallery'):
                args[a[2:]] = rest.pop(0)
            else:
                args['record'] = a
        if not args['record']: sys.exit(f'{argv[0]} needs a BrickWright record id')
        gallery = Path(args['gallery'])
        result = (send(args['record'], args['title'], args['world'], gallery) if argv[0] == '--send'
                  else status(args['record'], args['world'], gallery))
        print(json.dumps(result, ensure_ascii=False))
        return
    import_samples(dict(a.split('=', 1) for a in argv) if argv else SAMPLES)


if __name__ == '__main__':
    main(sys.argv[1:])
