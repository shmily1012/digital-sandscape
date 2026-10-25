"""Checkpoint fixture for GPU active-system assembly; no prebuilt GPU matrix."""
from pathlib import Path
import sys,json
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
import numpy as np
from experiments.deposition.contact_particles import advance_contacts,circular_planes,ContactConvergenceError
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain

def main():
    f=json.loads((ROOT/'tests/fixtures/contact_gpu_failure_232.json').read_text());grains=[Grain(**g) for g in f['grains']]
    try:
        advance_contacts(grains,f['gravity'],.05,circular_planes(32),max_iterations=256,tolerance=1e-7)
        raise RuntimeError('Checkpoint no longer reproduces')
    except ContactConvergenceError as e:contacts=e.contacts
    trace=[];refine(grains,contacts,f['gravity'],.05,tolerance=1e-7,precision='float32',trace=trace)
    size=trace[0]['matrix_size']
    if size>32:raise RuntimeError('Active system exceeds GPU experiment capacity')
    a=np.eye(32,dtype=np.float32)*100;a[:size,:size]=np.asarray(trace[0]['matrix']);rhs=np.zeros(32,dtype=np.float32);rhs[:size]=trace[0]['rhs']
    x,_,rank,_=np.linalg.lstsq(a,rhs,rcond=1e-6)
    report=dict(grains=[asdict(g) for g in grains],contacts=[list(c) for c in contacts],gravity=f['gravity'],dt=.05,matrix=a.reshape(-1).tolist(),rhs=rhs.tolist(),expected=x.tolist(),rank=int(rank),active_contacts=size//2,selected_contacts=trace[0]['selected_contacts'])
    (ROOT/'reports/active-system-fixture.json').write_text(json.dumps(report))
if __name__=='__main__':main()
