"""Original geometric assets, generated with Python's standard library only."""
import struct, zlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'game/mods/brickcraft'
def png(name,w,h,pixel):
    raw=b''.join(b'\0'+b''.join(bytes(pixel(x,y)) for x in range(w)) for y in range(h))
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    (root/'textures'/name).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
colors=dict(coral=(235,93,72),gold=(249,193,65),mint=(74,183,147),sky=(74,161,217),violet=(151,116,203),cream=(238,229,199),navy=(48,76,110),rose=(229,131,165))
for name,rgb in colors.items():
    png('brickcraft_'+name+'.png',32,32,lambda x,y,c=rgb: tuple(max(0,min(255,v+(-16 if x==31 or y==31 else 8 if x==0 or y==0 else 0))) for v in c)+(255,))
png('brickcraft_baseplate.png',32,32,lambda x,y:(88,126,116,255) if (x%16-8)**2+(y%16-8)**2<12 else (70,103,98,255))
png('brickcraft_separator.png',32,32,lambda x,y:(245,135,44,255) if (7<=x<=24 and 4<=y<=10) or (12<=x<=20 and 10<=y<=28) else (0,0,0,0))
png('brickcraft_hand.png',32,32,lambda x,y:(245,196,134,255) if 9<=x<=24 and 7<=y<=29 else (0,0,0,0))
# Landscape: flat brick-toy colors with a stud dot so hills read as bricks too.
def stud(base,light):
    return lambda x,y:light if (x%16-8)**2+(y%16-8)**2<12 else base
png('brickcraft_grass.png',32,32,stud((96,178,84,255),(122,199,104,255)))
png('brickcraft_grass_side.png',32,32,lambda x,y:(96,178,84,255) if y<10 else (150,104,70,255) if y!=31 else (128,88,60,255))
png('brickcraft_dirt.png',32,32,lambda x,y:(150,104,70,255) if x!=31 and y!=31 else (128,88,60,255))
png('brickcraft_trunk.png',32,32,lambda x,y:(118,80,52,255) if x%8 else (98,66,44,255))
png('brickcraft_trunk_top.png',32,32,lambda x,y:(150,108,70,255) if (x-15.5)**2+(y-15.5)**2<100 else (118,80,52,255))
png('brickcraft_leaves.png',32,32,stud((58,148,82,255),(80,170,100,255)))
# Block-person styles. Texture rows: skin, shirt, pants, eyes, hair (8 rows, room to grow).
ROWS=8
styles=dict(
    builder=dict(shirt=(74,161,217),pants=(48,76,110),hair=None),
    dad=dict(shirt=(48,76,110),pants=(70,74,84),hair=(62,44,32)),
    daughter=dict(shirt=(229,131,165),pants=(151,116,203),hair=(110,66,40)),
    explorer=dict(shirt=(74,183,147),pants=(238,229,199),hair=(232,190,92)),
)
for name,st in styles.items():
    rows=[(245,196,134),st['shirt'],st['pants'],(35,38,48),st['hair'] or (35,38,48)]
    rows+= [rows[0]]*(ROWS-len(rows))
    fname='brickcraft_person.png' if name=='builder' else f'brickcraft_person_{name}.png'
    png(fname,16,16*ROWS,lambda x,y,r=rows:r[y//16]+(255,))
# A deliberately generic original block person; no copied character mesh.
def person(path,hair):
    vertices=[];uvs=[];faces=[]
    def box(x0,y0,z0,x1,y1,z1,color):
        offset=len(vertices)
        vertices.extend([(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)])
        uvs.append((.5,1-(color+.5)/ROWS)); t=len(uvs)
        for f in [(1,4,3,2),(5,6,7,8),(1,5,8,4),(2,3,7,6),(4,8,7,3),(1,2,6,5)]:
            faces.append('f '+' '.join(f'{offset+i}/{t}' for i in f))
    box(-.25,1.22,-.22,.25,1.72,.22,0)
    box(-.3,.58,-.18,.3,1.2,.18,1)
    box(-.5,.58,-.15,-.31,1.16,.15,0);box(.31,.58,-.15,.5,1.16,.15,0)
    box(-.27,.06,-.17,-.02,.58,.17,2);box(.02,.06,-.17,.27,.58,.17,2)
    # Eyes on the front (negative Z).
    box(-.15,1.49,-.228,-.08,1.56,-.22,3);box(.08,1.49,-.228,.15,1.56,-.22,3)
    if hair:
        box(-.27,1.64,-.24,.27,1.78,.24,4)          # cap
        box(-.27,1.4,.16,.27,1.72,.25,4)            # back
        box(-.27,1.58,-.24,.27,1.66,-.2,4)          # fringe
    if hair=='long':
        box(-.27,.95,.16,.27,1.4,.25,4)             # long back hair
        box(-.3,1.05,-.1,-.25,1.7,.24,4);box(.25,1.05,-.1,.3,1.7,.24,4)  # sides
    (root/'models'/path).write_text('\n'.join(['# Original BrickCraft block person']+['v %g %g %g'%p for p in vertices]+['vt %g %g'%p for p in uvs]+faces)+'\n')
person('brickcraft_person.obj',None)
person('brickcraft_person_short.obj','short')
person('brickcraft_person_long.obj','long')
print('Generated 21 textures and 3 original block person meshes')
