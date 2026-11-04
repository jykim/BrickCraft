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
import math
def separator_pixels(size=64, ss=4):
    """Ray-marched brick separator: ribbed flat handle, raised head with an axle pin and two studs."""
    # Side profile (x along the tool, y up), extruded across z.
    P = [(0, .1), (.7, 0), (10.3, 0), (10.8, -.55), (14.0, -.55), (14.4, .5), (14.4, 1.05), (13.9, 1.5),
         (12.6, 1.5), (12.6, 1.95), (11.3, 1.95), (9.0, .62), (0, .3)]
    HW = 1.6
    def poly(px, py):
        d = (px - P[0][0]) ** 2 + (py - P[0][1]) ** 2; s = 1
        j = len(P) - 1
        for i in range(len(P)):
            (ax, ay), (bx, by) = P[i], P[j]
            ex, ey = ax - bx, ay - by; wx, wy = px - bx, py - by
            t = max(0, min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
            d = min(d, (wx - ex * t) ** 2 + (wy - ey * t) ** 2)
            c1, c2, c3 = py >= by, py < ay, ex * wy > ey * wx
            if (c1 and c2 and c3) or (not c1 and not c2 and not c3): s = -s
            j = i
        return s * math.sqrt(d)
    def body(x, y, z):
        r = .07
        dx = poly(x, y) + r
        dz = abs(z) - HW + r
        d = min(max(dx, dz), 0) + math.hypot(max(dx, 0), max(dz, 0)) - r
        # Rounded corners at the thin tip, seen from above.
        if x < .8:
            cx, cz = .8 - x, abs(z) - (HW - .8)
            if cz > 0: d = max(d, math.hypot(cx, cz) - .8)
        return d
    def capsule_z(x, y, z, cx, cy, half, rad):
        zz = max(abs(z) - half, 0)
        return math.sqrt((x - cx) ** 2 + (y - cy) ** 2 + zz * zz) - rad
    ribs = [1.9 + i * .88 for i in range(8)]
    def ytop(x): return .3 + .32 * x / 9
    def cyl_y(x, y, z, cx, cz, rad, y0, y1, rr=.05):
        dr = math.hypot(x - cx, z - cz) - rad + rr
        dy = abs(y - (y0 + y1) / 2) - (y1 - y0) / 2 + rr
        return min(max(dr, dy), 0) + math.hypot(max(dr, 0), max(dy, 0)) - rr
    def box(x, y, z, cx, cy, cz, hx, hy, hz, rr=.03):
        qx, qy, qz = abs(x - cx) - hx + rr, abs(y - cy) - hy + rr, abs(z - cz) - hz + rr
        return math.sqrt(max(qx, 0) ** 2 + max(qy, 0) ** 2 + max(qz, 0) ** 2) + min(max(qx, qy, qz), 0) - rr
    def logo(x, z):  # shallow raised frame near the tip
        o = max(abs(x - 1.0) - .55, abs(z) - 1.05)
        return abs(o) - .06
    def sdf(x, y, z):
        d = body(x, y, z)
        if x < 9.2 and y < 1:
            for cx in ribs:
                if abs(x - cx) < .4:
                    d = min(d, capsule_z(x, y, z, cx, ytop(cx) - .02, 1.05, .12))
            if x < 1.8:
                l = logo(x, z); h = y - ytop(x) - .04
                d = min(d, max(l, h, -(y - ytop(x) + .1)))
        if x > 12.4:
            for cz in (-.8, .8):
                d = min(d, cyl_y(x, y, z, 13.25, cz, .52, 1.3, 1.92))
        if 11 < x < 12.6 and y > 1.5:
            d = min(d, box(x, y, z, 11.9, 2.5, 0, .36, .6, .11), box(x, y, z, 11.9, 2.5, 0, .11, .6, .36))
        return d
    def normal(x, y, z):
        e = .004
        return norm((sdf(x + e, y, z) - sdf(x - e, y, z), sdf(x, y + e, z) - sdf(x, y - e, z), sdf(x, y, z + e) - sdf(x, y, z - e)))
    def norm(v):
        l = math.sqrt(sum(c * c for c in v)) or 1
        return tuple(c / l for c in v)
    def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    def dot(a, b): return sum(p * q for p, q in zip(a, b))
    # Camera: look down at the tool from its right side, then turn the image so it runs corner to corner.
    yaw, pitch = math.radians(5), math.radians(70)
    fwd = norm((-math.cos(pitch) * math.sin(yaw) * -1, -math.sin(pitch), -math.cos(pitch) * math.cos(yaw)))
    right = norm(cross(fwd, (0, 1, 0))); up = cross(right, fwd)
    ang = math.radians(40)
    centre = (7.2, .7, 0); span = 13.4
    light = norm((.35, .85, .75)); half = norm(tuple(l - f for l, f in zip(light, fwd)))
    base = (247, 142, 34)
    N = size * ss
    acc = [[[0, 0, 0, 0] for _ in range(size)] for _ in range(size)]
    for j in range(N):
        for i in range(N):
            u = (i + .5) / N - .5; v = .5 - (j + .5) / N
            uu = (u * math.cos(ang) + v * math.sin(ang)) * span
            vv = (-u * math.sin(ang) + v * math.cos(ang)) * span
            o = tuple(c + uu * r + vv * w - 12 * f for c, r, w, f in zip(centre, right, up, fwd))
            t = 0; hit = False
            for _ in range(90):
                p = tuple(oc + t * f for oc, f in zip(o, fwd))
                d = sdf(*p)
                if d < .002: hit = True; break
                t += d
                if t > 24: break
            if not hit: continue
            n = normal(*p)
            dif = max(dot(n, light), 0)
            spec = max(dot(n, half), 0) ** 28 * .35
            rim = (1 - max(dot(n, tuple(-c for c in fwd)), 0)) ** 3 * .25
            k = .4 + .7 * dif - rim
            col = [min(255, c * k + 255 * spec) for c in base]
            a = acc[j // ss][i // ss]
            for c in range(3): a[c] += col[c]
            a[3] += 1
    out = []
    for row in acc:
        r = []
        for a in row:
            if a[3] * 2 < ss * ss: r.append((0, 0, 0, 0))
            else: r.append(tuple(int(a[c] / a[3]) for c in range(3)) + (255,))
        out.append(r)
    # A darker one-pixel outline keeps the shape readable on any background.
    w = size
    res = [list(r) for r in out]
    for y in range(w):
        for x in range(w):
            if out[y][x][3]: continue
            nb = [out[yy][xx] for yy, xx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)) if 0 <= yy < w and 0 <= xx < w and out[yy][xx][3]]
            if nb: res[y][x] = (120, 56, 10, 255)
    return res
_sep=separator_pixels()
png('brickcraft_separator.png',64,64,lambda x,y:_sep[y][x])
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
    def save(self,name,title,flip_x=False,scale=1):
        # The engine's OBJ loader negates x; flip_x writes it pre-negated so the mesh lands
        # where it is drawn here (meshes not symmetric in x need it). scale writes it bigger
        # (10: engine units, for an entity drawn at visual_size 1).
        k=-1 if flip_x else 1
        lines=['# Original BrickCraft '+title]+['v %g %g %g'%(k*x*scale,y*scale,z*scale) for x,y,z in self.v]+['vt %g %g'%p for p in self.vt]
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
def canopy(x,y):  # the Red Commander's shield roof seen from above: 2x2 red shields, gold rims and bosses
    u,v=x%16,y%16
    if u in (0,15) or v in (0,15): return (120,30,26,255)  # the gap between shields
    if u in (1,14) or v in (1,14): return (222,176,64,255)  # gold rim
    if (u-7.5)**2+(v-7.5)**2<=5: return (246,214,120,255) if (u-7)**2+(v-7)**2<=1 else (206,160,52,255)  # boss
    return (196,44,36,255) if (u+v)%7 else (176,38,32,255)
png('brickcraft_canopy.png',32,32,canopy)
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
# Kart racing (brickcraft_kart). A go-kart, front +z, wheels on the ground at y 0
# (textures: wheel, body in the racer's color, dark trim): a low floor, side pods, a nose
# with a bumper, a seat back, a steering wheel and a rear wing over the engine.
m=Mesh(); m.mat('wheel')
for x in (-.4,.4):
    for z,r in ((-.46,.17),(.46,.15)): m.box(x-.08,0,z-r,x+.08,2*r,z+r)
m.mat('body')
m.box(-.3,.08,-.6,.3,.18,.66)                                    # floor
for x in (-1,1): m.box(x*.26-.06,.18,-.36,x*.26+.06,.4,.28)        # side pods
m.box(-.2,.14,.5,.2,.34,.78)                                     # nose
m.box(-.22,.4,-.66,.22,.46,-.54)                                 # wing
m.mat('trim')
m.box(-.42,.08,.74,.42,.18,.84)                                  # bumper
m.box(-.2,.18,-.5,.2,.7,-.42)                                    # seat back
m.box(-.03,.18,.2,.03,.5,.26); m.box(-.12,.46,.18,.12,.56,.24)   # steering column and wheel
m.box(-.16,.18,-.66,.16,.36,-.5)                                 # engine
for x in (-.2,.2): m.box(x-.02,.36,-.62,x+.02,.4,-.58)            # wing posts
# Drawn at visual_size 1 (so written 10 times bigger): what's attached to an entity is drawn
# in its scale, and the riders on a kart must stay their own size.
m.save('brickcraft_kart.obj','go-kart',flip_x=True,scale=10)
# Asphalt with darker studs; a checkered start line; a boost pad's chevrons pointing +z
# (up the texture); a banana peel lying open (spins you out) and a bunch (to pick up).
png('brickcraft_kart_road.png',32,32,lambda x,y:(84,88,96,255) if (x%16-8)**2+(y%16-8)**2<12 else (70,73,80,255) if x not in (0,31) and y not in (0,31) else (62,64,70,255))
png('brickcraft_kart_check.png',32,32,lambda x,y:(240,240,240,255) if (x//8+y//8)%2 else (34,36,42,255))
png('brickcraft_kart_boost.png',32,32,lambda x,y:(255,226,92,255) if abs(x-15.5)<9 and 0<=((y+abs(x-15.5))%12)<5 else (245,135,44,255))
def banana_at(x,y,cx,cy,r0,r1):  # a crescent: a ring's lower-left quarter
    r=((x-cx)**2+(y-cy)**2)**.5
    return r0<=r<=r1 and x<=cx and y>=cy
def peel(x,y):  # a peel lying open: a stalk, a middle and three spotted flaps splayed out
    import math
    if 11<=x<=13 and 3<=y<=8: return (118,80,52,255)  # stalk
    for ex,ey in ((3,19),(12,22),(21,19)):
        # distance from the flap's line, from the middle (12, 10) to its tip
        vx,vy,px,py=ex-12,ey-10,x-12,y-10
        t=max(0,min(1,(px*vx+py*vy)/(vx*vx+vy*vy)))
        d=math.hypot(px-vx*t,py-vy*t)
        if d<=2.6*(1-t)+1.2:
            return (140,96,40,255) if (x*7+y*5)%13==0 else (244,210,62,255) if d<1.6 else (214,170,30,255)
    return (0,0,0,0)
png('brickcraft_kart_banana.png',24,24,peel)
def bunch(x,y):  # three ripe bananas on one green stem
    if 15<=x<=18 and 1<=y<=6: return (88,171,65,255)
    for cx,cy in ((21,3),(18,6),(24,6)):
        if banana_at(x,y,cx,cy,9,13):
            return (118,80,52,255) if y>=cy+12 and x<=cx-9 else (255,226,70,255) if ((x-cx)**2+(y-cy)**2)**.5<11.5 else (222,178,32,255)
    return (0,0,0,0)
png('brickcraft_kart_bunch.png',24,24,bunch)
print('Generated 43 textures, 3 block person meshes, 5 brick meshes, 5 train meshes, a cannon and a kart')
