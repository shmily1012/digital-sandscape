"""Persistent two-grain settle/reverse CPU trajectory, same 32-square carrier."""
import json,sys
from dataclasses import asdict
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.deposition.coupled_contacts import advance_coupled
from experiments.deposition.contact_particles import Plane
from experiments.liquid.grain_coupling import Grain
from experiments.liquid.model import DarcyGrid

def main():
    base=json.loads((ROOT/'reports/online-grain-fixtures.json').read_text())['base']
    grid=DarcyGrid(32,base['geometry']['active'])
    initial=[Grain(.475,.46,.025,.002,2.65,1),Grain(.525,.46,.025,.002,2.2,2)]
    grains=initial;rows=[];planes=[Plane(0,-1,-.525)]
    for step in range(80):
        gravity=(0,1) if step<60 else (0,-1)
        result=advance_coupled(grid,grains,gravity,.005,planes)
        grains=result.contact.grains
        rows.append(dict(gravity=gravity,expected=[asdict(g) for g in grains]))
    (ROOT/'reports/coupled-cycle-fixtures.json').write_text(json.dumps(dict(base=base,initial=[asdict(g) for g in initial],planes=[[0,-1,-.525,0]],steps=rows,dt=.005)))
    print('CPU coupled cycle: 80 steps')
if __name__=='__main__':main()
