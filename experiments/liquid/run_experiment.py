"""Run an evolving five-material mixture and save measured snapshots."""
import json
import argparse
import math
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid, circle_mask
from experiments.liquid.transport import DriftMixture


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--scheme',choices=['upwind','muscl'],default='upwind')
    args=parser.parse_args()
    n=24
    grid=DarcyGrid(n,circle_mask(n))
    fields=[[0.0]*(n*n) for _ in range(5)]
    for i,active in enumerate(grid.active):
        if not active:
            continue
        x,y=(i%n+0.5)/n,(i//n+0.5)/n
        sand=0.5 if 0.18<y<0.4 else 0
        gas=0.65 if min((x-0.35)**2,(x-0.65)**2)+(y-0.54)**2<0.12**2 else 0
        material=1+min(2,max(0,int((y-0.18)/0.075)))
        fields[material][i]=sand
        fields[4][i]=gas
        fields[0][i]=1-sand-gas
    mixture=DriftMixture(grid,fields,[(0,v) for v in (0,0.07,0.05,0.03,-0.08)],scheme=args.scheme)
    inventory=mixture.inventory()
    frames=[]
    peak_volume,peak_divergence,total_steps=0.0,0.0,0
    for frame in range(181):
        if frame:
            # Rotate the existing world halfway through; never recreate fractions.
            angle=0 if frame<=90 else math.pi*0.75
            mixture.slips=[(v*math.sin(angle),v*math.cos(angle)) for v in (0,0.07,0.05,0.03,-0.08)]
            report=mixture.advance(0.05)
            peak_volume=max(peak_volume,report.max_volume_error)
            peak_divergence=max(peak_divergence,report.max_divergence)
            total_steps+=report.substeps
        if frame%45==0:
            frames.append(dict(time=mixture.time,fractions=[c.copy() for c in mixture.fractions]))
    error=max(abs(a-b) for a,b in zip(inventory,mixture.inventory()))
    minimum=min(min(c) for c in mixture.fractions)
    assert error<1e-10 and peak_volume<1e-8 and minimum>=0
    result=dict(size=n,scheme=args.scheme,inventory_initial=inventory,inventory_final=mixture.inventory(),
                max_inventory_error=error,max_local_volume_error=peak_volume,
                max_divergence=peak_divergence,minimum_fraction=minimum,substeps=total_steps,
                time=mixture.time,snapshots=frames,
                scope='CPU drift-flux transport with pressure returnflow; no coherent interface or contact bed')
    filename='liquid-transport.json' if args.scheme=='upwind' else 'liquid-transport-muscl.json'
    (ROOT/'reports'/filename).write_text(json.dumps(result),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='snapshots'}))


if __name__=='__main__':
    main()
