"""Ordering sensitivity audit for the captured frictional contact discrepancy."""
from pathlib import Path
from dataclasses import asdict
import sys,json,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,forces
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.contact_particles import advance_contacts,Plane

def main():
    grains=[Grain(.5+(x-1.5)*.07,.605-y*.07,.035,.04,2.65-.1*((x+y)%3),1+(x+y)%3) for y in range(4) for x in range(4)]
    grid=DarcyGrid(24,circle_mask(24));model=DrainageResistance(grid,grains,geometric=True)
    orders={'forward':list(range(16)),'reverse':list(reversed(range(16))),'columns':[y*4+x for x in range(4) for y in range(4)]}
    rows=[];base={}
    for friction in (.5,0.):
        for name,order in orders.items():
            for relaxation in (1.,.5):
                indices=[2*i+a for i in order for a in (0,1)]
                mobility=[[model.mobility[i][j] for j in indices] for i in indices]
                ordered=[grains[i] for i in order]
                result=advance_contacts(ordered,(0,-1),.01,[Plane(0,-1,-.64)],friction=friction,
                                        tolerance=1e-12,max_iterations=10000,relaxation=relaxation,mobility_matrix=mobility)
                velocity=[None]*16;net=[list(f) for f in forces(grains,(0,-1))]
                for i,v in zip(order,result.velocity):velocity[i]=v
                reactions=[];law=0.
                for i,j,nx,ny,gap,ln,lt in result.reactions:
                    a=order[i];b=order[j] if j>=0 else -1
                    fx,fy=nx*ln-ny*lt,ny*ln+nx*lt
                    net[a][0]+=fx;net[a][1]+=fy
                    if b>=0:net[b][0]-=fx;net[b][1]-=fy
                    vx,vy=velocity[a]
                    if b>=0:vx-=velocity[b][0];vy-=velocity[b][1]
                    un=vx*nx+vy*ny+gap/.01;ut=-vx*ny+vy*nx
                    law=max(law,-ln,-un,abs(ln*un),abs(lt)-friction*ln,abs(lt*ut+friction*ln*abs(ut)))
                    reactions.append([a,b,nx,ny,gap,ln,lt])
                v=[x for pair in velocity for x in pair];force=[x for pair in net for x in pair]
                balance=max(abs(sum(a*b for a,b in zip(row,v))-f) for row,f in zip(model.resistance,force))
                if friction not in base:base[friction]=v
                difference=max(abs(a-b) for a,b in zip(v,base[friction]))
                row=dict(friction=friction,order=name,relaxation=relaxation,iterations=result.iterations,
                         force_balance=balance,contact_law=law,velocity_difference=difference,
                         velocity=velocity,reactions=reactions)
                rows.append(row)
                print(json.dumps({k:v for k,v in row.items() if k not in ('velocity','reactions')}),flush=True)
    report=dict(scope='Same geometry/mobility, only numerical ordering and relaxation changed; no assertion of exact mathematical nonuniqueness',grains=[asdict(g) for g in grains],rows=rows)
    (ROOT/'reports/friction-order-audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if any(r['force_balance']>1e-10 or r['contact_law']>1e-10 for r in rows):raise RuntimeError('Independent certificates failed')
if __name__=='__main__':main()
