"""Contact refinement trajectory oracle with float32 state checkpoints."""
from pathlib import Path
import sys,json,math,struct,time
from dataclasses import asdict,replace
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_particles import advance_contacts,circular_planes,ContactConvergenceError
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain

def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]
def quantize(g):return Grain(*(f32(v) for v in (g.x,g.y,g.radius,g.drag,g.density)),g.material)
def main():
    initial=[quantize(Grain(.4+.065*x+.002*math.sin(y*5+x),.24+.065*y,.025,.02,2.65,1+(x+y)%3)) for y in range(4) for x in range(4)]
    grains=list(initial);rows=[];failure=None;start=time.perf_counter()
    for step in range(240):
        gravity=(0,1) if step<160 else (.6,-.8)
        history=[]
        try:
            try:result=advance_contacts(grains,gravity,.05,circular_planes(32),max_iterations=256,tolerance=1e-7)
            except ContactConvergenceError as error:result,history=refine(grains,error.contacts,gravity,.05)
        except ValueError as error:
            failure=dict(step=step+1,error=str(error));break
        grains=[quantize(g) for g in result.grains]
        rows.append(dict(step=step+1,residual=result.residual,refinement=history,max_speed=max(math.hypot(*v) for v in result.velocity)))
    report=dict(scope='CPU only; float32 persistent state, double contact solve, global refinement after PGS failure; no GPU change',steps=len(rows),failure=failure,refined_steps=sum(bool(r['refinement']) for r in rows),cpu_seconds=time.perf_counter()-start,rows=rows,initial=[asdict(g) for g in initial],final=[asdict(g) for g in grains],failures=int(failure is not None))
    (ROOT/'reports/contact-refinement-cycle.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','initial','final')}))
    if failure:raise SystemExit(1)
if __name__=='__main__':main()
