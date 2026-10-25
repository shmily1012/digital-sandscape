"""Float32-input CPU oracle for GPU disk apertures and reciprocal transfer."""
from pathlib import Path
import sys,json,struct
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.disk_volume import face_apertures

def f32(x):return struct.unpack('<f',struct.pack('<f',x))[0]
def main():
    cases=[]
    configs=[('single',16,[(.473,.517,.071)]),('touching',32,[(.45,.5,.05),(.55,.5,.05)]),('tangent',16,[(.4915,.517,.071)]),('sixteen',64,[(.5+(x-1.5)*.09,.5+(y-1.5)*.09,.035) for y in range(4) for x in range(4)])]
    for name,side,positions in configs:
        grid=DarcyGrid(side,circle_mask(side),[.2+(i%side)/side for i in range(side*side)])
        grains=[Grain(*[f32(v) for v in p],.04,2.65,1) for p in positions]
        velocities=[[f32(.13*(i%3-1)),f32(.2-.03*i)] for i in range(len(grains))]
        # Tangency must carry nonzero horizontal flux.
        velocities[0]=[f32(.3),f32(-.2)]
        weights=[face_apertures(grid,g) for g in grains]
        source=[sum(w[f]*v[a] for w,v in zip(weights,velocities)) for f,(_,_,_,a) in enumerate(grid.faces)]
        liquid=[f32(v) for v in grid.project(source).liquid]
        mobility=[f32(m) for _,_,m,_ in grid.faces]
        adjoint=[[ -sum(w[f]*grid.h**2*liquid[f]/mobility[f] for f,(_,_,_,a) in enumerate(grid.faces) if a==axis) for axis in (0,1)] for w in weights]
        cases.append(dict(name=name,side=side,grains=[[g.x,g.y,g.radius,0.] for g in grains],velocities=velocities,
                          faces=[[i,j,a,0] for i,j,_,a in grid.faces],active=[int(a) for a in grid.active],q=liquid,mobility=mobility,
                          expected_source=source,expected_adjoint=adjoint,accepted=True,fault=''))
    for fault in ('overlap','wall','mobility','nan','overflow'):
        c=dict(cases[1]);c.update(name=fault,accepted=False,fault=fault);cases.append(c)
    (ROOT/'reports/geometric-operator-fixtures.json').write_text(json.dumps(dict(cases=cases)),encoding='utf-8')
if __name__=='__main__':main()
