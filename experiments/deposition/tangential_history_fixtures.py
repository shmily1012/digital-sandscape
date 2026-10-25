"""CPU oracle inputs for persistent GPU spring updates and rejected transactions."""
from pathlib import Path
import sys,json,math,struct
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.deposition.tangential_history import TangentialState,update_tangent

def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]
def main():
    count=130;states=[TangentialState(0.,100.) for _ in range(count)];metrics=[[0.]*8 for _ in range(count)];steps=[]
    bad={7:'negative_normal',15:'changed_id',23:'changed_stiffness',31:'nan'}
    for tick in range(40):
        inputs=[];next_states=[];next_metrics=[]
        for i,old in enumerate(states):
            slip=f32(.017*math.sin(i*.37+tick*.2));normal=f32(1+math.sin(i*.11+tick*.3));active=(tick+i)%17!=0
            inputs.append([1000+i,2000+i,slip,normal,100.,.5,1. if active else 0.,0.])
            if active:
                r=update_tangent(old,slip,normal,100.,.5)
                next_states.append(TangentialState(f32(r.state.elastic_slip),100.))
                next_metrics.append([r.force,r.elastic_energy,r.plastic_dissipation,r.implicit_dissipation,r.work_into_contact,0.,0.,0.])
            else:
                next_states.append(TangentialState(0.,100.));next_metrics.append([0.,0.,0.,0.,0.,.5*100*old.elastic_slip**2,0.,0.])
        accepted=tick not in bad
        if accepted:states=next_states;metrics=next_metrics
        steps.append(dict(tick=tick,inputs=inputs,accepted=accepted,fault=bad.get(tick,''),expected_xi=[s.elastic_slip for s in states],expected_metrics=metrics))
    (ROOT/'reports/tangential-history-fixtures.json').write_text(json.dumps(dict(count=count,steps=steps)),encoding='utf-8')
if __name__=='__main__':main()
