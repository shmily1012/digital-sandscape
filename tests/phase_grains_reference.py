"""Reference for conservative voxel displacement, without running fluid collision."""
import json
import math
from pathlib import Path


def hash32(x):
    x &= 0xffffffff
    x ^= (x << 13) & 0xffffffff
    x ^= x >> 17
    x ^= (x << 5) & 0xffffffff
    return x & 0xffffffff


def step(c, f, material, n, seed, tick, gravity, forces=None, gravity_scale=.00002, drag_divisor=1, mass_residual=None):
    offsets=[(0,0),(1,0),(0,1),(1,1)]
    gx,gy=gravity
    strength=max(0.,min(4.,gravity_scale/.00002))
    rounding=lambda v: int(math.copysign(math.floor(abs(v)+.5),v))
    body=(rounding(gx*strength),rounding(gy*strength))
    sign=lambda a: (a>0)-(a<0)
    down=(sign(gx),0) if abs(gx)>abs(gy) else (0,sign(gy))
    for phase in range(2):
        for by in range(n//2+1):
            for bx in range(n//2+1):
                x,y=2*bx-phase,2*by-phase
                if x>=n or y>=n:continue
                indices=[(y+dy)*n+x+dx if 0<=x+dx<n and 0<=y+dy<n else -1 for dx,dy in offsets]
                m=[material[i] if i>=0 else 1 for i in indices]
                rng=hash32(seed^(tick*747796405)^(phase*2891336453)^(bx*277803737)^(by*1597334677))
                total=0;source=target=-1
                for a,(ax,ay) in enumerate(offsets):
                    if m[a]<2:continue
                    drive=body
                    if forces is not None:
                        weight={2:2.,3:1.7,4:1.4}[m[a]]
                        def quantize(v):
                            value=max(-4.,min(4.,v/(weight*.00002)))*32767
                            return int(math.copysign(math.floor(abs(value)+.5),value))
                        drive=(body[0]+quantize(forces[indices[a]][0]),body[1]+quantize(forces[indices[a]][1]))
                    support=any((sx,sy)==(ax+down[0],ay+down[1]) and
                                (m[s]!=0 or c[indices[s]]>.05)
                                for s,(sx,sy) in enumerate(offsets))
                    for b,(tx,ty) in enumerate(offsets):
                        if m[b]!=0 or c[indices[b]]>.05:continue
                        dx,dy=tx-ax,ty-ay
                        length=abs(dx)+abs(dy);projection=dx*drive[0]+dy*drive[1]
                        if length==2 and not any(
                            (sx,sy) in ((ax+dx,ay),(ax,ay+dy)) and m[s]==0 and c[indices[s]]<=.05
                            for s,(sx,sy) in enumerate(offsets)):
                            continue
                        if projection<=0 or (length==2 and (not support or projection<=6000*length*strength)):continue
                        total+=projection;rng=hash32(rng+0x9e3779b9)
                        if rng%total<projection:source,target=a,b
                if source<0:continue
                rng=hash32(rng+0x9e3779b9)
                mobility={2:12,3:9,4:6}[m[source]]
                drive=body
                if forces is not None:
                    weight={2:2.,3:1.7,4:1.4}[m[source]]
                    force=forces[indices[source]]
                    def quantize(v):
                        value=max(-4.,min(4.,v/(weight*.00002)))*32767
                        return rounding(value)
                    drive=(body[0]+quantize(force[0]),body[1]+quantize(force[1]))
                mobility=math.floor(mobility*min(4.,math.hypot(*drive)/32767)+.5)
                threshold=(mobility*256+drag_divisor//2)//drag_divisor
                sample16=((rng&255)<<8)|((rng>>8)&255)
                if sample16>=threshold:continue
                a,b=indices[source],indices[target]
                material[a],material[b]=material[b],material[a]
                if forces is not None:forces[a],forces[b]=forces[b],forces[a]
                c[a],c[b]=c[b],c[a]
                if mass_residual is not None:mass_residual[a],mass_residual[b]=mass_residual[b],mass_residual[a]
                f[9*a:9*a+9],f[9*b:9*b+9]=f[9*b:9*b+9],f[9*a:9*a+9]


def fixture():
    n=16
    material=[1 if x in (0,n-1) or y in (0,n-1) else (2+(x+y)%3 if 2<=y<=5 and x%3 else 0) for y in range(n) for x in range(n)]
    c=[0. if m else (.5 if 8<=i//n<=10 and 5<=i%n<=10 else .03125) for i,m in enumerate(material)]
    f=[((i*9+q)%97)/256 for i in range(n*n) for q in range(9)]
    return n,c,f,material


def interface_slide_fixture(turns=0, sealed=False):
    n=6
    m=[1]*(n*n);c=[0.]*(n*n)
    def rotate(x,y):
        for _ in range(turns):x,y=n-1-y,x
        return y*n+x
    source,gas,target=[rotate(x,y) for x,y in ((2,2),(2,3),(3,3))]
    m[source]=2;m[gas]=0;m[target]=0;c[gas]=.75
    if not sealed:m[rotate(3,2)]=0
    f=[((i*9+q)%97)/256 for i in range(n*n) for q in range(9)]
    gravity=(0,32767)
    for _ in range(turns):gravity=(-gravity[1],gravity[0])
    return n,c,f,m,gravity,source,gas,target


GRAVITIES=[(0,32767),(23170,23170),(32767,0),(0,-32767),(-23170,-23170),(0,0)]
if __name__=='__main__':
    n,c,f,m=fixture()
    data=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=GRAVITIES)
    for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[(tick//30)%6])
    data.update(expected=c,expected_populations=f,expected_materials=m)
    n2=16
    m2=[1 if x in (0,n2-1) or y in (0,n2-1) else 0 for y in range(n2) for x in range(n2)]
    m2[10*n2+8]=2;c2=[0.]*(n2*n2);f2=[(i%97)/256 for i in range(n2*n2*9)]
    forces=[(0.,-.00008)]*(n2*n2)
    probe=dict(side=n2,seed=709,initial=c2.copy(),populations=f2.copy(),materials=m2.copy(),steps=180,gravities=[(0,32767)]*6,forces=[v for pair in forces for v in pair])
    for tick in range(180):step(c2,f2,m2,n2,709,tick,(0,32767),forces)
    probe.update(expected=c2,expected_populations=f2,expected_materials=m2)
    data['pressure_case']=probe
    data['strength_cases']=[]
    for strength in (0.,.00001,.00004):
        n,c,f,m=fixture()
        case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=GRAVITIES,gravity_scale=strength)
        for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[(tick//30)%6],gravity_scale=strength)
        case.update(expected=c,expected_populations=f,expected_materials=m)
        data['strength_cases'].append(case)
    c2=probe['initial'].copy();f2=probe['populations'].copy();m2=probe['materials'].copy()
    zero_pressure=dict(side=n2,seed=709,initial=c2.copy(),populations=f2.copy(),materials=m2.copy(),steps=180,gravities=[(0,0)]*6,forces=probe['forces'],gravity_scale=0.)
    for tick in range(180):step(c2,f2,m2,n2,709,tick,(0,0),forces,gravity_scale=0.)
    zero_pressure.update(expected=c2,expected_populations=f2,expected_materials=m2)
    data['strength_cases'].append(zero_pressure)
    data['drag_cases']=[]
    for divisor in (16,64,256):
        n,c,f,m=fixture()
        case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=720,gravities=GRAVITIES,drag_divisor=divisor)
        for tick in range(720):step(c,f,m,n,709,tick,GRAVITIES[(tick//30)%6],drag_divisor=divisor)
        case.update(expected=c,expected_populations=f,expected_materials=m)
        data['drag_cases'].append(case)
    n,c,f,m=fixture();residual=[((i%17)-8)*2**-32 for i in range(n*n)]
    case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=GRAVITIES,residuals=residual.copy())
    for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[(tick//30)%6],mass_residual=residual)
    case.update(expected=c,expected_populations=f,expected_materials=m,expected_residuals=residual)
    data['drag_cases'].append(case)
    for turns in range(4):
        n,c,f,m,g,source,gas,target=interface_slide_fixture(turns)
        case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=[g]*6)
        for tick in range(180):step(c,f,m,n,709,tick,g)
        assert m[target]==2 and m[gas]==0 and c[gas]==.75
        case.update(expected=c,expected_populations=f,expected_materials=m)
        data['drag_cases'].append(case)
        n,c,f,m,g,source,gas,target=interface_slide_fixture(turns,sealed=True)
        case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=[g]*6)
        for tick in range(180):step(c,f,m,n,709,tick,g)
        assert m[source]==2 and m[target]==0 and c[gas]==.75
        case.update(expected=c,expected_populations=f,expected_materials=m)
        data['drag_cases'].append(case)
    n,c,f,m=fixture()
    forces=[(((i%3)-1)*2**-16, -2**-14) if v>=2 else (0.,0.) for i,v in enumerate(m)]
    case=dict(side=n,seed=709,initial=c.copy(),populations=f.copy(),materials=m.copy(),steps=180,gravities=GRAVITIES,forces=[v for pair in forces for v in pair])
    for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[(tick//30)%6],forces=forces)
    case.update(expected=c,expected_populations=f,expected_materials=m,expected_forces=[v for pair in forces for v in pair])
    data['drag_cases'].append(case)
    (Path(__file__).resolve().parents[1]/'reports/phase-grains-fixture.json').write_text(json.dumps(data),encoding='utf-8')
