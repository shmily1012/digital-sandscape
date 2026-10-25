"""State-dependent Darcy buoyancy oracle, dimensionless and without capillarity."""
import json
from pathlib import Path
import sys
import argparse
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.geometric_transport import advect
from experiments.liquid.capillary import circle_fractions,height_curvature,capillary_flux,extend_curvature

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--capillary-steps',type=int,default=40)
    args=parser.parse_args()
    if not 2<=args.capillary_steps<=2000:parser.error('Require 2..2000 bounded steps')
    base=json.loads((ROOT/'reports/pressure-transport-fixtures.json').read_text())[0]
    grid=DarcyGrid(32,base['geometry']['active'])
    state=list(base['geometry']['initial'])
    sequence=[]
    elapsed=0.0
    for index in range(40):
        gravity=(0,1) if index<20 else (0,-1)
        source=[-m*0.02*gravity[axis]*0.5*(state[i]+state[j]) for i,j,m,axis in grid.faces]
        velocity=grid.project(source).mixture
        state,dt=advect(grid,state,velocity,0.02)
        elapsed+=dt
        sequence.append(dict(case='normal',gravity=gravity,expected=list(state),elapsed=elapsed))
    (ROOT/'reports/buoyancy-sequence.json').write_text(json.dumps(sequence),encoding='utf-8')
    print('Generated',len(sequence),'state-dependent buoyancy steps')
    state=circle_fractions(32)
    initial=list(state)
    sequence=[]
    elapsed=0.0
    for index in range(args.capillary_steps):
        gravity=(0,1) if index<args.capillary_steps//2 else (0,-1)
        curvature=extend_curvature(32,state,height_curvature(32,state))
        source=capillary_flux(grid,state,curvature,0.001,5.0)
        source=[q-m*0.02*gravity[axis]*0.5*(state[i]+state[j]) for q,(i,j,m,axis) in zip(source,grid.faces)]
        velocity=grid.project(source).mixture
        state,dt=advect(grid,state,velocity,0.0005)
        elapsed+=dt
        sequence.append(dict(case='normal',gravity=gravity,expected=list(state),elapsed=elapsed,initial=initial))
    (ROOT/'reports/capillary-sequence.json').write_text(json.dumps(sequence),encoding='utf-8')
    print('Generated',len(sequence),'coupled capillary steps')

if __name__=='__main__':main()
