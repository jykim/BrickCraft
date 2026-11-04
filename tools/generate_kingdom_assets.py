"""Original Bunny Kingdom palette textures; standard library only."""
import struct
import zlib
from pathlib import Path
OUT = Path(__file__).resolve().parents[1] / 'game/mods/brickcraft_habitat/textures'
def png(name, width, height, pixel):
    raw = b''.join(b'\0' + b''.join(bytes(pixel(x, y)) for x in range(width)) for y in range(height))
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    (OUT / name).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
for name, coat, fur, eyes in [
    ('blue', (45, 126, 224), (242, 239, 226), (30, 38, 52)),
    ('red', (212, 58, 65), (242, 219, 207), (55, 25, 32)),
    ('zombie', (67, 90, 68), (153, 190, 117), (228, 69, 51)),
    ('king', (232, 181, 59), (250, 241, 212), (32, 42, 68)),
]:
    rows = [fur, coat, tuple(max(0, c - 45) for c in coat), eyes, fur, (238, 160, 174), (208, 112, 137), fur]
    png(f'brickcraft_habitat_kingdom_{name}.png', 16, 128, lambda x, y: rows[y // 16] + (255,))
def berries(x, y):
    berry = any((x-a)**2 + (y-b)**2 < 5 for a, b in [(4, 5), (11, 9), (6, 12), (12, 3)])
    return (202, 59, 106, 255) if berry else (57 + (x+y)%3*9, 120 + (x*y)%4*6, 58, 255)
png('brickcraft_habitat_berries.png', 16, 16, berries)
print('Generated four bunny uniforms and berry texture.')
def weapon_pixel(kind, x, y):
    transparent = (0, 0, 0, 0)
    if kind == 'carrot_lance':
        if abs(x - (27-y)) < 2 and y > 8: return (226, 126, 46, 255)
        if 20 < x < 29 and 2 < y < 12 and (x+y)%3: return (79, 162, 74, 255)
    elif kind == 'radish_hammer':
        if 14 < x < 18 and 10 < y < 30: return (137, 93, 59, 255)
        if ((x-16)/11)**2 + ((y-10)/7)**2 < 1: return (236, 107, 151, 255)
        if 13 < x < 20 and y < 5: return (76, 156, 77, 255)
    elif kind == 'berry_sling':
        if (14 < x < 18 and 15 < y < 30) or (y < 18 and abs(abs(x-16)-(18-y)*.6) < 2): return (151, 103, 64, 255)
        if 8 < x < 24 and 5 < y < 8: return (224, 195, 150, 255)
        if (x-16)**2+(y-7)**2 < 10: return (205, 57, 106, 255)
    elif kind == 'acorn_launcher':
        if 7 < x < 25 and 12 < y < 25: return (147, 100, 57, 255)
        if 11 < x < 20 and 24 < y < 31: return (88, 61, 43, 255)
        if (x-16)**2+(y-9)**2 < 45: return (193, 141, 75, 255)
        if 8 < x < 24 and 5 < y < 9: return (98, 71, 43, 255)
    elif kind == 'cabbage_shield':
        if ((x-16)/13)**2+((y-16)/14)**2 < 1:
            return (89, 158, 70, 255) if (x-y)%7 < 2 else (139, 192, 89, 255)
    return transparent
for kind in ['carrot_lance', 'radish_hammer', 'berry_sling', 'acorn_launcher', 'cabbage_shield']:
    png(f'brickcraft_habitat_weapon_{kind}.png', 32, 32, lambda x, y: weapon_pixel(kind, x, y))
print('Generated five bunny weapon icons.')
