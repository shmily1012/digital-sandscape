"""Matched dense/operator contact experiments; no product performance claim."""
from pathlib import Path
import sys,json,time,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,forces
from experiments.deposition.contact_particles import advance_contacts,Plane
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.operator_contacts import advance_operator_contacts

def main():
    rows=[]
    for count in (4,16):
        side=math.isqrt(count)
        grains=[Grain(.5+(x-(side-1)/2)*.07,.605-y*.07,.035,.04,2.65-.1*((x+y)%3),1+(x+y)%3) for y in range(side) for x in range(side)]
        grid=DarcyGrid(24,circle_mask(24));planes=[Plane(0,-1,-.64)]
        for gravity,friction in (((0,1),.5),((1,1),.5),((0,-1),.5),((0,-1),0.)):
            start=time.perf_counter();dense=DrainageResistance(grid,grains,geometric=True)
            expected=advance_contacts(grains,gravity,.01,planes,friction=friction,mobility_matrix=dense.mobility,tolerance=1e-12)
            dense_ms=1000*(time.perf_counter()-start)
            start=time.perf_counter();result=advance_operator_contacts(grid,grains,gravity,.01,planes,friction=friction)
            operator_ms=1000*(time.perf_counter()-start)
            error=max(abs(a-b) for va,vb in zip(expected.velocity,result.contact.velocity) for a,b in zip(va,vb))
            def balance(contact):
                net=[v for pair in forces(grains,gravity) for v in pair]
                for i,j,nx,ny,_,ln,lt in contact.reactions:
                    fx,fy=nx*ln-ny*lt,ny*ln+nx*lt
                    net[2*i]+=fx;net[2*i+1]+=fy
                    if j>=0:net[2*j]-=fx;net[2*j+1]-=fy
                velocity=[v for pair in contact.velocity for v in pair]
                hv=[sum(a*b for a,b in zip(row,velocity)) for row in dense.resistance]
                return max(abs(a-b) for a,b in zip(hv,net))
            def contact_law(contact):
                violation=0.
                for i,j,nx,ny,gap,ln,lt in contact.reactions:
                    vx,vy=contact.velocity[i]
                    if j>=0:vx-=contact.velocity[j][0];vy-=contact.velocity[j][1]
                    normal=vx*nx+vy*ny+gap/.01
                    tangent=-vx*ny+vy*nx
                    violation=max(violation,-ln,-normal,abs(ln*normal),abs(lt)-friction*ln,
                                  abs(lt*tangent+friction*ln*abs(tangent)))
                return violation
            row=dict(particles=count,gravity=gravity,friction=friction,accepted=error<=1e-8,
                     dense_force_balance=balance(expected),operator_force_balance=balance(result.contact),
                     dense_contact_law=contact_law(expected),operator_contact_law=contact_law(result.contact),dense_ms=dense_ms,operator_ms=operator_ms,
                     outer_iterations=result.outer_iterations,pressure_solves=result.pressure_solves,
                     velocity_error=error,force_residual=result.force_residual,contact_residual=result.contact.residual)
            rows.append(row);print(json.dumps(row),flush=True)
    (ROOT/'reports/operator-contact-validation.json').write_text(json.dumps(dict(cases=rows,failures=sum(not r["accepted"] for r in rows),scope='Single CPU contact step per case, three gravities, no liquid finite-step or persistent cycle integration'),indent=2),encoding='utf-8')
    if any(not r['accepted'] for r in rows):raise SystemExit('Contact equivalence gate failed; results retained for diagnosis')
if __name__=='__main__':main()
