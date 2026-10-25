"""Read-only feasibility probe on an actual stalled artwork, not a solver.

All packets move one neighbor along a closed rectangular loop. The main
column carries gas and grains upward; the rest is a fluid return route.
"""
import hashlib
import json
import math
import struct
from pathlib import Path
from grain_collective_reference import work, WEIGHT
from grain_interface_work_reference import energy


def paths(c, m, n, a):
    x, y = a % n, a // n
    if m[a] < 2 or y == 0 or m[a-n]:
        return
    gas_seen = False
    bottom = y
    for yy in range(y, min(n-1, y+64)):
        i = yy*n+x
        if m[i] == 1:
            return
        if not m[i] and c[i] > .05:
            gas_seen = True
        elif not m[i] and gas_seen and c[i] <= .05:
            bottom = yy-1
            break
        elif not gas_seen and yy-y > 8:
            return
    else:
        return
    if not gas_seen or bottom <= y:
        return
    for width in (1, 2, 4, 8, 16, 24, 32):
        for sign in (1, -1):
            outer = x+width*sign
            if not 0 <= outer < n:
                continue
            body = [yy*n+x for yy in range(bottom, y-1, -1)]
            top = [(y-1)*n+xx for xx in range(x, outer+sign, sign)]
            side = [yy*n+outer for yy in range(y, bottom+1)]
            back = [bottom*n+xx for xx in range(outer-sign, x, -sign)]
            route = top+side+back
            if any(m[i] for i in route):
                continue
            yield body+route


def probe(prefix, n=256):
    raw_m=Path(str(prefix)+'.materials.u32').read_bytes()
    raw_c=Path(str(prefix)+'.f32').read_bytes()
    m=list(struct.unpack('<%dI' % (n*n),raw_m))
    c=list(struct.unpack('<%df' % (n*n),raw_c))
    candidates=[];legal=0
    gravity=(0.,.00002)
    potential=lambda gas,mat: energy(gas,mat,n,cosine=.5)-math.fsum(
        (WEIGHT.get(v,0.)-gas[i])*gravity[1]*(i//n) for i,v in enumerate(mat))
    initial_potential=potential(c,m)
    for a in range(n*n):
        for path in paths(c,m,n,a):
            legal+=1
            delta=work(c,m,n,path,gravity,.01,.5)
            if delta >= -1e-8:
                continue
            cc=c.copy();mm=m.copy()
            for k,i in enumerate(path):cc[i]=c[path[k-1]];mm[i]=m[path[k-1]]
            measured=potential(cc,mm)-initial_potential
            assert abs(measured-delta)<2e-7,(measured,delta)
            assert sorted(cc)==sorted(c) and sorted(mm)==sorted(m)
            for i,j in zip(path,path[1:]+path[:1]):
                assert abs(i%n-j%n)+abs(i//n-j//n)==1
            candidates.append(dict(source=a,path=path,work_float32=delta,
                                   work_independent_global=measured,
                                   interface_work=work(c,m,n,path,(0.,0.),.01,.5),
                                   gravity_work=math.fsum(-(WEIGHT.get(m[i],0.)-c[i])*gravity[1]*(path[(k+1)%len(path)]//n-i//n) for k,i in enumerate(path))))
            # One candidate per source is enough to establish feasibility.
            break
        if len(candidates)>=8:break
    return dict(input_sha256=hashlib.sha256(raw_m+raw_c).hexdigest(),
                prefix=str(prefix),legal_paths_examined=legal,candidates=candidates,
                runtime_modified=False,physical_acceptance=False,
                scope='Read-only feasibility on real state. Existing effective interface/gravity energy only; no hydrodynamic momentum closure, friction, kinetic rate, GPU scheduling or actual lift demonstrated.')


if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    result=probe(root/'reports/sandscape-long-cycle-90000-paired-interface-energy-exchange-wetting-0.5')
    (root/'reports/buoyant-loop-feasibility.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('BUOYANT_LOOP candidates=%d legal_examined=%d' % (len(result['candidates']),result['legal_paths_examined']))
