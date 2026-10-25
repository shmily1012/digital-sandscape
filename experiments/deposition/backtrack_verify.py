"""Independent double arithmetic checks of GPU contact forces and commit."""
from pathlib import Path
import sys,json,struct,math
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain,forces

def main():
    fixture=json.loads((ROOT/'reports/active-system-fixture.json').read_text())
    source=[Grain(**g) for g in fixture['grains']]
    grains=[Grain(*(struct.unpack('<f',struct.pack('<f',v))[0] for v in (g.x,g.y,g.radius,g.drag,g.density)),g.material) for g in source]
    data=(ROOT/'reports/backtrack-captured_network.bin').read_bytes()
    contacts=[struct.unpack_from('<4f4i4f',data,k*48) for k in range(len(fixture['contacts']))]
    external=forces(grains,fixture['gravity']);net=[list(f) for f in external]
    cone_error=0.
    for c in contacts:
        nx,ny,gap,m=c[:4];i,j=c[4:6];ln,lt=c[8:10]
        f=(nx*ln-ny*lt,ny*ln+nx*lt)
        for a in (0,1):
            net[i][a]+=f[a]
            if j>=0:net[j][a]-=f[a]
        cone_error=max(cone_error,-ln,abs(lt)-.5*ln)
    velocity=[[value/g.drag for value in f] for g,f in zip(grains,net)]
    residual=0.;power=0.
    for c in contacts:
        nx,ny,gap,m=c[:4];i,j=c[4:6];ln,lt=c[8:10]
        v=[velocity[i][a]-(velocity[j][a] if j>=0 else 0) for a in (0,1)]
        un=nx*v[0]+ny*v[1]+gap/fixture['dt'];ut=-ny*v[0]+nx*v[1]
        residual=max(residual,m*abs(ln-max(0,ln-un/m)),m*abs(lt-min(.5*max(0,ln),max(-.5*max(0,ln),lt-ut/m))))
        power+=lt*ut
    result,_=refine(source,fixture['contacts'],fixture['gravity'],fixture['dt'])
    committed=(ROOT/'reports/backtrack-captured_network-particles.bin').read_bytes()
    oracle_error=kinematic_error=0.
    identity=True
    for i,g in enumerate(grains):
        record=struct.unpack_from('<8f',committed,i*32)
        oracle_error=max(oracle_error,math.hypot(record[0]-result.grains[i].x,record[1]-result.grains[i].y))
        kinematic_error=max(kinematic_error,math.hypot(record[0]-g.x-fixture['dt']*velocity[i][0],record[1]-g.y-fixture['dt']*velocity[i][1]))
        identity=identity and record[2:6]==(g.radius,g.drag,g.density,g.material)
    report=dict(independent_contact_residual=residual,cone_error=cone_error,friction_power=power,cpu_oracle_position_error=oracle_error,force_to_position_error=kinematic_error,identity=identity)
    report['failures']=sum((residual>2e-7,cone_error>1e-10,power>1e-10,oracle_error>2e-6,kinematic_error>2e-7,not identity))
    (ROOT/'reports/backtrack-independent-validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
    if report['failures']:raise SystemExit(1)
if __name__=='__main__':main()
