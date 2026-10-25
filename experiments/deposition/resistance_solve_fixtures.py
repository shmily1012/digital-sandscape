"""Independent CPU velocity oracle for force-driven GPU resistance solves."""
import json,sys,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.matrix_free_drainage import MatrixFreeDrainage

def model(c):
 g=DarcyGrid(c['side'],c['active']);g.faces=[(i,j,m,a) for (i,j,a,_),m in zip(c['faces'],c['mobility'])]
 return MatrixFreeDrainage(g,[Grain(*p[:3],.04,2.65,1) for p in c['grains']])
def main():
 data=json.loads((ROOT/'reports/drainage-gpu-fixtures.json').read_text(encoding='utf-8'))
 cases=[c for c in data['cases'] if c['name'] in ('single','tangent','sixteen')]
 for c in cases:
  c['force']=[struct.unpack('<f',struct.pack('<f',x))[0] for i in range(len(c['grains'])) for x in (.0001*(i%3-1),-.001)]
  c['expected_velocity']=model(c).solve(c['force'],tolerance=1e-11).velocity
 (ROOT/'reports/resistance-solve-fixtures.json').write_text(json.dumps(dict(cases=cases)),encoding='utf-8')
if __name__=='__main__':main()
