"""Original geometric assets, generated with Python's standard library only."""
import struct, zlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'game/mods/brickcraft'
def png(name,w,h,pixel):
    raw=b''.join(b'\0'+b''.join(bytes(pixel(x,y)) for x in range(w)) for y in range(h))
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    (root/'textures'/name).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
colors=dict(coral=(235,93,72),gold=(249,193,65),mint=(74,183,147),sky=(74,161,217),violet=(151,116,203),cream=(238,229,199),navy=(48,76,110),rose=(229,131,165),
    # Harvested from the landscape: leaves/grass, trunks, dirt.
    green=(88,171,65),brown=(118,80,52),tan=(196,160,110))
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
    # jms, the AI builder: orange work shirt and a yellow hard-hat-colored cap.
    jms=dict(shirt=(245,135,44),pants=(48,76,110),hair=(249,193,65)),
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
# Brick meshes for shapes a node box cannot draw. Node units: the cell is -0.5..0.5,
# the high/back side faces +z (away from the builder), studs rise 0.5..0.64 into the cell above.
import math
class Mesh:
    def __init__(self): self.v=[];self.vt=[];self.vn=[];self.f=[]
    def poly(self,pts):
        ax,ay,az=pts[0];bx,by,bz=pts[1];cx,cy,cz=pts[2]
        n=((by-ay)*(cz-az)-(bz-az)*(cy-ay),(bz-az)*(cx-ax)-(bx-ax)*(cz-az),(bx-ax)*(cy-ay)-(by-ay)*(cx-ax))
        l=math.sqrt(sum(c*c for c in n)) or 1; n=tuple(c/l for c in n)
        self.vn.append(n); ni=len(self.vn)
        dom=max(range(3),key=lambda i:abs(n[i]))
        idx=[]
        for x,y,z in pts:
            self.v.append((x,y,z))
            self.vt.append({0:(z+.5,y+.5),1:(x+.5,z+.5),2:(x+.5,y+.5)}[dom])
            idx.append(f'{len(self.v)}/{len(self.vt)}/{ni}')
        self.f.append('f '+' '.join(idx))
    def box(self,x0,y0,z0,x1,y1,z1):
        P=lambda x,y,z:(x,y,z)
        self.poly([P(x0,y0,z0),P(x0,y1,z0),P(x1,y1,z0),P(x1,y0,z0)])  # -z
        self.poly([P(x1,y0,z1),P(x1,y1,z1),P(x0,y1,z1),P(x0,y0,z1)])  # +z
        self.poly([P(x0,y0,z1),P(x0,y1,z1),P(x0,y1,z0),P(x0,y0,z0)])  # -x
        self.poly([P(x1,y0,z0),P(x1,y1,z0),P(x1,y1,z1),P(x1,y0,z1)])  # +x
        self.poly([P(x0,y1,z0),P(x0,y1,z1),P(x1,y1,z1),P(x1,y1,z0)])  # top
        self.poly([P(x0,y0,z1),P(x0,y0,z0),P(x1,y0,z0),P(x1,y0,z1)])  # bottom
    def stud(self,x,z): self.box(x-.13,.5,z-.13,x+.13,.64,z+.13)
    # Faces after this draw with the next texture: the engine splits meshes by group (g), not usemtl.
    def mat(self,name): self.f+=['g '+name,'usemtl '+name]
    def prism(self,pts,y0,y1):
        # pts: an outline in (x, z), turned clockwise like Mesh.box's top.
        if sum(xa*zb-xb*za for (xa,za),(xb,zb) in zip(pts,pts[1:]+pts[:1]))>0: pts=list(reversed(pts))
        self.poly([(x,y1,z) for x,z in pts]); self.poly([(x,y0,z) for x,z in reversed(pts)])
        for (xa,za),(xb,zb) in zip(pts,pts[1:]+pts[:1]):
            self.poly([(xb,y0,zb),(xb,y1,zb),(xa,y1,za),(xa,y0,za)])
    def save(self,name,title,flip_x=False):
        # The engine's OBJ loader negates x; flip_x writes it pre-negated so the mesh lands
        # where it is drawn here (meshes not symmetric in x need it).
        k=-1 if flip_x else 1
        lines=['# Original BrickCraft '+title]+['v %g %g %g'%(k*x,y,z) for x,y,z in self.v]+['vt %g %g'%p for p in self.vt]
        lines+=['vn %g %g %g'%(k*x,y,z) for x,y,z in self.vn]+self.f
        (root/'models'/name).write_text('\n'.join(lines)+'\n')
def slope(name,x0,x1,stud_xs,title,inverted=False):
    # Side profile (z,y): flat top over the back stud row, 45-degree face down to a low front lip.
    # Inverted flips it: full top, the 45-degree face underneath rising from a back base.
    m=Mesh(); lip=-.39
    prof=[(-.5,-.5),(.5,-.5),(.5,.5),(0,.5),(-.5,lip)]
    if inverted: prof=[(z,-y) for z,y in reversed(prof)]
    m.poly([(x0,y,z) for z,y in prof])                       # left side
    m.poly([(x1,y,z) for z,y in reversed(prof)])             # right side
    for (za,ya),(zb,yb) in zip(prof,prof[1:]+prof[:1]):     # bottom, back, top, slope, lip
        m.poly([(x1,ya,za),(x1,yb,zb),(x0,yb,zb),(x0,ya,za)])
    for x in stud_xs:
        for z in ((-.25,.25) if inverted else (.25,)): m.stud(x,z)
    m.save(name,title)
slope('brickcraft_slope_2x2.obj',-.5,.5,(-.25,.25),'45-degree slope 2 x 2')
slope('brickcraft_slope_2x1.obj',-.5,0,(-.25,),'45-degree slope 2 x 1')
slope('brickcraft_slope_inv_2x2.obj',-.5,.5,(-.25,.25),'inverted 45-degree slope 2 x 2',inverted=True)
def round_brick(name,cx,cz,r,stud_at,title):
    m=Mesh(); N=24
    ring=[(cx+r*math.cos(2*math.pi*i/N),cz+r*math.sin(2*math.pi*i/N)) for i in range(N)]
    for (xa,za),(xb,zb) in zip(ring,ring[1:]+ring[:1]):
        m.poly([(xa,-.5,za),(xa,.5,za),(xb,.5,zb),(xb,-.5,zb)])
    m.poly([(x,.5,z) for x,z in reversed(ring)]); m.poly([(x,-.5,z) for x,z in ring])
    for x,z in stud_at: m.stud(x,z)
    m.save(name,title)
round_brick('brickcraft_round_2x2.obj',0,0,.49,[(x,z) for x in (-.25,.25) for z in (-.25,.25)],'round brick 2 x 2')
# The 1 x 1 sits in the same quarter cell as the 1 x 1 brick (x and z -0.5..0).
round_brick('brickcraft_round_1x1.obj',-.25,-.25,.24,[(-.25,-.25)],'round brick 1 x 1')
# Train track, one cell long: dark ties under light rails 0.5 apart (tiles: tie, rail).
# The straight runs along z; the curve joins the +z and +x ends around the (+x, +z) corner.
TIE,RAIL=(-.5,-.42),(-.42,-.32)
png('brickcraft_track_tie.png',16,16,lambda x,y:(84,88,96,255))
png('brickcraft_track_rail.png',16,16,lambda x,y:(178,184,192,255))
png('brickcraft_cart_wheel.png',16,16,lambda x,y:(36,38,44,255))
m=Mesh(); m.mat('tie')
for z in (-.375,-.125,.125,.375): m.box(-.42,TIE[0],z-.06,.42,TIE[1],z+.06)
m.mat('rail')
for x in (-.25,.25): m.box(x-.04,RAIL[0],-.5,x+.04,RAIL[1],.5)
m.save('brickcraft_track_straight.obj','train track, straight',flip_x=True)
def arc(r,th): return (.5-r*math.cos(th),.5-r*math.sin(th))
m=Mesh(); m.mat('tie')
for th in (math.pi/12,math.pi/4,5*math.pi/12):
    tx,tz=math.sin(th)*.06,-math.cos(th)*.06
    (ax,az),(bx,bz)=arc(.08,th),arc(.92,th)
    m.prism([(ax-tx,az-tz),(bx-tx,bz-tz),(bx+tx,bz+tz),(ax+tx,az+tz)],*TIE)
m.mat('rail'); N=12
for r in (.25,.75):
    for i in range(N):
        a,b=math.pi/2*i/N,math.pi/2*(i+1)/N
        m.prism([arc(r-.04,a),arc(r+.04,a),arc(r+.04,b),arc(r-.04,b)],*RAIL)
m.save('brickcraft_track_curve.obj','train track, curve',flip_x=True)
# A flatbed cart centered in its track cell, long side along z (textures: wheel, chassis, deck).
m=Mesh(); m.mat('wheel')
for x in (-.25,.25):
    for z in (-.27,.27): m.box(x-.05,-.32,z-.09,x+.05,-.14,z+.09)
m.mat('chassis')
m.box(-.18,-.24,-.42,.18,-.12,.42)
for z in (-.46,.46): m.box(-.1,-.22,z-.04,.1,-.14,z+.04)  # couplers
m.mat('deck')
m.box(-.38,-.12,-.46,.38,-.02,.46)
for x in (-.19,.19):
    for z in (-.23,.23): m.box(x-.1,-.02,z-.1,x+.1,.03,z+.1)
m.save('brickcraft_cart.obj','flatbed train cart',flip_x=True)
# Inventory icons: track from above, the cart from the side.
png('brickcraft_track_item.png',32,32,lambda x,y:(178,184,192,255) if x in (8,9,10,21,22,23) else
    (84,88,96,255) if 3<=x<=28 and y%8 in (3,4,5,6) else (0,0,0,0))
def cart_icon(x,y):
    if any((x-cx)**2+(y-24)**2<=12 for cx in (9,22)): return (36,38,44,255)
    if 3<=x<=28 and 12<=y<=17 or y in (9,10,11) and (6<=x<=11 or 20<=x<=25): return (235,93,72,255)
    if 5<=x<=26 and 18<=y<=21: return (84,88,96,255)
    return (0,0,0,0)
png('brickcraft_cart_item.png',32,32,cart_icon)
print('Generated 27 textures, 3 block person meshes, 5 brick meshes and 3 train meshes')
