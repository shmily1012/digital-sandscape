"""Independent high-precision residual audit of a captured failed system."""
import json
import math
import hashlib
from decimal import Decimal, localcontext
from pathlib import Path
from grain_cut_cells import boundary_source, boundary_reaction, network, coupled_pressure


if __name__ == '__main__':
    root=Path(__file__).resolve().parents[1]/'reports'
    capture=root/'endpoint-failed-system-before-ic.json'
    if not capture.exists():capture=root/'endpoint-failed-system.json'
    payload=capture.read_bytes();data=json.loads(payload)
    system=data['system'];diagnostic=data['diagnostic'];graph=system['graph']
    p=diagnostic['pressure'];low=diagnostic['low']
    source,weights=boundary_source(graph,system['velocity']);grid,edges=network(graph)
    force=boundary_reaction(graph,weights,p,low)
    terms=[[v] for v in grid.operator(p,low)]
    for region,grain,nx,ny in weights:
        terms[region].append(-system['dt']*(nx*force[grain][0]+ny*force[grain][1])/system['mass'][grain])
    floating=[math.fsum(v) for v in terms]
    D=Decimal.from_float
    with localcontext() as context:
        context.prec=60
        pressure=[D(a)+D(b) for a,b in zip(p,low)]
        actual=[Decimal(0) for _ in pressure]
        reaction=[[Decimal(0),Decimal(0)] for _ in system['mass']]
        for i,j,w in edges:
            q=D(w)*(pressure[i]-pressure[j]);actual[i]+=q;actual[j]-=q
        for region,grain,nx,ny in weights:
            reaction[grain][0]-=D(nx)*pressure[region]
            reaction[grain][1]-=D(ny)*pressure[region]
        for region,grain,nx,ny in weights:
            actual[region]-=D(system['dt'])*(D(nx)*reaction[grain][0]+D(ny)*reaction[grain][1])/D(system['mass'][grain])
        residual=[abs(a-D(b)) for a,b in zip(actual,source)]
        worst=max(range(len(residual)),key=residual.__getitem__)
        report=dict(input_file=capture.name,input_sha256=hashlib.sha256(payload).hexdigest(),
                    nodes=len(p),edges=len(edges),iterations=diagnostic['iterations'],
                    captured_residual=diagnostic['residual'],
                    replay_float_residual=max(abs(a-b) for a,b in zip(floating,source)),
                    decimal_residual=str(residual[worst]),worst_region=worst,
                    operator_roundoff=max(abs(float(a)-b) for a,b in zip(actual,floating)),
                    maximum_pressure=max(map(abs,p)),
                    minimum_conductance=min(w for _,_,w in edges),
                    maximum_conductance=max(w for _,_,w in edges),
                    scope='60-digit residual using the captured float coefficients and high+low pressure; not an accepted solve')
    replay=coupled_pressure(**system)
    report['current_solver']={key:replay[key] for key in ('iterations','residual','continuity','precondition_shift')}
    (root/'endpoint-system-audit.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
