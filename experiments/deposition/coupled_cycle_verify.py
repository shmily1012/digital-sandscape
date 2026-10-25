"""Independent audit of every committed coupled GPU step."""
import json,struct,math,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.grain_coupling import Grain,forces,face_weights

def records(name,fmt):return list(struct.iter_unpack(fmt,(ROOT/f'reports/coupled-cycle-{name}.bin').read_bytes()))
def f32(x):return struct.unpack('<f',struct.pack('<f',x))[0]
def main():
    fixture=json.loads((ROOT/'reports/coupled-cycle-fixtures.json').read_text());report=json.loads((ROOT/'reports/coupled-cycle-validation.json').read_text())
    grid=DarcyGrid(32,fixture['base']['geometry']['active']);n=len(fixture['initial']);nc=n*(n-1)//2+n*len(fixture['planes'])
    particles=records('particles','<8f');contacts=records('forces','<4f4i4f');matrix=records('matrix','<f');net=records('net','<2f');flux=records('flux','<f')
    previous=[Grain(*(f32(g[k]) for k in ('x','y','radius','drag','density')),g['material']) for g in fixture['initial']]
    rows=[];failures=int(report['accepted']!=80 or not report['recovery_tested'])
    for frame in range(report['accepted']):
        current=particles[frame*n:(frame+1)*n];c=contacts[frame*nc:(frame+1)*nc];q=net[frame*n:(frame+1)*n];u=[x[0] for x in flux[frame*len(grid.faces):(frame+1)*len(grid.faces)]]
        m=[x[0] for x in matrix[frame*4*n*n:(frame+1)*4*n*n]]
        gravity=fixture['steps'][frame]['gravity'];dt=fixture['dt']
        force=[list(f) for f in forces(previous,gravity)];cone=0.
        for nx,ny,gap,mn,i,j,_,_,ln,lt,mt,_ in c:
            cone=max(cone,-ln,abs(lt)-.5*ln);f=(nx*ln-ny*lt,ny*ln+nx*lt)
            for axis in (0,1):
                force[i][axis]+=f[axis]
                if j>=0:force[j][axis]-=f[axis]
        flat=[x for f in force for x in f];velocity=[sum(a*b for a,b in zip(m[r*2*n:(r+1)*2*n],flat)) for r in range(2*n)]
        residual=power=0.
        for nx,ny,gap,mn,i,j,_,_,ln,lt,mt,_ in c:
            vx,vy=[velocity[2*i+a]-(velocity[2*j+a] if j>=0 else 0) for a in (0,1)]
            un=nx*vx+ny*vy+gap/dt;ut=-ny*vx+nx*vy;bound=.5*max(0,ln)
            residual=max(residual,mn*abs(ln-max(0,ln-un/mn)),mt*abs(lt-min(bound,max(-bound,lt-ut/mt))))
            power+=lt*ut
        position_error=max(math.hypot(g[0]-old.x-dt*velocity[2*i],g[1]-old.y-dt*velocity[2*i+1]) for i,(g,old) in enumerate(zip(current,previous)))
        weights=[face_weights(grid,g) for g in previous]
        source=[mob*sum(w[k]*f[a] for w,f in zip(weights,q))/grid.h**2 for k,(_,_,mob,a) in enumerate(grid.faces)]
        scale=max(map(abs,source),default=0.)
        oracle=grid.project([x/scale for x in source]) if scale else grid.project(source)
        expected=[x*scale for x in oracle.mixture] if scale else oracle.mixture
        flux_error=max(abs(a-b) for a,b in zip(u,expected));divergence=max(map(abs,grid.divergence(u)))
        threshold=2e-6+4.76837158203125e-7*max(map(abs,grid.divergence(source)))
        identity=all(g[2:6]==(old.radius,old.drag,old.density,old.material) for g,old in zip(current,previous))
        finite=all(math.isfinite(x) for g in current for x in g) and all(math.isfinite(x) for x in u+flat)
        gap=min(math.dist(g[:2],h[:2])-g[2]-h[2] for i,g in enumerate(current) for h in current[:i])
        wall=min(-g[1]+.525-g[2] for g in current)
        force_error=max(abs(a-b) for f,r in zip(force,q) for a,b in zip(f,r))
        failed=int(not identity or not finite or gap< -2e-7 or wall< -2e-7 or residual>2e-7 or cone>1e-10 or power>1e-8 or position_error>2e-7 or flux_error>2e-6 or divergence>threshold+1e-6 or force_error>1e-8)
        failures+=failed;rows.append(dict(step=frame+1,residual=residual,flux_error=flux_error,divergence=divergence,pressure_threshold=threshold,position_error=position_error,force_error=force_error,failures=failed))
        previous=[Grain(*g[:6]) for g in current]
    result=dict(failures=failures,frames=report['accepted'],steps=rows,scope='independent per-step double force balance and CPU pressure; point-force model only')
    (ROOT/'reports/coupled-cycle-independent.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(dict(failures=failures,frames=report['accepted'],max_contact_residual=max((r['residual'] for r in rows),default=0),max_flux_error=max((r['flux_error'] for r in rows),default=0))))
    if failures:raise SystemExit(1)
if __name__=='__main__':main()
