"""Attribute temporal refinements to geometry, contact or solver rejection."""
from pathlib import Path
import sys,json,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.adaptive_history import advance_history_interval

def main():
    grid=DarcyGrid(16,circle_mask(16));kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
    first=advance_operator_history(grid,[Grain(.473,.517,.071,.04,2.65,1)],[10],{},(.4,1),.01,**kw).candidate
    trace=[]
    result=advance_history_interval(grid,first.contact.grains,[10],first.history,(1,1),.04,max_substeps=64,trace=trace,**kw)
    for r in trace:
        if r['worst_face'] is None:continue
        i,j,_,axis=grid.faces[r['worst_face']]
        r['face_axis']=axis
        r['face_center']=[((i%grid.size+j%grid.size)/2+.5)*grid.h,((i//grid.size+j//grid.size)/2+.5)*grid.h]
        center=r['positions'][0];radius=first.contact.grains[0].radius
        r['distance_to_tangent']=abs(abs(r['face_center'][axis]-center[axis])-radius)
    narrow=sorted((r for r in trace if r['accepted']),key=lambda r:r['dt'])[:5]
    report=dict(scope='Single supported disk, trace of existing absolute face-flux criterion; no physical model change',
                attempts=len(trace),contact_failures=sum(r['reason']=='contact' for r in trace),
                smallest_steps=narrow,trace=trace,elapsed=result.elapsed)
    (ROOT/'reports/history-substep-trace.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='trace'}))
if __name__=='__main__':main()
