"""CPU pressure oracle for GPU contact-force feedback and published carrier flux."""
from pathlib import Path
import json,sys,struct,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.grain_coupling import Grain,face_weights,forces

def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]
def read(name):return [v[0] for v in struct.iter_unpack('<f',(ROOT/name).read_bytes())]
def main():
    fixture=json.loads((ROOT/'reports/feedback-contact-fixtures.json').read_text());grid=DarcyGrid(32,fixture['base']['geometry']['active']);rows=[];failures=0
    for case in fixture['cases']:
        flux=read(f"reports/feedback-{case['name']}-flux.bin")
        if not case['accepted']:
            failures+=int(any(flux));continue
        grains=[Grain(*(f32(g[k]) for k in ('x','y','radius','drag','density')),g['material']) for g in case['grains']]
        q=read(f"reports/feedback-{case['name']}-net.bin");net=[q[i:i+2] for i in range(0,len(q),2)]
        expected_net=[list(f) for f in forces(grains,case['gravity'])]
        contacts=list(struct.iter_unpack('<4f4i4f',(ROOT/f"reports/feedback-{case['name']}-forces.bin").read_bytes()))
        for nx,ny,_,_,i,j,_,_,ln,lt,_,_ in contacts:
            f=(nx*ln-ny*lt,ny*ln+nx*lt)
            for axis in (0,1):
                expected_net[i][axis]+=f[axis]
                if j>=0:expected_net[j][axis]-=f[axis]
        net_error=max(abs(a-b) for left,right in zip(net,expected_net) for a,b in zip(left,right))
        weights=[face_weights(grid,g) for g in grains]
        source=[m*sum(w[k]*f[a] for w,f in zip(weights,net))/grid.h**2 for k,(_,_,m,a) in enumerate(grid.faces)]
        scale=max(map(abs,source),default=0.)
        oracle=grid.project([x/scale for x in source]) if scale else grid.project(source)
        expected=[u*scale for u in oracle.mixture] if scale else oracle.mixture
        error=max(abs(a-b) for a,b in zip(flux,expected));divergence=max(map(abs,grid.divergence(flux)))
        threshold=2e-6+4.76837158203125e-7*max(map(abs,grid.divergence(source)))
        peak=max(map(abs,flux));net_norm=max(math.hypot(*f) for f in net)
        valid=all(math.isfinite(v) for v in flux+q)
        failed=int(not valid or net_error>1e-8 or error>2e-6 or divergence>threshold+1e-6)
        if case['name']=='rest':failed+=int(net_norm>1e-7 or peak>1e-5)
        if case['name']=='release':failed+=int(peak<1e-4)
        failures+=failed;rows.append(dict(name=case['name'],net_force_error=net_error,flux_error=error,divergence=divergence,pressure_threshold=threshold,peak_flux=peak,net_force_norm=net_norm,failures=failed))
    result=dict(failures=failures,cases=rows,scope='GPU net load and final carrier flux against independent CPU pressure solve; single-step point-force model')
    (ROOT/'reports/feedback-carrier-independent.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
    if failures:raise SystemExit(1)
if __name__=='__main__':main()
