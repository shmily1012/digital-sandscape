"""Audit pressure datum using one common physical region, never fit a force."""
import json
import math
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from grain_volume_reference import fixtures
from grain_contact_impulse_reference import MASS
from grain_cut_cells import build,coupled_contacts,moving_box_gas,boundary_reaction,network
from experiments.liquid.model import add_compensated


if __name__=='__main__':
    case=fixtures()[8];n=32;dt=.1
    before=build(case['material'],case['offset'],n)
    masses=[MASS.get(m,0.) for m in case['material']]
    contacts=[(y*n+16,(y+1)*n+16,0.,1.,0.) for y in range(3,22)]
    joint=coupled_contacts(before,case['velocity'],masses,contacts,dt)
    offset=[[a+dt*b for a,b in zip(o,v)] for o,v in zip(case['offset'],joint['velocity'])]
    after=build(case['material'],offset,n)
    gas=[node['area']*(.8 if node['center'][1]>16 else .2) for node in before['nodes']]
    remap=moving_box_gas(before,after,gas,dt,return_operator=True)
    overlay=remap['endpoint_operator'];solution=remap['endpoint_solution']
    assert before['components']==overlay['components']==1
    old_bounds={(node['x0'],node['x1'],node['lo'][0],node['hi'][0]):i
                for i,node in enumerate(before['nodes'])}
    new_anchor=next(i for i,node in enumerate(overlay['nodes']) if tuple(node['bounds']) in old_bounds)
    old_anchor=old_bounds[tuple(overlay['nodes'][new_anchor]['bounds'])]
    low=solution['pressure_low'];joint_low=joint['pressure_low'] or [0.]*len(joint['pressure'])
    shift=math.fsum((joint['pressure'][old_anchor],joint_low[old_anchor],
                    -solution['pressure'][new_anchor],-low[new_anchor]))
    shifted=[add_compensated(p,l,shift) for p,l in zip(solution['pressure'],low)]
    p=[a for a,_ in shifted];tail=[b for _,b in shifted]
    force=boundary_reaction(overlay,overlay['boundary_weights'],p,tail)
    def residual(f):
        return max(abs(remap['geometric_velocity'][i][k]-case['velocity'][i][k]
                       -(dt*f[i][k]+joint['contact_impulse'][i][k])/masses[i])
                   for i,_,_,_ in before['grains'] for k in (0,1))
    grid,_=network(overlay)
    flux_error=max(abs(a-b) for a,b in zip(grid.liquid_flux(p,tail),solution['flux']))
    # A constant datum has only one degree of freedom. Orthogonal projection
    # gives a diagnostic lower bound, never a force used by the simulation.
    unit_force=boundary_reaction(overlay,overlay['boundary_weights'],[1.]*len(p))
    defect=[];direction=[]
    for i,_,_,_ in before['grains']:
        for k in (0,1):
            defect.append(remap['geometric_velocity'][i][k]-case['velocity'][i][k]
                          -(dt*remap['pressure_reaction'][i][k]+joint['contact_impulse'][i][k])/masses[i])
            direction.append(dt*unit_force[i][k]/masses[i])
    norm=math.fsum(x*x for x in direction)
    coefficient=math.fsum(a*b for a,b in zip(defect,direction))/norm if norm else 0.
    irreducible_l2=math.sqrt(math.fsum((a-coefficient*b)**2 for a,b in zip(defect,direction)))
    lower_bound=irreducible_l2/math.sqrt(len(defect))
    report=dict(raw_residual=residual(remap['pressure_reaction']),aligned_residual=residual(force),
                common_region=overlay['nodes'][new_anchor]['bounds'],shift=shift,flux_error=flux_error,
                shifted_work=math.fsum(f*v for ff,vv in zip(force,remap['geometric_velocity']) for f,v in zip(ff,vv)),
                dissipation=solution['dissipation'],physical_acceptance=False,
                any_constant_shift_linf_lower_bound=lower_bound,
                datum_alone_cannot_pass=lower_bound>1e-8,
                scope='Single prescribed endpoint; diagnostic only, no state commit')
    # Compare the simultaneous solve on exactly the remap operator, without
    # replacing its pressure by a separately gauged kinematic solution.
    endpoint_joint=coupled_contacts(overlay,case['velocity'],masses,contacts,dt)
    actual_source=[(node['area']-node['end_area'])/dt for node in overlay['nodes']]
    divergence=grid.divergence(endpoint_joint['flux'])
    report['same_geometry_joint']=dict(
        velocity_mismatch=max(abs(endpoint_joint['velocity'][i][k]-remap['geometric_velocity'][i][k])
                              for i,_,_,_ in before['grains'] for k in (0,1)),
        capacity_residual=max(abs(a-b) for a,b in zip(divergence,actual_source)),
        contact_residual=endpoint_joint['contact_residual'],
        pressure_residual=endpoint_joint['residual'])
    (Path(__file__).resolve().parents[1]/'reports/endpoint-gauge-audit.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
