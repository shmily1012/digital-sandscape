import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.kernel_self_response import build_kernel,estimate
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,calibrate_self_response,forces

def main():
    kernel=build_kernel()
    (ROOT/'reports/self-response-kernel.json').write_text(json.dumps(kernel),encoding='utf-8')
    rows=[]
    for n in (16,32,64):
        grid=DarcyGrid(n,circle_mask(n))
        for x,y in ((.5,.5),(.473,.521),(.6,.4),(.7,.5)):
            grain=Grain(x,y,.012,.04,2.65,1)
            try:fast=estimate(grid,grain,kernel)
            except ValueError:
                rows.append(dict(size=n,position=[x,y],accepted=False));continue
            exact=calibrate_self_response(grid,[grain])[0][0]
            force=forces([grain],(.6,.8))[0]
            speed_error=max(abs(sum((fast[2*a+b]-exact[2*a+b])*force[b] for b in range(2))) for a in range(2))
            rows.append(dict(size=n,position=[x,y],accepted=True,exact=exact,estimate=fast,matrix_error=max(abs(a-b) for a,b in zip(fast,exact)),speed_error=speed_error,relative_speed_error=speed_error/(sum(v*v for v in force)**.5/grain.drag)))
    report=dict(kernel_coefficients=4*9*9,rows=rows,scope='CPU prototype: exact interior discrete kernel, approximate smooth-circle boundary; not integrated into evolution')
    report['failures']=sum(row['relative_speed_error']>0.01 for row in rows if row['accepted'])
    (ROOT/'reports/kernel-self-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))
    if report['failures']:raise SystemExit(1)

if __name__=='__main__':main()
