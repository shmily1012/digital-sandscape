"""Float32-input CPU oracle for the GPU height-function estimator."""
import json
import struct
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.capillary import circle_fractions,height_curvature,extend_curvature

def main():
    cases=[]
    for name,n in [('circle32',32),('circle64',64),('planar',32),('near_pure_noise',32),('second_interface',32),('unresolved',32)]:
        field=circle_fractions(n)
        if name=='planar':field=[min(1,max(0,n*0.51-y)) for y in range(n) for x in range(n)]
        if name=='unresolved':field=[0.5]*(n*n)
        if name in ('near_pure_noise','second_interface'):
            field=[min(1,max(0,y-15.3)) for y in range(n) for x in range(n)]
            for x in range(n):field[19*n+x]=1-5.96e-8 if name=='near_pure_noise' else 0.9
        field=list(struct.unpack(f'{n*n}f',struct.pack(f'{n*n}f',*field)))
        raw=height_curvature(n,field)
        cases.append(dict(name=name,size=n,fraction=field,expected=raw,extended=extend_curvature(n,field,raw)))
    rejected=ROOT/'reports/capillary-rejected-state.bin'
    if rejected.exists():
        field=list(struct.unpack('1024f',rejected.read_bytes()))
        raw=height_curvature(32,field)
        cases.append(dict(name='captured_rejection',size=32,fraction=field,expected=raw,extended=extend_curvature(32,field,raw)))
    (ROOT/'reports/curvature-fixtures.json').write_text(json.dumps(cases),encoding='utf-8')

if __name__=='__main__':main()
