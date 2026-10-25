"""Effective overdamped exchange oracle; no resolved fluid momentum claim."""
import json
import math
import struct
from pathlib import Path
from grain_interface_work_reference import fixtures as energy_fixtures, exchange_work, neighbor, DIRECTIONS
from phase_grains_reference import hash32

HOPS = DIRECTIONS+((1,1),(-1,1),(-1,-1),(1,-1))
F=lambda x:struct.unpack('<f',struct.pack('<f',x))[0]
add=lambda a,b:F(a+b)
sub=lambda a,b:F(a-b)
mul=lambda a,b:F(a*b)
div=lambda a,b:F(a/b)


def encoded_bond_function(c,m,sigma,cosine):
    kappa=mul(mul(1.5,sigma),4.)
    def bond(i,j):
        if m[i] and m[j]:return 0.
        if not m[i] and not m[j]:
            d=sub(c[i],c[j]);return mul(mul(mul(.5,kappa),d),d)
        fluid,solid=(j,i) if m[i] else (i,j)
        cf=c[fluid];preference=cosine if m[solid]>=2 else 0.
        alpha=div(mul(2.,preference),4.)
        one=add(1.,alpha)
        cb=cf if alpha==0 else div(mul(2.,cf),add(one,F(math.sqrt(sub(mul(one,one),mul(mul(4.,alpha),cf))))))
        d=sub(cb,cf)
        return add(mul(mul(kappa,d),d),mul(mul(mul(mul(sigma,preference),cb),cb),sub(3.,mul(2.,cb))))
    return bond


def encoded_work(c,m,n,a,b,sigma,cosine):
    """Float32 discrete arithmetic, separately audited against global double energy."""
    bond=encoded_bond_function(c,m,sigma,cosine)
    mapped=lambda i:b if i==a else a if i==b else i
    delta=0.
    for d in DIRECTIONS:
        j=neighbor(a,d,n)
        if j is not None:delta=add(delta,sub(bond(mapped(a),mapped(j)),bond(a,j)))
        j=neighbor(b,d,n)
        if j is not None and j!=a:delta=add(delta,sub(bond(mapped(b),mapped(j)),bond(b,j)))
    return delta


def step(c,m,f,residual,moved,n,tick,seed,gravity,sigma=.01,cosine=0.,drag=1,weight_scale=1.,mobility_scale=1.):
    rounding = lambda x: math.floor(x+.5)
    gx,gy=map(F,gravity);sigma=F(sigma);cosine=F(cosine)
    sign=lambda x:(x>0)-(x<0)
    down=(sign(gx),0) if abs(gx)>abs(gy) else (0,sign(gy))
    for phase in range(16):
        color=(phase+tick)%16
        for y in range(color//4,n,4):
            for x in range(color%4,n,4):
                a=y*n+x
                if m[a]<2 or moved[a]==tick:continue
                # Match the shader's exact eligibility shortcut, not a cached
                # surface mask: previous colors can expose a buried grain.
                cardinal = (neighbor(a, direction, n) for direction in DIRECTIONS)
                if not any(j is not None and m[j] == 0 and c[j] <= .05 for j in cardinal):continue
                reference_weight={2:2.,3:1.7,4:1.4}[m[a]]
                weight=mul(F(reference_weight),F(weight_scale))
                below=neighbor(a,down,n)
                supported=below is None or (below!=a and (m[below]!=0 or c[below]>.05))
                rng=hash32(seed^(tick*747796405)^(a*277803737))
                chosen=None;best=0;ties=0
                for dx,dy in HOPS:
                    b=neighbor(a,(dx,dy),n)
                    if b is None or m[b]!=0 or c[b]>.05:continue
                    diagonal=dx!=0 and dy!=0
                    if diagonal:
                        routes=[neighbor(a,d,n) for d in ((dx,0),(0,dy))]
                        if not supported or all(j is None or m[j]!=0 for j in routes):continue
                    change=encoded_work(c,m,n,a,b,sigma,cosine)
                    change=sub(change,mul(add(F(weight),c[b]),add(mul(gx,dx),mul(gy,dy))))
                    score=max(0,min(10000000,rounding(div(mul(-change,1e9),2 if diagonal else 1))))
                    if score<=0:continue
                    rng=hash32(rng+0x9e3779b9)
                    if score>best:best=score;chosen=b;ties=1
                    elif score==best:
                        ties+=1
                        if rng%ties==0:chosen=b
                if chosen is None:continue
                rng=hash32(rng+0x9e3779b9)
                threshold=rounding(div(mul(mul(mul({2:24.,3:18.,4:12.}[m[a]],F(mobility_scale)),min(4.,div(best,mul(F(reference_weight),20000.)))),256.),drag))
                if (rng&65535)>=threshold:continue
                b=chosen
                m[a],m[b]=m[b],m[a];c[a],c[b]=c[b],c[a]
                residual[a],residual[b]=residual[b],residual[a]
                f[9*a:9*a+9],f[9*b:9*b+9]=f[9*b:9*b+9],f[9*a:9*a+9]
                moved[a],moved[b]=moved[b],tick


def fixtures(include_variants=False):
    result=[]
    for case in energy_fixtures():
        for sigma,gravity in ((0.,(0.,.00002)),(.01,(0.,.00002)),(.01,(-.000012,.000016))):
            n=case['side'];c=case['phase'].copy();m=case['materials'].copy()
            f=[(i%97)/128 for i in range(n*n*9)];residual=[i/65536 for i in range(n*n)]
            moved=[-1]*(n*n)
            initial=dict(phase=c.copy(),materials=m.copy(),populations=f.copy(),residual=residual.copy())
            for tick in range(80):step(c,m,f,residual,moved,n,tick,20261024,gravity,sigma,case['cosine'])
            result.append(dict(initial,side=n,sigma=sigma,gravity=gravity,cosine=case['cosine'],steps=80,
                               expected_phase=c,expected_materials=m,expected_populations=f,
                               expected_residual=residual,expected_moved=moved))
    for base in result.copy() if include_variants else []:
        for weight_scale,mobility_scale in ((.7,1.),(1.4,1.),(1.,.5),(1.,2.)):
            c=base['phase'].copy();m=base['materials'].copy();f=base['populations'].copy();r=base['residual'].copy();stamps=[-1]*(base['side']**2)
            for tick in range(base['steps']):
                step(c,m,f,r,stamps,base['side'],tick,20261024,base['gravity'],base['sigma'],base['cosine'],weight_scale=weight_scale,mobility_scale=mobility_scale)
            result.append(dict(base,weight_scale=weight_scale,mobility_scale=mobility_scale,expected_phase=c,expected_materials=m,expected_populations=f,expected_residual=r,expected_moved=stamps))
    return result


if __name__=='__main__':
    (Path(__file__).resolve().parents[1]/'reports/grain-energy-fixture.json').write_text(json.dumps(fixtures(True)))
