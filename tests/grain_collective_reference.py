"""Bounded collective motion along an explicit, unobstructed fluid loop."""
import json
import math
from pathlib import Path
from grain_energy_reference import F,add,sub,mul,div,encoded_bond_function
from grain_interface_work_reference import neighbor,DIRECTIONS
from phase_grains_reference import hash32

WEIGHT={2:2.,3:1.7,4:1.4}
MOBILITY={2:24.,3:18.,4:12.}


def paths(m,moved,n,a,tick,gravity):
    gx,gy=gravity
    if gx==gy==0 or m[a]<2 or moved[a]==tick:return []
    sign=lambda x:(x>0)-(x<0)
    down=(0,sign(gy)) if abs(gy)>=abs(gx) else (sign(gx),0)
    target=neighbor(a,down,n)
    if target is None or m[target]:return []
    grains=[]
    for k in range(8):
        j=neighbor(a,(-k*down[0],-k*down[1]),n)
        if j is None or m[j]<2:break
        if moved[j]==tick:break
        grains.append(j)
    if len(grains)<2:return []
    result=[]
    for direction in (1,-1):
        side=(down[1]*direction,-down[0]*direction)
        return_cells=[]
        for k in range(len(grains)+1):
            j=neighbor(a,((1-k)*down[0]+side[0],(1-k)*down[1]+side[1]),n)
            if j is None or m[j]:break
            return_cells.append(j)
        length=min(len(grains),len(return_cells)-1)
        if length<2:continue
        result.append(list(reversed(grains[:length]))+[target]+return_cells[:length+1])
    return result


def work(c,m,n,path,gravity,sigma,cosine,weight_scale=1.):
    bond=encoded_bond_function(c,m,F(sigma),F(cosine))
    slots={i:k for k,i in enumerate(path)};delta=0.;gx,gy=map(F,gravity)
    for k,i in enumerate(path):
        old_i=path[k-1]
        for d in DIRECTIONS:
            j=neighbor(i,d,n)
            if j is None or (j in slots and j<i):continue
            old_j=path[slots[j]-1] if j in slots else j
            delta=add(delta,sub(bond(old_i,old_j),bond(i,j)))
        nxt=path[(k+1)%len(path)]
        mass=mul(F(WEIGHT[m[i]]),F(weight_scale)) if m[i]>=2 else -c[i]
        delta=sub(delta,mul(mass,add(mul(gx,nxt%n-i%n),mul(gy,nxt//n-i//n))))
    return delta


def apply(c,m,f,residual,moved,path,tick):
    old_c=[c[i] for i in path];old_m=[m[i] for i in path]
    old_r=[residual[i] for i in path];old_stamp=[moved[i] for i in path]
    old_f=[f[9*i:9*i+9] for i in path]
    for k,i in enumerate(path):
        c[i]=old_c[k-1];m[i]=old_m[k-1];residual[i]=old_r[k-1]
        f[9*i:9*i+9]=old_f[k-1];moved[i]=tick if m[i]>=2 else old_stamp[k-1]


def step(c,m,f,residual,moved,n,tick,seed,gravity,sigma=.01,cosine=.5,drag=1,weight_scale=1.,mobility_scale=1.):
    gx,gy=map(F,gravity);vertical=abs(gy)>=abs(gx)
    for phase in range(48):
        color=(phase+tick)%48
        for axial in range(color//4,n,12):
            for lateral in range(color%4,n,4):
                x,y=(lateral,axial) if vertical else (axial,lateral);a=y*n+x
                candidates=paths(m,moved,n,a,tick,(gx,gy))
                if not candidates:continue
                rng=hash32(seed^(tick*747796405)^(a*277803737));best=0;chosen=None;resistance=0.
                for path in candidates:
                    score=max(0,min(10000000,math.floor(mul(-work(c,m,n,path,(gx,gy),sigma,cosine,weight_scale),1e9)+.5)))
                    if score<=0:continue
                    rng=hash32(rng+0x9e3779b9)
                    if score>best or (score==best and not (rng&1)):
                        best=score;chosen=path;length=len(path)//2-1;resistance=0.
                        for j in reversed(path[:length]):
                            resistance=add(resistance,div(mul(F(WEIGHT[m[j]]),256.),mul(MOBILITY[m[j]],F(mobility_scale))))
                        resistance=add(resistance,mul(length+2,8.))
                if chosen is None:continue
                rng=hash32(rng+0x9e3779b9)
                rate=min(.25,max(0.,div(mul(best,F(1e-9)),mul(mul(F(.00002),resistance),drag))))
                if (rng&65535)>=math.floor(mul(rate,65536.)+.5):continue
                apply(c,m,f,residual,moved,chosen,tick)


def fixtures(include_variants=False):
    result=[];n=24
    for index,(blocked,sigma,gravity,length) in enumerate([(False,0.,(0.,.00002),4),(True,0.,(0.,.00002),4),
                                         (False,.01,(0.,.00002),4),(False,.01,(.000012,.000016),8),
                                         (False,.01,(0.,-.00002),4),(False,.01,(0.,.00002),8)]):
        m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        for y in range(6,6+length):m[y*n+12]=2 if index==5 else 2+y%3
        if blocked:
            for y in range(5,7+length):m[y*n+11]=m[y*n+13]=1
        center=16.5 if index==5 else 13.
        c=[0. if m[i] else F(.5*(1+math.tanh((i//n-center)/2))) for i in range(n*n)]
        f=[(i%97)/128 for i in range(n*n*9)];r=[i/65536 for i in range(n*n)];stamps=[-1]*(n*n)
        initial=dict(phase=c.copy(),materials=m.copy(),populations=f.copy(),residual=r.copy())
        steps=180 if index==5 else 60
        for tick in range(steps):step(c,m,f,r,stamps,n,tick,20261024,gravity,sigma)
        result.append(dict(initial,side=n,sigma=sigma,gravity=gravity,cosine=.5,steps=steps,
                           expected_phase=c,expected_materials=m,expected_populations=f,expected_residual=r,expected_moved=stamps))
    # Rotate the nontrivial barrier case to exercise the horizontal GPU tiling.
    base=result[5]
    rotate=lambda values:[values[(n-1-x)*n+y] for y in range(n) for x in range(n)]
    c=rotate(base['phase']);m=rotate(base['materials']);r=rotate(base['residual'])
    packets=rotate([base['populations'][9*i:9*i+9] for i in range(n*n)])
    f=[v for packet in packets for v in packet];stamps=[-1]*(n*n)
    initial=dict(phase=c.copy(),materials=m.copy(),populations=f.copy(),residual=r.copy())
    for tick in range(180):step(c,m,f,r,stamps,n,tick,20261024,(-.00002,0.),.01)
    result.append(dict(initial,side=n,sigma=.01,gravity=(-.00002,0.),cosine=.5,steps=180,
                       expected_phase=c,expected_materials=m,expected_populations=f,expected_residual=r,expected_moved=stamps))
    base=result[0]
    c=base['phase'].copy();m=base['materials'].copy();f=base['populations'].copy();r=base['residual'].copy();stamps=[-1]*(n*n)
    for x in (11,13):m[7*n+x]=1;c[7*n+x]=0.
    initial=dict(phase=c.copy(),materials=m.copy(),populations=f.copy(),residual=r.copy())
    for tick in range(180):step(c,m,f,r,stamps,n,tick,20261024,(0.,.00002),0.)
    result.append(dict(initial,side=n,sigma=0.,gravity=(0.,.00002),cosine=.5,steps=180,
                       expected_phase=c,expected_materials=m,expected_populations=f,expected_residual=r,expected_moved=stamps))
    for base in result.copy() if include_variants else []:
        for weight_scale,mobility_scale in ((.7,1.),(1.4,1.),(1.,.5),(1.,2.)):
            c=base['phase'].copy();m=base['materials'].copy();f=base['populations'].copy();r=base['residual'].copy();stamps=[-1]*(n*n)
            for tick in range(base['steps']):
                step(c,m,f,r,stamps,n,tick,20261024,base['gravity'],base['sigma'],base['cosine'],weight_scale=weight_scale,mobility_scale=mobility_scale)
            result.append(dict(base,weight_scale=weight_scale,mobility_scale=mobility_scale,expected_phase=c,expected_materials=m,expected_populations=f,expected_residual=r,expected_moved=stamps))
    for case in result:
        case['expected_initial_activity']=sum(bool(paths(case['materials'],[-1]*(n*n),n,i,0,case['gravity'])) for i in range(n*n))
    return result


if __name__=='__main__':
    (Path(__file__).resolve().parents[1]/'reports/grain-collective-fixture.json').write_text(json.dumps(fixtures(True)))
