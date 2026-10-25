"""Solve the active linear branches of the saved friction ordering witness."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
import numpy as np
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,forces
from experiments.deposition.drainage_resistance import DrainageResistance

def main():
    source=json.loads((ROOT/'reports/friction-order-audit.json').read_text(encoding='utf-8'))
    grains=[Grain(**g) for g in source['grains']];n=2*len(grains)
    model=DrainageResistance(DarcyGrid(24,circle_mask(24)),grains,geometric=True)
    outputs=[]
    for case in [r for r in source['rows'] if r['friction']==.5 and r['relaxation']==1 and r['order'] in ('forward','reverse')]:
        contacts=case['reactions'];size=n+2*len(contacts)
        matrix=np.zeros((size,size));rhs=np.zeros(size);matrix[:n,:n]=model.resistance
        rhs[:n]=[v for pair in forces(grains,(0,-1)) for v in pair]
        velocity=np.asarray(case['velocity']).reshape(-1);modes=[];directions=[]
        for k,(i,j,nx,ny,gap,ln,lt) in enumerate(contacts):
            normal=np.zeros(n);tangent=np.zeros(n)
            normal[2*i:2*i+2]=[nx,ny];tangent[2*i:2*i+2]=[-ny,nx]
            if j>=0:normal[2*j:2*j+2]=[-nx,-ny];tangent[2*j:2*j+2]=[ny,-nx]
            row=n+2*k;matrix[:n,row]=-normal;matrix[:n,row+1]=-tangent
            ut=float(tangent@velocity)
            if ln<1e-9:
                matrix[row,row]=1;matrix[row+1,row+1]=1;mode='open'
            else:
                matrix[row,:n]=normal;rhs[row]=-gap/.01
                if abs(ut)<1e-8:matrix[row+1,:n]=tangent;mode='stick'
                else:
                    matrix[row+1,row+1]=1;matrix[row+1,row]=.5*np.sign(ut);mode='slide'
            modes.append(mode);directions.append((normal,tangent,gap))
        original=np.concatenate([velocity,np.asarray([[c[5],c[6]] for c in contacts]).reshape(-1)])
        correction,_,rank,singular=np.linalg.lstsq(matrix,rhs-matrix@original,rcond=1e-12)
        solved=original+correction
        violation=0.
        for k,(normal,tangent,gap) in enumerate(directions):
            ln,lt=solved[n+2*k:n+2*k+2];un=normal@solved[:n]+gap/.01;ut=tangent@solved[:n]
            violation=max(violation,-ln,-un,abs(ln*un),abs(lt)-.5*ln,abs(lt*ut+.5*ln*abs(ut)))
        row=dict(order=case['order'],rank=int(rank),dimension=size,minimum_singular=float(singular[-1]),
                 linear_residual=float(max(abs(matrix@solved-rhs))),contact_violation=float(violation),
                 original_velocity_difference=float(max(abs(solved[:n]-velocity))),velocity=solved[:n].tolist(),modes=modes)
        outputs.append(row);print(json.dumps({k:v for k,v in row.items() if k not in ('velocity','modes')}),flush=True)
    difference=max(abs(a-b) for a,b in zip(outputs[0]['velocity'],outputs[1]['velocity']))
    report=dict(scope='Floating-point active-branch reconstruction, not an exact-arithmetic uniqueness proof',branches=outputs,branch_velocity_difference=difference)
    (ROOT/'reports/friction-branch-audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(dict(branch_velocity_difference=difference)))
    if any(b['linear_residual']>1e-10 or b['contact_violation']>1e-10 for b in outputs):raise RuntimeError('Branch certificate failed')
    if difference<1e-5:raise RuntimeError('Captured distinct branches not reproduced')
if __name__=='__main__':main()
