"""Repeat captured order-sensitive network with explicit spring stiffness."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.history_contacts import advance_history_contacts
from experiments.deposition.contact_particles import Plane

def main():
    source=json.loads((ROOT/'reports/friction-order-audit.json').read_text(encoding='utf-8'))
    grains=[Grain(**g) for g in source['grains']]
    model=DrainageResistance(DarcyGrid(24,circle_mask(24)),grains,geometric=True)
    rows=[]
    for stiffness in (.1,1.,10.,100.):
        reference=None
        for name,order in [('forward',list(range(16))),('reverse',list(reversed(range(16)))),('columns',[y*4+x for x in range(4) for y in range(4)])]:
            for relaxation in (1.,.5):
                indices=[2*i+a for i in order for a in (0,1)]
                matrix=[[model.mobility[i][j] for j in indices] for i in indices]
                r=advance_history_contacts([grains[i] for i in order],order,{},(0,-1),.01,
                        planes=[Plane(0,-1,-.64)],plane_ids=[-1],stiffness=stiffness,
                        mobility_matrix=matrix,max_iterations=10000,relaxation=relaxation)
                velocity=[None]*16
                for i,v in zip(order,r.contact.velocity):velocity[i]=v
                if reference is None:reference=velocity
                difference=max(abs(a-b) for va,vb in zip(reference,velocity) for a,b in zip(va,vb))
                energy_error=abs(r.work_into_springs-r.elastic_energy-r.dissipated)
                row=dict(stiffness=stiffness,order=name,relaxation=relaxation,iterations=r.contact.iterations,
                         velocity_difference=difference,constitutive_error=r.constitutive_error,energy_error=energy_error,
                         velocity=velocity)
                rows.append(row)
        print(json.dumps(dict(stiffness=stiffness,max_difference=max(r['velocity_difference'] for r in rows if r['stiffness']==stiffness))),flush=True)
    report=dict(scope='Single-step spring candidate with initially empty history; no guarantee across stiffness, timestep or continued cycles',cases=rows,
                failures=sum(r['velocity_difference']>1e-8 or r['energy_error']>1e-10 for r in rows))
    (ROOT/'reports/history-contact-order.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if report['failures']:raise SystemExit('Spring ordering audit failed')
if __name__=='__main__':main()
