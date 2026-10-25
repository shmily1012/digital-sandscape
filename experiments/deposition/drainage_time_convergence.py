"""Fixed-duration temporal refinement audit; explicit geometry frozen per step."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.deposition.geometric_drainage_cycle import run

def main():
    results=[]
    for refinement in (1,2,4):
        result=run(refinement)
        result['mean_flux_change']=sum(r['finite_vs_frozen_flux'] for r in result['rows'])/len(result['rows'])
        results.append(result)
        print(json.dumps({k:v for k,v in result.items() if k!='rows'}),flush=True)
    differences=[max(abs(a-b) for old,new in zip(results[i]['final_positions'],results[i+1]['final_positions']) for a,b in zip(old,new)) for i in range(2)]
    report=dict(scope='Fixed 1.0 duration, reversal at 0.6, identical four grains and grid; not spatial convergence',runs=results,successive_position_errors=differences)
    (ROOT/'reports/drainage-time-convergence.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(dict(successive_position_errors=differences)))
    if differences[1]>=differences[0]:raise RuntimeError('Endpoint trajectory did not refine')
    if any(results[i+1]['mean_flux_change']>=results[i]['mean_flux_change'] for i in range(2)):raise RuntimeError('Mean flux discrepancy did not refine')
if __name__=='__main__':main()
