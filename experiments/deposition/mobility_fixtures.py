"""Known-mobility CPU fixtures; calibration is deliberately not claimed as GPU work."""
import sys,json
from pathlib import Path
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.grain_coupling import Grain,calibrate_self_response,carrier_response
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.deposition.contact_particles import Plane,advance_contacts

def main():
    grid=DarcyGrid(16,circle_mask(16));floor=[Plane(0,-1,-.525)]
    resting=[Grain(.5,.5,.025,.002,2.65,1)]
    pair=[Grain(.475,.5,.025,.002,2.65,1),Grain(.525,.5,.025,.002,2.2,2)]
    free=[Grain(.42,.43,.012,.04,2.65,1),Grain(.58,.43,.01,.03,2.2,2)]
    cases=[]
    for name,grains,gravity,planes in [('rest',resting,(0,1),floor),('release',resting,(0,-1),floor),('slide',pair,(.6,.8),floor),('free',free,(.6,.8),floor)]:
        _,matrix=calibrate_self_response(grid,grains)
        result=advance_contacts(grains,gravity,.01,planes,mobility_matrix=matrix,tolerance=1e-7)
        cases.append(dict(name=name,grains=[asdict(g) for g in grains],gravity=gravity,planes=[[p.nx,p.ny,p.offset,0] for p in planes],matrix=matrix,expected=[asdict(g) for g in result.grains],accepted=True,budget=2000))
    for name,matrix in [('nonreciprocal',[[500,2],[0,500]]),('indefinite',[[1,2],[2,1]])]:
        case=dict(cases[0]);case.update(name=name,matrix=matrix,expected=case['grains'],accepted=False);cases.append(case)
    case=dict(cases[2]);case.update(name='budget_rejected',budget=1,expected=case['grains'],accepted=False);cases.append(case)
    (ROOT/'reports/mobility-contact-fixtures.json').write_text(json.dumps(dict(cases=cases),indent=2))
    base=json.loads((ROOT/'reports/online-grain-fixtures.json').read_text())['base']
    grid32=DarcyGrid(32,base['geometry']['active'])
    calibrated=[]
    for case in cases[:4]:
        item=dict(case);grains=[Grain(**g) for g in item['grains']]
        _,item['matrix']=calibrate_self_response(grid32,grains)
        planes=[Plane(*p[:3]) for p in item['planes']]
        result=advance_contacts(grains,item['gravity'],.01,planes,mobility_matrix=item['matrix'],tolerance=1e-7)
        item['expected']=[asdict(g) for g in result.grains];item['calibration_budget']=96
        calibrated.append(item)
    rejected=dict(calibrated[2]);rejected.update(name='pressure_budget_rejected',calibration_budget=1,accepted=False,expected=rejected['grains']);calibrated.append(rejected)
    touching=[Grain(.488,.5,.012,.04,2.65,1),Grain(.512,.5,.012,.04,2.2,2)]
    raw=carrier_response(grid32,touching)
    for i,g in enumerate(touching):
        for a in range(2):
            for b in range(2):raw[2*i+a][2*i+b]=1/g.drag if a==b else 0.
    try:calibrate_self_response(grid32,touching)
    except ValueError as error:
        if 'positive definite' not in str(error):raise
    else:raise AssertionError('Touching scope witness unexpectedly accepted')
    calibrated.append(dict(name='touching_mobility_rejected',grains=[asdict(g) for g in touching],expected=[asdict(g) for g in touching],planes=[[0,-1,-.525,0]],gravity=[0,1],matrix=raw,accepted=False,budget=2000,calibration_budget=96))
    (ROOT/'reports/calibrated-contact-fixtures.json').write_text(json.dumps(dict(base=base,cases=calibrated),indent=2))
    feedback=[dict(case,feedback_budget=96) for case in calibrated]
    rejected=dict(feedback[1]);rejected.update(name='feedback_budget_rejected',feedback_budget=1,accepted=False,expected=rejected['grains']);feedback.append(rejected)
    (ROOT/'reports/feedback-contact-fixtures.json').write_text(json.dumps(dict(base=base,cases=feedback),indent=2))
    print('Generated' ,len(cases),'known-mobility and',len(calibrated),'GPU-calibrated cases')
if __name__=='__main__':main()
