#!/usr/bin/env python3
"""Bring BrickWright builds into BrickCraft as display models.

Reads a build's mesh (`build.glb`, real LDraw parts, metres) from the BrickWright gallery
and writes one mesh per model to game/mods/brickcraft_models/:

  models/brickcraft_model_<slug>.glb   all parts merged, coloured through a palette texture
  textures/brickcraft_model_<slug>.png one square per colour in the build
  catalog.lua                          slug, title, source, pieces, size in cells

Life-size: the game's cell is 2 x 2 studs (16 mm), so 1 cell = 16 mm on every axis and the
model keeps its real proportions (a brick is 9.6 mm, so 0.6 of a cell tall). The game draws
its own bricks a full cell tall, so a model reads a little flatter than game bricks stacked
the same number of rows.

Python standard library only, like the other tools.

    python3 tools/import_brickwright.py                       # the samples below
    python3 tools/import_brickwright.py <slug>=<record id> ... # others
"""
import json, math, struct, sys, zlib
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'game' / 'mods' / 'brickcraft_models'
GALLERY = Path('/Volumes/990PRO/lifidea/Projects/dev/brickwright/site')
CELL_M = 0.016          # one cell = 2 studs = 16 mm
UNITS = 10 / CELL_M     # Luanti mesh units: 10 per cell
MAX_VERTS = 65535       # 16-bit indices per primitive
MAX_INDICES = 65535     # Luanti's glTF loader also counts corners against this ('too many vertices')

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
    if stride == size * n:
        out = array(code)
        out.frombytes(binary[start:start + a['count'] * stride])
        return out, n
    out = array(code)
    for k in range(a['count']):
        out.extend(struct.unpack_from('<' + code * n, binary, start + k * stride))
    return out, n


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


def png(path, w, h, rgba_rows):
    raw = b''.join(b'\0' + bytes(row) for row in rgba_rows)
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def convert(slug, record):
    js, binary = read_glb(GALLERY / 'models' / f'{record}.glb')
    # Colours: one palette square per material, 8 x 8 px, 4 squares a row.
    colors = []
    for m in js['materials']:
        r, g, b, a = m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])
        colors.append((to_srgb(r), to_srgb(g), to_srgb(b), round(255 * a)))
    cols = 4
    rows_n = (len(colors) + cols - 1) // cols
    tw, th = 8 * cols, 8 * rows_n
    pix = [[0] * (tw * 4) for _ in range(th)]
    uv = []
    for i, c in enumerate(colors):
        cx, cy = i % cols, i // cols
        for y in range(8):
            for x in range(8):
                pix[cy * 8 + y][(cx * 8 + x) * 4:(cx * 8 + x) * 4 + 4] = c
        uv.append(((cx * 8 + 4) / tw, (cy * 8 + 4) / th))

    pos, nor, tex, idx = array('f'), array('f'), array('f'), array('I')
    lo, hi = [math.inf] * 3, [-math.inf] * 3

    def walk(ni, parent):
        n = js['nodes'][ni]
        m = mat_mul(parent, node_matrix(n))
        if 'mesh' in n:
            flip = (m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2])
                    + m[8] * (m[1] * m[6] - m[5] * m[2])) < 0
            for p in js['meshes'][n['mesh']]['primitives']:
                assert p.get('mode', 4) == 4
                P, _ = accessor(js, binary, p['attributes']['POSITION'])
                N, _ = accessor(js, binary, p['attributes']['NORMAL']) if 'NORMAL' in p['attributes'] else (None, 0)
                I, _ = accessor(js, binary, p['indices'])
                u, v = uv[p.get('material', 0)]
                base = len(pos) // 3
                for k in range(0, len(P), 3):
                    x, y, z = P[k], P[k + 1], P[k + 2]
                    wx = m[0] * x + m[4] * y + m[8] * z + m[12]
                    wy = m[1] * x + m[5] * y + m[9] * z + m[13]
                    wz = m[2] * x + m[6] * y + m[10] * z + m[14]
                    pos.extend((wx, wy, wz))
                    for a, val in enumerate((wx, wy, wz)):
                        if val < lo[a]: lo[a] = val
                        if val > hi[a]: hi[a] = val
                    if N is not None:
                        a, b, c = N[k], N[k + 1], N[k + 2]
                        nx = m[0] * a + m[4] * b + m[8] * c
                        ny = m[1] * a + m[5] * b + m[9] * c
                        nz = m[2] * a + m[6] * b + m[10] * c
                        l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
                        nor.extend((nx / l, ny / l, nz / l))
                    else:
                        nor.extend((0, 1, 0))
                    tex.extend((u, v))
                for k in range(0, len(I), 3):
                    a, b, c = I[k] + base, I[k + 1] + base, I[k + 2] + base
                    idx.extend((a, c, b) if flip else (a, b, c))
        for c in n.get('children', []):
            walk(c, m)

    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for ni in js['scenes'][js.get('scene', 0)]['nodes']:
        walk(ni, identity)

    # Centre on x, z; stand on y = 0; metres -> mesh units at life-size.
    cx, cz, by = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, lo[1]
    for k in range(0, len(pos), 3):
        pos[k] = (pos[k] - cx) * UNITS
        pos[k + 1] = (pos[k + 1] - by) * UNITS
        pos[k + 2] = (pos[k + 2] - cz) * UNITS

    # Split into primitives of at most 65535 vertices, re-indexed per chunk.
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
        clo, chi = [math.inf] * 3, [-math.inf] * 3
        for v in corners:
            p3 = pos[3 * v:3 * v + 3]
            P.extend(p3); N.extend(nor[3 * v:3 * v + 3]); T.extend(tex[2 * v:2 * v + 2])
            for a in range(3):
                clo[a] = min(clo[a], p3[a]); chi[a] = max(chi[a], p3[a])
        a0 = len(accessors)
        accessors += [
            {'bufferView': add_view(P.tobytes(), 34962), 'componentType': 5126, 'count': len(corners),
             'type': 'VEC3', 'min': clo, 'max': chi},
            {'bufferView': add_view(N.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC3'},
            {'bufferView': add_view(T.tobytes(), 34962), 'componentType': 5126, 'count': len(corners), 'type': 'VEC2'},
            {'bufferView': add_view(local.tobytes(), 34963), 'componentType': 5123, 'count': len(local), 'type': 'SCALAR'},
        ]
        prims.append({'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                      'indices': a0 + 3, 'material': 0, 'mode': 4})
    while len(out) % 4: out.append(0)
    gltf = {
        'asset': {'version': '2.0', 'generator': 'BrickCraft tools/import_brickwright.py'},
        'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': slug}],
        'meshes': [{'name': slug, 'primitives': prims}],
        'materials': [{'name': 'palette', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                                                    'metallicFactor': 0, 'roughnessFactor': 1}}],
        'samplers': [{'magFilter': 9728, 'minFilter': 9728}],
        'textures': [{'sampler': 0}],
        'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(out)}],
    }
    head = json.dumps(gltf, separators=(',', ':')).encode()
    head += b' ' * (-len(head) % 4)
    glb = (struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(head) + 8 + len(out))
           + struct.pack('<II', len(head), 0x4E4F534A) + head + struct.pack('<II', len(out), 0x004E4942) + bytes(out))
    assert len(glb) < 16_000_000, f'{slug}: {len(glb)} bytes is over the engine limit'
    (MOD / 'models').mkdir(parents=True, exist_ok=True)
    (MOD / 'textures').mkdir(parents=True, exist_ok=True)
    (MOD / 'models' / f'brickcraft_model_{slug}.glb').write_bytes(glb)
    png(MOD / 'textures' / f'brickcraft_model_{slug}.png', tw, th, pix)
    size = [(hi[a] - lo[a]) / CELL_M for a in range(3)]
    return {'slug': slug, 'record': record, 'tris': len(idx) // 3, 'bytes': len(glb),
            'w': round(size[0], 2), 'h': round(size[1], 2), 'd': round(size[2], 2),
            'alpha': any(c[3] < 255 for c in colors), 'prims': len(prims)}


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'


def main(argv):
    picks = dict(a.split('=', 1) for a in argv) if argv else SAMPLES
    meta = {m['id']: m for m in json.loads((GALLERY / 'models.json').read_text())['models']}
    catalog = MOD / 'catalog.lua'
    known = {}
    if catalog.exists() and argv:  # adding to the catalog keeps the models already there
        for line in catalog.read_text().splitlines():
            if line.startswith('  {slug='):
                known[line.split('"')[1]] = line
    for slug, record in picks.items():
        r = convert(slug, record)
        m = meta.get(record, {})
        title = TITLES.get(slug, slug.replace('_', ' ').title())
        known[slug] = (f'  {{slug={lua_str(slug)},title={lua_str(title)},record={lua_str(record)},'
                       f'pieces={m.get("brick_count") or 0},w={r["w"]},h={r["h"]},d={r["d"]},'
                       f'alpha={"true" if r["alpha"] else "false"},prompt={lua_str((m.get("prompt") or "")[:160])}}},')
        print(f'{slug:8} {record}  {r["tris"]:>7} triangles in {r["prims"]} parts, {r["bytes"] / 1e6:.1f} MB, '
              f'{r["w"]:.1f} x {r["d"]:.1f} cells, {r["h"]:.1f} tall', flush=True)
    catalog.write_text('-- Generated by tools/import_brickwright.py: BrickWright builds as display models.\n'
                       '-- w, d, h: life-size footprint and height in cells (1 cell = 16 mm).\n'
                       'return {\n' + '\n'.join(known.values()) + '\n}\n')


if __name__ == '__main__':
    main(sys.argv[1:])
