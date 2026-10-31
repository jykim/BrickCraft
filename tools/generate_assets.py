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
palette=[(245,196,134,255),(74,161,217,255),(48,76,110,255),(35,38,48,255)]
png('brickcraft_person.png',16,64,lambda x,y:palette[min(3,y//16)])
# A deliberately generic original block person; no copied character mesh.
vertices=[];uvs=[];faces=[]
def box(x0,y0,z0,x1,y1,z1,color):
    offset=len(vertices)
    vertices.extend([(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)])
    uvs.append((.5,1-(color+.5)/4)); t=len(uvs)
    for f in [(1,4,3,2),(5,6,7,8),(1,5,8,4),(2,3,7,6),(4,8,7,3),(1,2,6,5)]:
        faces.append('f '+' '.join(f'{offset+i}/{t}' for i in f))
box(-.25,1.22,-.22,.25,1.72,.22,0)
box(-.3,.58,-.18,.3,1.2,.18,1)
box(-.5,.58,-.15,-.31,1.16,.15,0);box(.31,.58,-.15,.5,1.16,.15,0)
box(-.27,.06,-.17,-.02,.58,.17,2);box(.02,.06,-.17,.27,.58,.17,2)
# Eyes on the front (negative Z).
box(-.15,1.49,-.228,-.08,1.56,-.22,3);box(.08,1.49,-.228,.15,1.56,-.22,3)
(root/'models/brickcraft_person.obj').write_text('\n'.join(['# Original BrickCraft block person']+['v %g %g %g'%p for p in vertices]+['vt %g %g'%p for p in uvs]+faces)+'\n')
print('Generated 12 textures and original block person mesh')
