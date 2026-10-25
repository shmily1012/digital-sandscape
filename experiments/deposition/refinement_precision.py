"""Capture active systems and independent small SVD checks reproducibly."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
import numpy as np
from experiments.deposition.contact_particles import advance_contacts,circular_planes,ContactConvergenceError
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain

def main():
    fixture=json.loads((ROOT/'tests/fixtures/contact_gpu_failure_232.json').read_text())
    grains=[Grain(**g) for g in fixture['grains']]
    try:
        advance_contacts(grains,fixture['gravity'],.05,circular_planes(32),max_iterations=256,tolerance=1e-7)
        raise RuntimeError('Captured PGS failure no longer reproduces')
    except ContactConvergenceError as error: contacts=error.contacts
    report=[]
    for precision,tolerance in [('float64',1e-9),('float32',1e-7)]:
        trace=[]
        result,history=refine(grains,contacts,fixture['gravity'],.05,tolerance=tolerance,precision=precision,trace=trace)
        report.append(dict(precision=precision,residual=result.residual,history=history,systems=trace))
    (ROOT/'reports/contact-refinement-precision.json').write_text(json.dumps(report,indent=2))
    cases=[]
    def append(name,a,rhs):
        a=np.asarray(a,dtype=np.float32);rhs=np.asarray(rhs,dtype=np.float32)
        x,_,rank,_=np.linalg.lstsq(a,rhs,rcond=1e-6)
        cases.append(dict(name=name,size=len(rhs),matrix=a.reshape(-1).tolist(),rhs=rhs.tolist(),expected=x.tolist(),rank=int(rank)))
    for i,system in enumerate(report[1]['systems']):append(f'active_{i}',system['matrix'],system['rhs'])
    append('zero',np.zeros((4,4)),[1,2,3,4])
    append('diagonal_singular',np.diag([2,0,4]),[2,7,8])
    random=np.random.default_rng(709)
    q,_=np.linalg.qr(random.normal(size=(32,32)));v,_=np.linalg.qr(random.normal(size=(32,32)))
    append('dense_full',q@np.diag(np.linspace(1,10,32))@v.T,random.normal(size=32))
    append('dense_rank31',q@np.diag([0]+list(np.linspace(1,10,31)))@v.T,random.normal(size=32))
    (ROOT/'reports/active-svd-fixtures.json').write_text(json.dumps(dict(cases=cases)))
    print('Precision oracles and',len(cases),'GPU SVD fixtures generated')
if __name__=='__main__':main()
