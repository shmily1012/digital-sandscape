"""Audit GPU trajectory with double force balance and independent CPU solves."""
import json, math, struct, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_particles import advance_contacts, circular_planes, ContactConvergenceError
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain, forces

def main():
    fixture=json.loads((ROOT/'reports/contact-cycle-fixtures.json').read_text())['cases'][0]
    report=json.loads((ROOT/'reports/refined-cycle-validation.json').read_text())
    raw=(ROOT/'reports/refined-cycle-trace.bin').read_bytes()
    contacts_raw=(ROOT/'reports/refined-cycle-forces.bin').read_bytes()
    count=len(fixture['initial']); frame_size=count*32
    contact_count=count*(count-1)//2+count*len(fixture['planes'])
    assert len(raw)==report['accepted']*frame_size
    assert len(contacts_raw)==report['accepted']*contact_count*48
    previous=[tuple(struct.unpack('<f',struct.pack('<f',g[k]))[0] for k in ('x','y','radius','drag','density','material'))+(0.,0.) for g in fixture['initial']]
    minimum_pair=minimum_wall=float('inf')
    max_residual=max_cone=max_power=max_position=max_oracle=0.
    for frame,offset in enumerate(range(0,len(raw),frame_size)):
        grains=list(struct.iter_unpack('<8f',raw[offset:offset+frame_size]))
        source=[Grain(*g[:6]) for g in previous]
        gravity=(0.,1.) if frame<160 else (.6,-.8)
        net=[list(f) for f in forces(source,gravity)]
        contacts=list(struct.iter_unpack('<4f4i4f',contacts_raw[frame*contact_count*48:(frame+1)*contact_count*48]))
        for c in contacts:
            nx,ny,_,_=c[:4];i,j=c[4:6];ln,lt=c[8:10]
            assert all(math.isfinite(v) for v in c)
            assert 0<=i<count and -1<=j<count
            f=(nx*ln-ny*lt,ny*ln+nx*lt)
            for a in (0,1):
                net[i][a]+=f[a]
                if j>=0:net[j][a]-=f[a]
            max_cone=max(max_cone,-ln,abs(lt)-.5*ln)
        velocity=[[v/g.drag for v in force] for g,force in zip(source,net)]
        power=0.
        for c in contacts:
            nx,ny,gap,m=c[:4];i,j=c[4:6];ln,lt=c[8:10]
            vx,vy=[velocity[i][a]-(velocity[j][a] if j>=0 else 0) for a in (0,1)]
            un=nx*vx+ny*vy+gap/.05;ut=-ny*vx+nx*vy;bound=.5*max(0,ln)
            max_residual=max(max_residual,m*abs(ln-max(0,ln-un/m)),m*abs(lt-min(bound,max(-bound,lt-ut/m))))
            power+=lt*ut
        max_power=max(max_power,power)
        try:oracle=advance_contacts(source,gravity,.05,circular_planes(32),max_iterations=256,tolerance=1e-7)
        except ContactConvergenceError as error:oracle,_=refine(source,error.contacts,gravity,.05)
        for i,g in enumerate(grains):
            assert all(math.isfinite(v) for v in g)
            assert g[2:]==previous[i][2:]
            max_position=max(max_position,math.hypot(*(g[a]-previous[i][a]-.05*velocity[i][a] for a in (0,1))))
            max_oracle=max(max_oracle,math.hypot(g[0]-oracle.grains[i].x,g[1]-oracle.grains[i].y))
            for other in grains[:i]:minimum_pair=min(minimum_pair,math.dist(g[:2],other[:2])-g[2]-other[2])
            for nx,ny,d,_ in fixture['planes']:minimum_wall=min(minimum_wall,nx*g[0]+ny*g[1]-d-g[2])
        previous=grains
    result=dict(frames=report['accepted'],minimum_pair_gap=minimum_pair,minimum_wall_gap=minimum_wall,identity=True,finite=True,max_residual=max_residual,max_cone_error=max_cone,max_friction_power=max_power,max_force_position_error=max_position,max_cpu_position_error=max_oracle,scope='16-grain local-drag contact cycle; not full liquid sand art')
    result['failures']=sum((report['accepted']!=240,minimum_pair< -2e-7,minimum_wall< -2e-7,max_residual>2e-7,max_cone>1e-10,max_power>1e-9,max_position>2e-7,max_oracle>2e-6))
    (ROOT/'reports/refined-cycle-independent.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
    if result['failures']:raise SystemExit(1)
if __name__=='__main__':main()

