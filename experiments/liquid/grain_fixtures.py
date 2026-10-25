import json
from dataclasses import asdict
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.grain_coupling import Grain,advance,spread,calibrate_self_response

def main():
    base=json.loads((ROOT/'reports/pressure-transport-fixtures.json').read_text())[0]
    grid=DarcyGrid(32,base['geometry']['active'])
    grains=[Grain(.42,.43,.012,.04,2.65,1),Grain(.58,.43,.01,.03,2.2,2),Grain(.5,.6,.014,.05,1.8,3)]
    cases=[]
    base_grains=grains
    for name,g,dt,budget in [('down',(0,1),.01,96),('oblique',(.6,.8),.01,96),('up',(0,-1),.01,96),('budget',(0,1),.01,1),('wall',(0,1),100,96),('isolated',(.6,.8),.01,96)]:
        grains=[Grain(.473,.521,.012,.04,2.65,1)] if name=='isolated' else base_grains
        self_response,_=calibrate_self_response(grid,grains)
        accepted=name not in ('budget','wall')
        expected,_,_=advance(grid,grains,g,dt) if accepted else (grains,None,None)
        source,_,_=spread(grid,grains,g)
        cases.append(dict(name=name,gravity=g,dt=dt,budget=budget,accepted=accepted,grains=[asdict(v) for v in grains],expected=[asdict(v) for v in expected],source=source,self_response=self_response))
    (ROOT/'reports/grain-fixtures.json').write_text(json.dumps(dict(base=base,cases=cases)),encoding='utf-8')

if __name__=='__main__':main()
