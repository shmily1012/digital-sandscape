"""Re-evaluate accepted GPU velocities with the independent double CPU operator."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.deposition.resistance_solve_fixtures import model

def main():
 fixtures=json.loads((ROOT/'reports/resistance-solve-fixtures.json').read_text(encoding='utf-8'))['cases']
 source=json.loads((ROOT/'reports/resistance-solve-gpu.json').read_text(encoding='utf-8'))
 models={c['name']:(c,model(c)) for c in fixtures}
 failures=source['failures'];rows=[]
 for result in source['cases']:
  if not result['accepted']:continue
  fixture,op=models[result['name']]
  residual=max(abs(a-f*result['scale']) for a,f in zip(op.apply(result['velocity']),fixture['force']))
  if residual>2e-7:failures+=1
  rows.append(dict(name=result['name'],scenario=result['scenario'],independent_force_residual=residual))
 report=dict(failures=failures,cases=rows,tolerance=2e-7)
 (ROOT/'reports/resistance-solve-independent.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print(json.dumps(report));return int(failures!=0)
if __name__=='__main__':raise SystemExit(main())
