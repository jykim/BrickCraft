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
    # Brick Knight, war mode's practice target: armor gray, with a steel helmet.
    knight=dict(shirt=(170,176,188),pants=(90,94,104),hair=(140,146,158)),
    # Your blue knights, and the Red Army: Red Knights and their gold-helmeted Red Commander.
    blueknight=dict(shirt=(84,168,240),pants=(48,76,110),hair=(206,222,240)),
    redknight=dict(shirt=(214,52,44),pants=(118,32,30),hair=(150,40,36)),
    redboss=dict(shirt=(226,40,40),pants=(80,18,18),hair=(249,193,65)),
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
# Parts fitted to a cart, drawn in the cart's frame (its front is +z): a train motor between
# the wheels, and a battery box at the back of the deck with a switch light on top
# (textures: body, light; the light's texture shows the switch).
m=Mesh(); m.mat('motor')
m.box(-.16,-.31,-.2,.16,-.12,.2)
m.save('brickcraft_train_motor.obj','train motor',flip_x=True)
m=Mesh(); m.mat('body')
m.box(-.28,-.02,-.44,.28,.26,-.12)
m.mat('light')
m.box(.08,.26,-.36,.2,.31,-.2)
m.box(-.2,.26,-.32,-.04,.29,-.24)  # switch lever
m.save('brickcraft_battery_box.obj','battery box',flip_x=True)
# War mode (brickcraft_war). Item icons are 32 x 32 pixel art; the sword runs corner to corner.
def sword(x,y):
    t,d=(x-y+31)/2,abs(x+y-31)  # along the blade from the bottom-left corner, and off it
    if 11<=t<=30 and d<=2: return (236,240,246,255) if x+y<31 else (178,186,198,255)
    if 9<=t<11 and d<=6: return (249,193,65,255)
    if 3<=t<9 and d<=1: return (118,80,52,255)
    if t<3 and d<=2: return (249,193,65,255)
    return (0,0,0,0)
png('brickcraft_sword.png',32,32,sword)
def boot(x,y):
    if 26<=y<=28 and 8<=x<=28: return (54,40,34,255)  # sole
    if (10<=x<=19 and 4<=y<26) or (10<=x<=28 and 17<=y<26):
        return (196,92,60,255) if y>7 else (226,128,92,255)
    return (0,0,0,0)
png('brickcraft_boot.png',32,32,boot)
def cannon_icon(x,y):
    if (x-11)**2+(y-22)**2<=36: return (36,38,44,255) if (x-11)**2+(y-22)**2>=9 else (118,80,52,255)
    if 4<=x<=27 and 9<=y<=16: return (70,74,84,255) if y>10 else (110,116,128,255)
    if 26<=x<=29 and 8<=y<=17: return (52,56,64,255)
    if 6<=x<=24 and 15<=y<=20: return (118,80,52,255)
    return (0,0,0,0)
png('brickcraft_cannon.png',32,32,cannon_icon)
def knight_icon(x,y):  # a shield with a coral cross
    inside=4<=x<=27 and 3<=y<=28 and (y<=17 or abs(x-15.5)<=(28-y)*1.1)
    if not inside: return (0,0,0,0)
    if 13<=x<=18 or 11<=y<=15: return (235,93,72,255)
    return (170,176,188,255)
png('brickcraft_knight.png',32,32,knight_icon)
def bow_icon(x,y):  # a wooden bow drawn corner to corner, its string and an arrow across
    t,d=(x-y+31)/2,(x+y-31)/2  # along the bow's line, and off it toward the bottom right
    bend=6.5-((t-15.5)**2)/37
    if 2<=t<=29 and abs(-d-bend)<=1.3: return (150,98,58,255) if -d<bend else (118,80,52,255)
    if 3<=t<=28 and abs(d)<=.5: return (238,229,199,255)  # string
    if abs(x-y)<=1 and 6<=x<=27: return (196,160,110,255) if x>9 else (235,93,72,255)  # arrow, coral fletching
    if abs(x-y)<=2 and 25<=x<=28: return (110,116,128,255)  # arrowhead
    return (0,0,0,0)
png('brickcraft_bow.png',32,32,bow_icon)
png('brickcraft_cannonball.png',16,16,lambda x,y:(0,0,0,0) if (x-7.5)**2+(y-7.5)**2>56 else (120,124,134,255) if (x-5)**2+(y-5)**2<5 else (40,42,48,255))
png('brickcraft_smoke.png',16,16,lambda x,y:(235,232,226,max(0,int(230-((x-7.5)**2+(y-7.5)**2)*4.1))))
def ammo(x,y):  # a pile of three cannonballs
    for cx,cy in ((10,21),(21,21),(15.5,12)):
        d=(x-cx)**2+(y-cy)**2
        if d<=30: return (126,130,140,255) if (x-cx+2)**2+(y-cy+2)**2<5 else (40,42,48,255)
    return (0,0,0,0)
png('brickcraft_ammo.png',32,32,ammo)
png('brickcraft_cannon_metal.png',16,16,lambda x,y:(64,68,78,255))
# A cannon on a wooden carriage, barrel along +z, standing at y 0 (textures: wood, metal).
m=Mesh(); m.mat('wood')
m.box(-.22,.1,-.36,.22,.28,.3)
for x in (-.3,.3):
    for z in (-.22,.18): m.box(x-.05,0,z-.12,x+.05,.24,z+.12)
m.mat('metal')
m.box(-.11,.26,-.34,.11,.48,.5)
m.box(-.14,.23,.42,.14,.51,.52)  # muzzle ring
m.box(-.05,.32,-.42,.05,.42,-.34)  # cascabel knob
m.box(-.34,.06,-.17,.34,.1,.13)  # axles
m.save('brickcraft_cannon.obj','war cannon')
# Technic: axles and gears are drawn around the y axis (a turning copy spins about its own
# y axis; pieces lie any way by facedir). Every gear has its axle through it. Gears have
# their real size: a cell is 2 studs and a gear's pitch radius is teeth/16 studs, so
# teeth/32 cells (8: 1/4, 24: 3/4, 40: 1 1/4); a tooth sits at angle 0 (and every quarter
# turn, as 8, 24 and 40 divide by 4). Machine blocks face +z.
def axle(m):
    m.box(-.05,-.5,-.13,.05,.5,.13); m.box(-.13,-.5,-.05,.13,.5,.05)
def gear(name,teeth):
    m=Mesh(); axle(m)
    r=teeth/32; root,tip=r-.05,r+.05
    pts=[]
    for i in range(teeth):
        a=2*math.pi*i/teeth; w=math.pi/teeth
        for da,rr in ((-w*.5,root),(-w*.25,tip),(w*.25,tip),(w*.5,root)):
            pts.append((rr*math.cos(a+da),rr*math.sin(a+da)))
    y0,y1=-.08,.08
    for (xa,za),(xb,zb) in zip(pts,pts[1:]+pts[:1]):
        m.poly([(0,y1,0),(xb,y1,zb),(xa,y1,za)]); m.poly([(0,y0,0),(xa,y0,za),(xb,y0,zb)])
        m.poly([(xb,y0,zb),(xb,y1,zb),(xa,y1,za),(xa,y0,za)])
    m.save(name,f'gear, {teeth} teeth')
m=Mesh(); axle(m); m.save('brickcraft_axle.obj','technic axle')
gear('brickcraft_gear8.obj',8)
gear('brickcraft_gear24.obj',24)
gear('brickcraft_gear40.obj',40)
# Machine blocks (textures: body, then the battery's switch light or the motor's axle stub).
m=Mesh(); m.mat('body')
m.box(-.3,-.5,-.34,.3,.1,.3)
for x in (-.15,.15):
    for z in (-.17,.13): m.box(x-.1,.1,z-.1,x+.1,.18,z+.1)
m.mat('light'); m.box(-.22,.1,.22,-.06,.16,.3)
m.save('brickcraft_battery_node.obj','battery box on the ground')
m=Mesh(); m.mat('body')
m.box(-.32,-.5,-.4,.32,.14,.3); m.box(-.22,.14,-.3,.22,.24,.2)
m.mat('stub'); m.box(-.05,-.18,.3,.05,.06,.5); m.box(-.12,-.11,.3,.12,-.01,.5)
m.save('brickcraft_motor_node.obj','train motor on the ground')
# A locomotive's drive wheel (radius 1/2, about y like a gear; scaled down on the cart),
# and a passenger car's cabin on a cart deck: corner posts, benches and a roof (textures:
# body, roof). The cabin is drawn in the cart's frame, front +z.
m=Mesh(); N=20
rim=[(.5*math.cos(2*math.pi*i/N),.5*math.sin(2*math.pi*i/N)) for i in range(N)]
for (xa,za),(xb,zb) in zip(rim,rim[1:]+rim[:1]):
    m.poly([(0,.06,0),(xb,.06,zb),(xa,.06,za)]); m.poly([(0,-.06,0),(xa,-.06,za),(xb,-.06,zb)])
    m.poly([(xb,-.06,zb),(xb,.06,zb),(xa,.06,za),(xa,-.06,za)])
m.box(-.05,-.1,-.45,.05,.1,.45)  # a spoke shows it turning
m.save('brickcraft_wheel.obj','drive wheel')
m=Mesh(); m.mat('body')
for x in (-.36,.36):
    for z in (-.42,.42): m.box(x-.04,-.02,z-.04,x+.04,.95,z+.04)
for z in (-.24,.24): m.box(-.3,-.02,z-.08,.3,.16,z+.08)
m.box(-.38,-.02,-.46,.38,.3,-.4); m.box(-.38,-.02,.4,.38,.3,.46)  # end walls
m.mat('roof'); m.box(-.44,.95,-.5,.44,1.03,.5)
m.save('brickcraft_coach.obj','passenger car cabin',flip_x=True)
# Ramps: track rising one level over one cell toward +z (the centerline runs from (z -1/2,
# y 0) to (z 1/2, y 1), so rails sit 0.32 below it as on flat track). Ties step up under
# the rails; a chain lift has a dark chain between them (textures: tie, rail, chain).
def incline(m,x0,x1,below,thick):
    pts=[]
    for z in (-.5,.5):
        top=z+.5-below
        pts.append([(x0,top,z),(x1,top,z),(x1,top-thick,z),(x0,top-thick,z)])
    (a0,a1,a2,a3),(b0,b1,b2,b3)=pts
    m.poly([a0,b0,b1,a1]); m.poly([a3,a2,b2,b3])          # top, bottom
    m.poly([a0,a3,b3,b0]); m.poly([a1,b1,b2,a2])          # sides
    m.poly([a0,a1,a2,a3]); m.poly([b0,b3,b2,b1])          # ends
def ramp(name,chain):
    m=Mesh(); m.mat('tie')
    for z in (-.375,-.125,.125,.375):
        top=z+.5-.42
        m.box(-.42,top-.08,z-.06,.42,top,z+.06)
    m.mat('rail')
    for x in (-.25,.25): incline(m,x-.04,x+.04,.32,.1)
    if chain:
        m.mat('chain'); incline(m,-.1,.1,.39,.04)
    m.save(name,'track ramp'+(' with chain lift' if chain else ''))
ramp('brickcraft_track_ramp.obj',False)
ramp('brickcraft_track_lift.obj',True)
print('Generated 38 textures, 3 block person meshes, 5 brick meshes, 5 train meshes and a cannon')
