"""Original block-style assets for brickcraft_habitat (Bunnyland and future habitats).
Python standard library only. Writes into game/mods/brickcraft_habitat/{models,textures}.

Every animal and skin is a set of boxes on a row texture: each row of the 16 x (16*ROWS)
texture is one flat color and each box picks its row, like the core block person.
A model's front (face) is toward -z, as the core person's is, so entities face their
way with yaw = atan2(-dx, dz) like the war mode's knights.
"""
import struct, zlib, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'game/mods/brickcraft_habitat'
(root/'textures').mkdir(parents=True,exist_ok=True)
(root/'models').mkdir(parents=True,exist_ok=True)
def png(name,w,h,pixel):
    raw=b''.join(b'\0'+b''.join(bytes(pixel(x,y)) for x in range(w)) for y in range(h))
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    (root/'textures'/name).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
ROWS=8
def rows_png(name,rows):
    rows=list(rows)+[rows[0]]*(ROWS-len(rows))
    png(name,16,16*ROWS,lambda x,y:tuple(rows[y//16])+(255,))
class Boxes:
    def __init__(self): self.v=[];self.vt=[];self.f=[]
    def box(self,x0,y0,z0,x1,y1,z1,row):
        o=len(self.v)
        self.v+=[(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]
        self.vt.append((.5,1-(row+.5)/ROWS)); t=len(self.vt)
        for f in [(1,4,3,2),(5,6,7,8),(1,5,8,4),(2,3,7,6),(4,8,7,3),(1,2,6,5)]:
            self.f.append('f '+' '.join(f'{o+i}/{t}' for i in f))
    def pair(self,x0,y0,z0,x1,y1,z1,row):  # mirrored on both sides of x=0
        self.box(x0,y0,z0,x1,y1,z1,row); self.box(-x1,y0,z0,-x0,y1,z1,row)
    def save(self,name,title):
        (root/'models'/name).write_text('\n'.join(['# Original BrickCraft '+title]+['v %g %g %g'%p for p in self.v]+
            ['vt %g %g'%p for p in self.vt]+self.f)+'\n')

# --- Player skins: the core block person (same proportions) with long ears and a tail.
# Rows: 0 fur (face, hands), 1 body, 2 legs, 3 eyes, 4 ear fur, 5 inner ear, 6 nose, 7 tail.
m=Boxes()
m.box(-.25,1.22,-.22,.25,1.72,.22,0)                       # head
m.box(-.3,.58,-.18,.3,1.2,.18,1)                           # body
m.box(-.5,.58,-.15,-.31,1.16,.15,0);m.box(.31,.58,-.15,.5,1.16,.15,0)  # arms
m.box(-.27,.06,-.17,-.02,.58,.17,2);m.box(.02,.06,-.17,.27,.58,.17,2)  # legs
m.pair(.08,1.49,-.228,.15,1.56,-.22,3)                     # eyes
m.box(-.04,1.4,-.235,.04,1.46,-.22,6)                      # nose
m.pair(.06,1.72,-.06,.19,2.28,.06,4)                       # ears
m.pair(.09,1.76,-.075,.16,2.22,-.06,5)                     # inner ears
m.box(-.09,.62,.18,.09,.8,.32,7)                           # tail
m.save('brickcraft_habitat_bunny_person.obj','bunny-eared block person')
SKINS=dict(
    snow =[(244,240,234),(229,131,165),(151,116,203),(35,38,48),(244,240,234),(246,170,190),(236,120,150),(255,255,255)],
    cocoa=[(160,112,76),(238,229,199),(118,80,52),(35,38,48),(160,112,76),(240,180,170),(90,56,40),(238,229,199)],
    gray =[(150,154,162),(74,161,217),(48,76,110),(35,38,48),(150,154,162),(236,170,184),(70,72,80),(230,232,236)],
    rose =[(252,214,226),(151,116,203),(229,131,165),(35,38,48),(252,214,226),(229,131,165),(214,92,130),(255,250,250)],
)
for name,rows in SKINS.items(): rows_png(f'brickcraft_habitat_skin_{name}.png',rows)

# --- Bunny (the creature). Rows: 0 fur, 1 belly and tail, 2 eyes, 3 inner ear, 4 nose.
m=Boxes()
m.box(-.17,.08,-.12,.17,.38,.3,0)          # body
m.box(-.12,.08,-.14,.12,.3,.1,1)           # belly
m.box(-.14,.24,-.38,.14,.5,-.1,0)          # head
m.pair(.09,.4,-.385,.13,.45,-.37,2)        # eyes
m.box(-.03,.32,-.39,.03,.36,-.37,4)        # nose
m.pair(.03,.48,-.28,.11,.8,-.2,0)          # ears
m.pair(.05,.52,-.285,.09,.76,-.275,3)      # inner ears
m.box(-.07,.2,.3,.07,.34,.4,1)             # tail
m.pair(.08,0,-.1,.15,.1,.04,0)             # front paws
m.pair(.1,0,.12,.18,.12,.34,0)             # hind feet
m.save('brickcraft_habitat_bunny.obj','bunny')
rows_png('brickcraft_habitat_bunny.png',[(244,240,234),(255,255,255),(35,38,48),(246,170,190),(236,120,150)])
rows_png('brickcraft_habitat_bunny_brown.png',[(176,128,90),(238,229,199),(35,38,48),(240,180,170),(90,56,40)])
rows_png('brickcraft_habitat_bunny_gray.png',[(150,154,162),(230,232,236),(35,38,48),(236,170,184),(70,72,80)])

# --- Wolf. Rows: 0 fur, 1 belly and muzzle, 2 eyes, 3 nose, 4 dark back.
m=Boxes()
m.box(-.2,.42,-.45,.2,.82,.5,0)            # body
m.box(-.21,.72,-.4,.21,.86,.45,4)          # dark back
m.box(-.17,.62,-.82,.17,.98,-.45,0)        # head
m.box(-.09,.62,-1.08,.09,.78,-.82,1)       # muzzle
m.box(-.04,.74,-1.1,.04,.8,-1.07,3)        # nose
m.pair(.07,.84,-.83,.13,.9,-.82,2)         # eyes
m.pair(.06,.98,-.7,.15,1.16,-.6,4)         # ears
for z in (-.36,.36): m.pair(.08,0,z-.07,.18,.45,z+.07,0)  # legs
m.box(-.06,.62,.5,.06,.74,.92,4)           # tail
m.save('brickcraft_habitat_wolf.obj','wolf')
rows_png('brickcraft_habitat_wolf.png',[(122,126,136),(206,208,212),(240,200,60),(30,30,34),(84,88,98)])

# --- Lion. Rows: 0 tawny fur, 1 mane, 2 eyes, 3 nose, 4 tail tuft.
m=Boxes()
m.box(-.28,.5,-.55,.28,1.0,.7,0)           # body
m.box(-.4,.5,-1.0,.4,1.36,-.5,1)           # mane
m.box(-.24,.66,-1.18,.24,1.14,-.98,0)      # face
m.box(-.1,.68,-1.28,.1,.84,-1.16,0)        # muzzle
m.box(-.05,.8,-1.3,.05,.86,-1.27,3)        # nose
m.pair(.09,.96,-1.19,.16,1.03,-1.18,2)     # eyes
for z in (-.42,.56): m.pair(.1,0,z-.09,.24,.55,z+.09,0)  # legs
m.box(-.04,.8,.7,.04,.88,1.25,0)           # tail
m.box(-.08,.74,1.2,.08,.94,1.36,4)         # tuft
m.save('brickcraft_habitat_lion.obj','lion')
rows_png('brickcraft_habitat_lion.png',[(214,166,92),(128,74,36),(52,40,24),(60,36,30),(96,56,30)])

# --- Eagle (wings spread). Rows: 0 brown, 1 white head and tail, 2 eyes, 3 beak and feet, 4 dark wings.
m=Boxes()
m.box(-.18,.2,-.3,.18,.5,.35,0)            # body
m.box(-.14,.38,-.52,.14,.66,-.24,1)        # head
m.box(-.04,.44,-.62,.04,.54,-.5,3)         # beak
m.pair(.07,.56,-.525,.12,.6,-.52,2)        # eyes
m.pair(.18,.38,-.18,.7,.46,.2,0)           # inner wings
m.pair(.7,.4,-.12,1.15,.46,.16,4)          # outer wings
m.box(-.14,.28,.35,.14,.36,.62,1)          # tail
m.pair(.05,.06,-.05,.1,.2,.05,3)           # feet
m.save('brickcraft_habitat_eagle.obj','eagle')
rows_png('brickcraft_habitat_eagle.png',[(110,72,44),(246,244,236),(30,30,34),(240,196,48),(70,46,30)])

# --- Earthquake boulder and asteroid: plain cubes drawn with these.
def noise(x,y,s): return (math.sin(x*12.9898+y*78.233+s)*43758.5453)%1
png('brickcraft_habitat_boulder.png',16,16,lambda x,y:tuple(int(c*(.82+.3*noise(x//2,y//2,1))) for c in (128,124,118))+(255,))
def meteor(x,y):
    r=noise(x//2,y//2,7)
    return (255,int(120+120*r),40,255) if r>.55 else (90,60,50,255) if r>.2 else (60,40,36,255)
png('brickcraft_habitat_meteor.png',16,16,meteor)
png('brickcraft_habitat_spark.png',8,8,lambda x,y:(255,200,80,max(0,int(255-((x-3.5)**2+(y-3.5)**2)*20))))

# --- Food and water sources.
def soil(x,y): return (124,84,56,255) if (x//4+y//4)%2 else (110,74,48,255)
def carrots(x,y):  # soil with four green carrot tops, seen from above
    for cx,cy in ((7,7),(23,7),(7,23),(23,23)):
        if (x-cx)**2+(y-cy)**2<10: return (88,171,65,255)
        if abs(x-cx)<5 and abs(y-cy)<2 or abs(y-cy)<5 and abs(x-cx)<2: return (62,140,52,255)
    return soil(x,y)
png('brickcraft_habitat_patch_top.png',32,32,carrots)
png('brickcraft_habitat_patch_empty.png',32,32,soil)
def patch_side(x,y):
    if y<10: return soil(x,y)
    if 4<=x%10<=6 and y<22: return (245,135,44,255)  # carrots in the soil
    return (118,80,52,255) if y!=31 else (98,66,44,255)
png('brickcraft_habitat_patch_side.png',32,32,patch_side)
def carrot_icon(x,y):
    dx,dy=x-16,y-16
    if dy<-6 and abs(dx+dy*.3)<3 and dy>-15: return (74,168,68,255)
    if -7<=dy<=13 and abs(dx)<=4.5*(1-(dy+7)/22): return (245,135,44,255)
    return (0,0,0,0)
png('brickcraft_habitat_carrot.png',32,32,carrot_icon)
png('brickcraft_habitat_water.png',32,32,lambda x,y:(74,161,217,255) if (x+y)%9 else (130,200,240,255))
png('brickcraft_habitat_trough_side.png',32,32,lambda x,y:(128,132,140,255) if x not in (0,31) and y not in (0,31) else (100,104,112,255))
def trough_icon(x,y):
    if 10<=y<=24 and 3<=x<=28: return (74,161,217,255) if y<14 and 6<=x<=25 else (128,132,140,255)
    return (0,0,0,0)
png('brickcraft_habitat_trough.png',32,32,trough_icon)
png('brickcraft_habitat_flood.png',16,16,lambda x,y:(62,128,190,170) if (x+2*y)%11 else (120,180,230,190))
print('habitat assets written to',root)

# --- Colony structures: hutch (home), nursery, lookout, and their icons.
def wood(x,y): return (176,128,84,255) if (y//4)%2 else (160,114,74,255)
png('brickcraft_habitat_hutch_roof.png',32,32,lambda x,y:(214,84,64,255) if (x//4+y//8)%2 else (196,70,54,255))
def hutch_front(x,y):
    if (x-15.5)**2/64+(y-26)**2/196<1: return (52,36,28,255)   # an arched doorway
    return wood(x,y)
png('brickcraft_habitat_hutch_front.png',32,32,hutch_front)
png('brickcraft_habitat_hutch_side.png',32,32,wood)
def hutch_icon(x,y):
    if y<14 and abs(x-15.5)<=y+2: return (214,84,64,255)
    if 14<=y<=29 and 4<=x<=27: return (52,36,28,255) if (x-15.5)**2/25+(y-26)**2/64<1 else wood(x,y)
    return (0,0,0,0)
png('brickcraft_habitat_hutch.png',32,32,hutch_icon)
png('brickcraft_habitat_nursery_top.png',32,32,lambda x,y:(246,170,190,255) if (x//6+y//6)%2 else (255,226,236,255))
png('brickcraft_habitat_nursery_side.png',32,32,lambda x,y:(238,229,199,255) if y>6 else (246,170,190,255))
def nursery_icon(x,y):
    if 14<=y<=26 and 3<=x<=28: return (246,170,190,255) if y<18 else (238,229,199,255)
    if 8<=y<14 and (x-10)**2+(y-12)**2<12: return (255,255,255,255)
    return (0,0,0,0)
png('brickcraft_habitat_nursery.png',32,32,nursery_icon)
png('brickcraft_habitat_lookout.png',32,32,lambda x,y:(140,100,64,255) if x%8 else (110,76,48,255))
png('brickcraft_habitat_lookout_top.png',32,32,lambda x,y:(249,193,65,255) if (x+y)%6 else (220,160,40,255))
def lookout_icon(x,y):
    if y<8 and 6<=x<=25: return (249,193,65,255)
    if 8<=y<=30 and (abs(x-10)<2 or abs(x-21)<2): return (140,100,64,255)
    if y in (15,22) and 10<=x<=21: return (140,100,64,255)
    return (0,0,0,0)
png('brickcraft_habitat_lookout_icon.png',32,32,lookout_icon)

# --- Fence and gate icons.
def fence_icon(x,y):
    if (abs(x-7)<2 or abs(x-24)<2) and 4<=y<=29: return (150,104,70,255)
    if (abs(y-11)<2 or abs(y-21)<2) and 5<=x<=26: return (176,128,84,255)
    return (0,0,0,0)
png('brickcraft_habitat_fence.png',32,32,fence_icon)
def gate_icon(x,y):
    if (abs(x-4)<2 or abs(x-27)<2) and 3<=y<=29: return (110,76,48,255)
    if 6<=x<=25 and (abs(y-10)<2 or abs(y-21)<2 or abs((x-6)-(y-8)*1.4)<1.6 and 8<=y<=23): return (176,128,84,255)
    return (0,0,0,0)
png('brickcraft_habitat_gate.png',32,32,gate_icon)
