"""Bounded replay of the existing dense-chain endpoint feedback failure."""
import json
import argparse
import math
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import patch
from grain_volume_reference import fixtures
from grain_cut_cells import build, moving_contact_candidate, moving_box_gas
from grain_contact_impulse_reference import MASS


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--small-chain',action='store_true')
    parser.add_argument('--steps',type=int,choices=range(1,9),default=1)
    parser.add_argument('--without-coherent-prediction',action='store_true',
                        help='Diagnostic ablation only; retain the unprojected joint velocity')
    args=parser.parse_args();n=8 if args.small_chain else 32
    data=fixtures()[8]
    contacts=[(y*32+16,(y+1)*32+16,0.,1.,0.) for y in range(3,22)]
    if args.small_chain:
        material=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        offset=[[0.,0.] for _ in material];velocity=[[0.,0.] for _ in material]
        for i in (19,27,35):material[i]=2;offset[i]=[.13,-.27];velocity[i]=[0.,.02]
        data=dict(material=material,offset=offset,velocity=velocity)
        contacts=[(19,27,0.,1.,0.),(27,35,0.,1.,0.)]
    graph=build(data['material'],data['offset'],n)
    mass=[MASS.get(m,0.) for m in data['material']]
    if args.small_chain:mass=[3. if m>=2 else 0. for m in data['material']]
    gas=[node['area']*(.8 if node['center'][1]>16 else .2) for node in graph['nodes']]
    trace=[];step_records=[];step_index=0;initial_inventory=math.fsum(gas)
    def observe(before,after,*args,**kwargs):
        result=moving_box_gas(before,after,*args,**kwargs)
        positions={i:(x,y) for i,x,y,_ in after['grains']}
        entry=dict(step=step_index,nodes=len(after['nodes']),minimum_area=min(node['area'] for node in after['nodes']),
                   contact_gaps=[sum((positions[b][k]-positions[a][k])*normal
                                     for k,normal in enumerate((nx,ny)))-1.
                                 for a,b,nx,ny,_ in contacts])
        if 'joint_candidate' in result:
            joint=result['joint_candidate']
            entry.update(velocities=[joint['velocity'][i] for i,_,_,_ in after['grains']],
                         contact_lambdas=joint['contact_lambdas'],
                         contact_residual=joint['contact_residual'])
        trace.append(entry)
        return result
    try:
        ablation=(patch('grain_cut_cells.contact_prediction',lambda joint,*args,**kwargs:joint['velocity'])
                  if args.without_coherent_prediction else nullcontext())
        with patch('grain_cut_cells.moving_box_gas',observe),ablation:
            free=data['velocity']
            for step_index in range(args.steps):
                result=moving_contact_candidate(graph,free,mass,contacts,gas)
                if not result['accepted']:break
                remap=result['remap']
                step_records.append(dict(step=step_index,momentum_residual=result['residual'],
                    capacity_residual=remap.get('capacity_residual',0.),
                    contact_residual=remap['geometric_contact_residual'],work_error=remap['work_error'],
                    inventory_drift=math.fsum(result['gas'])-initial_inventory))
                graph,gas=result['graph'],result['gas']
                free=[list(v) for v in result['velocity']]
                for i,_,_,_ in graph['grains']:free[i][1]+=.002
        report={k:result[k] for k in ('accepted','residual','history','capacity_history','iterations')}
        report['residual_kind']=result.get('residual_kind','momentum')
    except (RuntimeError,ValueError) as error:
        report={'accepted':False,'reason':str(error),'solver_failure':True}
        if hasattr(error,'contact_diagnostic'):
            (Path(__file__).resolve().parents[1]/'reports/endpoint-contact-failure.json').write_text(json.dumps(error.contact_diagnostic))
            report['contact_polish']=error.contact_diagnostic['polish_trace']
        if hasattr(error,'endpoint_system'):
            failure=dict(system=error.endpoint_system,diagnostic=getattr(error,'pressure_diagnostic',None))
            (Path(__file__).resolve().parents[1]/'reports/endpoint-failed-system.json').write_text(json.dumps(failure))
    report['physical_acceptance']=False
    report['coherent_prediction']=not args.without_coherent_prediction
    report['geometry_trace']=trace
    report['accepted_steps']=len(step_records);report['requested_steps']=args.steps
    report['step_records']=step_records
    name='endpoint-small-chain.json' if args.small_chain else 'endpoint-feedback-shared-operator.json'
    if args.without_coherent_prediction:name=name.replace('.json','-unprojected.json')
    if args.steps!=1:name=name.replace('.json',f'-steps-{args.steps}.json')
    path=Path(__file__).resolve().parents[1]/'reports'/name
    path.write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
    raise SystemExit(0 if report['accepted'] else 1)
