"""Compare raw main-window gas fields; no image filtering or state modification."""
from array import array
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def metrics(path):
    c=array('f');c.frombytes(path.read_bytes())
    n=256
    if len(c)!=n*n:raise ValueError('Expected 256 squared fixture')
    troughs=0
    for y in range(1,n-1):
        for x in range(1,n-1):
            i=y*n+x
            if .6<c[i]<.99:
                for d in (1,n):
                    troughs+=c[i-d]>c[i]+.02 and c[i+d]>c[i]+.02
    return dict(bulk_troughs=troughs,mass=sum(c),interface_cells=sum(.1<q<.9 for q in c))


if __name__=='__main__':
    data={}
    for tick in (2000,5000):
        data[tick]={}
        for name,prefix in [('before','phase-before'),('after','phase-preview')]:
            data[tick][name]=metrics(ROOT/f'reports/{prefix}-tick-{tick}.f32')
    (ROOT/'reports/phase-quality-comparison.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print(json.dumps(data,indent=2))
