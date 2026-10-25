"""Independent audit of stored GPU forces under the uploaded mobility matrix."""
from pathlib import Path
import json,struct,math,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.grain_coupling import Grain,forces

def f32(x):return struct.unpack('<f',struct.pack('<f',x))[0]
def main():
    prefix='feedback' if '--feedback' in sys.argv else ('calibrated' if '--calibrated' in sys.argv else 'mobility')
    cases=json.loads((ROOT/f'reports/{prefix}-contact-fixtures.json').read_text())['cases'];rows=[];failures=0
    for case in cases:
        if not case['accepted']:continue
        grains=[Grain(*(f32(g[k]) for k in ('x','y','radius','drag','density')),g['material']) for g in case['grains']]
        matrix=[[f32(x) for x in row] for row in case['matrix']]
        if prefix in ('calibrated','feedback'):
            values=[v[0] for v in struct.iter_unpack('<f',(ROOT/f"reports/{prefix}-{case['name']}-matrix.bin").read_bytes())]
            size=2*len(grains);matrix=[values[i:i+size] for i in range(0,len(values),size)]
        contacts=list(struct.iter_unpack('<4f4i4f',(ROOT/f"reports/{prefix}-{case['name']}-forces.bin").read_bytes()))
        output=list(struct.iter_unpack('<8f',(ROOT/f"reports/{prefix}-{case['name']}-particles.bin").read_bytes()))
        net=[list(f) for f in forces(grains,case['gravity'])]
        cone=0.
        for nx,ny,gap,mn,i,j,_,_,ln,lt,mt,_ in contacts:
            cone=max(cone,-ln,abs(lt)-.5*ln)
            force=(nx*ln-ny*lt,ny*ln+nx*lt)
            for a in (0,1):
                net[i][a]+=force[a]
                if j>=0:net[j][a]-=force[a]
        flat=[v for f in net for v in f]
        v=[sum(a*b for a,b in zip(row,flat)) for row in matrix]
        residual=power=0.
        for nx,ny,gap,mn,i,j,_,_,ln,lt,mt,_ in contacts:
            vx,vy=[v[2*i+a]-(v[2*j+a] if j>=0 else 0) for a in (0,1)]
            normal=nx*vx+ny*vy+gap/.01;tangent=-ny*vx+nx*vy;bound=.5*max(0,ln)
            residual=max(residual,mn*abs(ln-max(0,ln-normal/mn)),mt*abs(lt-min(bound,max(-bound,lt-tangent/mt))))
            power+=lt*tangent
        error=max(math.hypot(record[0]-g.x-.01*v[2*i],record[1]-g.y-.01*v[2*i+1]) for i,(record,g) in enumerate(zip(output,grains)))
        valid=all(math.isfinite(x) for row in output for x in row)
        valid &= all(record[2:6]==(g.radius,g.drag,g.density,g.material) for record,g in zip(output,grains))
        failure=int(not valid or residual>2e-7 or cone>1e-10 or power>1e-8 or error>2e-7)
        failures+=failure;rows.append(dict(name=case['name'],residual=residual,cone_error=cone,friction_power=power,force_position_error=error,identity=valid,failures=failure))
    result=dict(failures=failures,cases=rows,scope=prefix+' mobility; independent double force audit; see feedback_verify for carrier validation')
    (ROOT/f'reports/{prefix}-contact-independent.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
    if failures:raise SystemExit(1)
if __name__=='__main__':main()
