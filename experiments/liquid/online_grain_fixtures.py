import json
from pathlib import Path
from dataclasses import asdict
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.grain_coupling import Grain,advance,calibrate_self_response
from experiments.liquid.model import DarcyGrid

def main():
    fixture=json.loads((ROOT/'reports/grain-fixtures.json').read_text())
    initial=fixture['cases'][0]['grains']
    grid=DarcyGrid(32,fixture['base']['geometry']['active'])
    grains=[Grain(**g) for g in initial]
    sequence=[]
    for step in range(8):
        gravity=(.6,.8) if step<4 else (-.6,-.8)
        blocks,_=calibrate_self_response(grid,grains)
        grains,_,_=advance(grid,grains,gravity,.02)
        sequence.append(dict(gravity=gravity,dt=.02,self_response=blocks,expected=[asdict(g) for g in grains]))
    (ROOT/'reports/online-grain-fixtures.json').write_text(json.dumps(dict(base=fixture['base'],initial=initial,sequence=sequence)),encoding='utf-8')

if __name__=='__main__':main()
