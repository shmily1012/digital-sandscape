"""Isolate flux-source and face-mobility changes at a grid-aligned sand bed.

This is a diagnostic, not a solver or a physical acceptance test. Mixed
geometry is intentionally inconsistent and must never be used for a step.
"""
import copy
import json
from pathlib import Path
from grain_volume_reference import fixtures, geometry, apertures, project
from drainage_reaction_reference import reaction, dissipation, feedback
from grain_cut_cells import build, pressure, boundary_source, coupled_pressure, coupled_contacts, moving_box_gas
from local_gas_reference import transport_regions


def sealed_plug_inertia():
    n=12;material=[1]*(n*n);offset=[[0.,0.] for _ in material];velocity=copy.deepcopy(offset)
    for x in range(1,n-1):material[6*n+x]=0
    grain=6*n+6;material[grain]=2;velocity[grain]=[.02,0.]
    graph=build(material,offset,n)
    mass=[3. if m>=2 else 0. for m in material]
    source,_=boundary_source(graph,velocity)
    rejected=False
    try:pressure(graph,source)
    except ValueError:rejected=True
    result=coupled_pressure(graph,velocity,mass)
    return dict(prescribed_rejected=rejected,velocity=result['velocity'][grain],
                force=result['force'][grain],continuity=result['continuity'],
                max_liquid_flux=max(abs(q) for q in result['flux']),
                iterations=result['iterations'],scope='frozen geometry pressure/inertia; no position commit')


def split_connectivity(shape):
    n=12
    material=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
    offset=[[0.,0.] for _ in material]
    for y in range(1,n-1):material[y*n+6]=2
    graph=build(material,offset,n,shape)
    left={label for node,label in zip(graph['nodes'],graph['labels']) if node['cell']%n<5}
    right={label for node,label in zip(graph['nodes'],graph['labels']) if node['cell']%n>7}
    left_nodes=[i for i,node in enumerate(graph['nodes']) if node['cell']%n<5]
    right_nodes=[i for i,node in enumerate(graph['nodes']) if node['cell']%n>7]
    source=[0.]*len(graph['nodes']);source[left_nodes[0]]=1.;source[right_nodes[-1]]=-1.
    rejected=False
    try:pressure(graph,source)
    except ValueError:rejected=True
    source[right_nodes[-1]]=0.;source[left_nodes[-1]]=-1.
    result=pressure(graph,source)
    return dict(shape=shape,components=graph['components'],nodes=len(graph['nodes']),
                edges=len(graph['edges']),connected_across_barrier=bool(left & right),
                incompatible_source_rejected=rejected,
                compatible_source=dict(residual=result['residual'],iterations=result['iterations'],
                                       work_error=abs(result['source_work']-result['dissipation']),
                                       undriven_side_pressure=max(abs(result['pressure'][i]) for i in right_nodes)),
                scope='stationary region pressure network; no moving grains or gas')


def sealed_barrier(shape):
    """A touching grain chain joins both walls and separates the 2D liquid.

    Inject an incompatible left/right source to detect false graph paths.
    A pressure solution means this graph leaks, not that the case passes.
    """
    n=12
    material=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
    offset=[[0.,0.] for _ in material];velocity=copy.deepcopy(offset)
    for y in range(1,n-1):material[y*n+6]=2
    case=dict(side=n,material=material,offset=offset,velocity=velocity,shape=shape,
              expected=geometry(material,offset,velocity,n,1.,shape),
              aperture=apertures(material,offset,velocity,n,1.,shape))
    for x in range(2,9):case['expected'][6*n+x][2]=1.
    try:
        flux,_=project(case)
        return dict(shape=shape,leaks=True,cross_barrier_flux=flux[6*n+5][0])
    except RuntimeError as error:
        return dict(shape=shape,leaks=False,rejection=str(error))


def audit():
    base=fixtures()[8]
    chain_graph=build(base['material'],base['offset'],base['side'])
    masses={2:3.,3:2.7,4:2.4}
    chain=coupled_pressure(chain_graph,base['velocity'],[masses.get(m,0.) for m in base['material']])
    closing=max(chain['velocity'][y*32+16][1]-chain['velocity'][(y+1)*32+16][1] for y in range(3,22))
    contacts=[(y*32+16,(y+1)*32+16,0.,1.,0.) for y in range(3,22)]
    joint=coupled_contacts(chain_graph,base['velocity'],[masses.get(m,0.) for m in base['material']],contacts)
    capacity=[node['area'] for node in chain_graph['nodes']];predicted=capacity.copy()
    for (i,j,_),q in zip(chain_graph['edges'],joint['flux']):predicted[i]-=.1*q;predicted[j]+=.1*q
    gas=[v*(.8 if node['center'][1]>16 else .2) for node,v in zip(chain_graph['nodes'],capacity)]
    gas_result=transport_regions(chain_graph,gas,predicted,joint['flux'])
    moved=[[p+.1*v for p,v in zip(pos,vel)] if m>=2 else list(pos)
           for pos,vel,m in zip(base['offset'],joint['velocity'],base['material'])]
    endpoint_graph=build(base['material'],moved,32)
    try:
        remap=moving_box_gas(chain_graph,endpoint_graph,gas)
        remap_report={key:value for key,value in remap.items() if key!='gas'}
        remap_report['kinematic_solved']=True
    except (ValueError,RuntimeError) as error:
        remap_report=dict(kinematic_solved=False,error=str(error))
    by_cell=[0.]*len(base['material'])
    for node,v in zip(chain_graph['nodes'],predicted):by_cell[node['cell']]+=v
    endpoint=geometry(base['material'],base['offset'],joint['velocity'],32,.1)
    endpoint_error=max(abs(v-row[1]) for v,row in zip(by_cell,endpoint))
    refinement=[]
    for step in (.1,.05,.025):
        proposed=capacity.copy()
        for (i,j,_),q in zip(chain_graph['edges'],joint['flux']):proposed[i]-=step*q;proposed[j]+=step*q
        totals=[0.]*len(base['material'])
        for node,v in zip(chain_graph['nodes'],proposed):totals[node['cell']]+=v
        exact=geometry(base['material'],base['offset'],joint['velocity'],32,step)
        refinement.append(dict(dt=step,error=max(abs(v-row[1]) for v,row in zip(totals,exact))))
    round_case=dict(base,shape='disk')
    round_feedback=feedback(round_case,accelerate=True)
    candidates=[]
    for speed in (0.,1e-7):
        case=copy.deepcopy(base)
        for i,m in enumerate(case['material']):
            if m>=2:case['velocity'][i][0]=speed
        args=(case['material'],case['offset'],case['velocity'],case['side'],.1)
        case['expected']=geometry(*args)
        case['aperture']=apertures(*args)
        candidates.append(case)
    rows=[]
    for source in (0,1):
        for opening in (0,1):
            case=copy.deepcopy(candidates[source])
            case['aperture']=candidates[opening]['aperture']
            row=dict(source=source,opening=opening,diagnostic_only=True)
            try:
                case['fluid_flux'],case['pressure']=project(case)
                force=reaction(case,dt=.1)
                row.update(solved=True,top_force=force[112],dissipation=dissipation(case))
            except RuntimeError as error:
                row.update(solved=False,error=str(error))
            rows.append(row)
    changes=[]
    for i,(before,after) in enumerate(zip(candidates[0]['aperture'],candidates[1]['aperture'])):
        for axis,(a,b) in enumerate(zip(before,after)):
            if abs(a-b)>.1:
                changes.append(dict(cell=[i%32,i//32],axis=axis,before=a,after=b))
    return dict(dt=.1,velocity_perturbation=1e-7,
                capacity_change=max(abs(a[1]-b[1]) for a,b in zip(candidates[0]['expected'],candidates[1]['expected'])),
                face_jumps=changes,crossed_operators=rows,
                sealed_barriers=[sealed_barrier(shape) for shape in ('box','disk')],
                split_connectivity=[split_connectivity(shape) for shape in ('box','disk')],
                sealed_plug_inertia=sealed_plug_inertia(),
                chain_pressure_inertia=dict(nodes=len(chain_graph['nodes']),iterations=chain['iterations'],
                                            residual=chain['residual'],contact_closing_speed=closing,
                                            physical_step_accepted=False),
                chain_fixed_contact_reference={key:joint[key] for key in
                                               ('contact_residual','continuity','response_solves','contact_sweeps',
                                                'uniform_pressure_contact_null','polish_merits')},
                chain_region_gas=dict(gas_residual=gas_result['gas_residual'],
                                      volume_residual=gas_result['volume_residual'],
                                      inventory_drift=gas_result['component_inventory_drift'],
                                      endpoint_geometry_error=endpoint_error,
                                      frozen_velocity_refinement=refinement,
                                      physical_step_accepted=False),
                chain_endpoint_remap=remap_report,
                round_feedback={key:round_feedback.get(key) for key in
                                ('accepted','residual','contact_residual','iterations')},
                physical_acceptance=False)


if __name__=='__main__':
    target=Path(__file__).resolve().parents[1]/'reports/drainage-alignment-isolation.json'
    target.write_text(json.dumps(audit(),indent=2))
    print(target)
