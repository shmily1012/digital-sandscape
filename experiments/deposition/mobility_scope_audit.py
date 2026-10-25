"""Scope audit: self-block replacement can invalidate contact-scale mobility."""
from pathlib import Path
import sys,json,math
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
import numpy as np
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,carrier_response,calibrate_self_response

def main():
    rows=[];witness=None
    for side in (16,32,64):
        grid=DarcyGrid(side,circle_mask(side))
        for separation in (.024,.05,.1,.16):
            # Touching, valid geometry; support width remains a numerical grid quantity.
            grains=[Grain(.5-separation/2,.5,separation/2,.02,2.65,1),Grain(.5+separation/2,.5,separation/2,.02,2.2,2)]
            raw=np.asarray(carrier_response(grid,grains));raw=(raw+raw.T)/2
            raw_min=float(np.linalg.eigvalsh(raw)[0])
            for drag in (.002,.02,.04):
                corrected=raw.copy()
                corrected[:2,:2]=np.eye(2)/drag;corrected[2:,2:]=np.eye(2)/drag
                eigen,vectors=np.linalg.eigh(corrected);minimum=float(eigen[0])
                row=dict(side=side,separation=separation,radius=separation/2,drag=drag,raw_min_eigenvalue=raw_min,corrected_min_eigenvalue=minimum,valid=minimum>1e-10)
                rows.append(row)
                if minimum< -1 and witness is None:
                    force=vectors[:,0];velocity=corrected@force
                    witness=dict(**row,force=force.tolist(),velocity=velocity.tolist(),work=float(force@velocity),matrix=corrected.tolist())
    result=dict(scope='dimensionless two non-overlapping touching grains; no claim of physical drag calibration',cases=rows,invalid_cases=sum(not r['valid'] for r in rows),witness=witness)
    (ROOT/'reports/mobility-scope-audit.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(dict(cases=len(rows),invalid=result['invalid_cases'],witness=witness)))
    if witness is None:raise SystemExit('Expected breakdown not observed; revise scope assessment')
if __name__=='__main__':main()
