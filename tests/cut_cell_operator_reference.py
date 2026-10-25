"""Export frozen split-region operators; CPU geometry upload is test-only."""
import json
import math
import struct
from pathlib import Path
from grain_cut_cells import build,boundary_map,network,moving_box_gas


def f32(x):return struct.unpack('<f',struct.pack('<f',x))[0]


def evaluate(data,p):
    force=[[0.,0.] for _ in range(data['grains'])]
    for node,g,nx,ny in data['weights']:
        force[g][0]-=nx*p[node];force[g][1]-=ny*p[node]
    out=[sum(w*(p[i]-p[j]) for j,w in data['edges'][data['edge_rows'][i]:data['edge_rows'][i+1]]) for i in range(data['nodes'])]
    for node,g,nx,ny in data['weights']:
        out[node]-=data['dt']*(nx*force[g][0]+ny*force[g][1])/data['mass'][g]
    return force,out


def solve(data):
    from experiments.liquid.model import DarcyGrid
    edges=[(i,j,w) for i in range(data['nodes'])
           for j,w in data['edges'][data['edge_rows'][i]:data['edge_rows'][i+1]] if i<j]
    grid=DarcyGrid.from_graph(data['nodes'],edges)
    p,iterations,residual=grid.pressure_for_source(data['expected'][1::2],tolerance=1e-10,
        max_iterations=2048,apply=lambda x:evaluate(data,x)[1])
    force,_=evaluate(data,p)
    return dict(pressure=p,force=[x for v in force for x in v],iterations=iterations,residual=residual)


def pack(graph,name,dt=.1,component_pressure=False):
    grains={g[0]:i for i,g in enumerate(graph['grains'])};count=len(graph['nodes'])
    _,connections=network(graph)
    adjacency=[[] for _ in range(count)]
    for i,j,w in connections:adjacency[i].append([j,f32(w)]);adjacency[j].append([i,f32(w)])
    edges=[];edge_rows=[0]
    for row in adjacency:edges.extend(row);edge_rows.append(len(edges))
    weights=[[node,grains[g],f32(nx),f32(ny)] for node,g,nx,ny in boundary_map(graph)]
    def csr(column,size):
        rows=[0];ids=[]
        for i in range(size):ids.extend(k for k,w in enumerate(weights) if w[column]==i);rows.append(len(ids))
        return rows,ids
    node_rows,node_ids=csr(0,count);grain_rows,grain_ids=csr(1,len(grains))
    pressure=[f32(1+graph['labels'][i] if component_pressure else .03*math.sin(i*.37)) for i in range(count)]
    masses=[f32(3.-.3*(i%3)) for i in range(len(grains))]
    velocity=[[f32(.01*math.cos(i)),f32(.02*math.sin(i+.5))] for i in range(len(grains))]
    force=[[0.,0.] for _ in grains]
    for node,g,nx,ny in weights:
        force[g][0]-=nx*pressure[node];force[g][1]-=ny*pressure[node]
    output=[[sum(w*(pressure[i]-pressure[j]) for j,w in adjacency[i]),0.] for i in range(count)]
    for node,g,nx,ny in weights:
        output[node][0]-=f32(dt)*(nx*force[g][0]+ny*force[g][1])/masses[g]
        output[node][1]+=nx*velocity[g][0]+ny*velocity[g][1]
    cell_labels={}
    for i,node in enumerate(graph['nodes']):cell_labels.setdefault(node.get('cell',i),set()).add(graph['labels'][i])
    return dict(name=name,nodes=count,grains=len(grains),edges=edges,edge_rows=edge_rows,
                weights=weights,node_rows=node_rows,node_ids=node_ids,grain_rows=grain_rows,grain_ids=grain_ids,
                mass=masses,velocity=[x for v in velocity for x in v],pressure=pressure,dt=f32(dt),
                expected_force=[x for v in force for x in v],expected=[x for v in output for x in v],
                components=graph['components'],shared_cell_components=max(map(len,cell_labels.values())),
                source_component_sum=[math.fsum(output[i][1] for i in range(count) if graph['labels'][i]==label)
                                      for label in range(graph['components'])])


def fixtures():
    n=8;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
    offsets=[[0.,0.] for _ in m];m[27]=2;offsets[27]=[.13,-.27]
    before=build(m,offsets,n)
    result=[pack(before,'offset-grain')]
    result.append(pack(before,'compatible-pure-pressure',dt=0.))
    end=[list(v) for v in offsets];end[27]=[.131,-.268]
    remap=moving_box_gas(before,build(m,end,n),[node['area']*.6 for node in before['nodes']],return_operator=True)
    result.append(pack(remap['endpoint_operator'],'finite-endpoint-overlay'))
    offsets=[[0.,0.] for _ in m]
    m[27]=0
    for x in range(1,n-1):m[3*n+x]=2
    graph=build(m,offsets,n)
    assert graph['components']==2
    result.append(pack(graph,'sealed-component-pressure',dt=0.,component_pressure=True))
    result.append(pack(graph,'inertial-sealed-components',dt=.1,component_pressure=True))
    graph=build(m,offsets,n,shape='disk')
    assert graph['components']==2
    split=pack(graph,'sealed-disk-split-cell',dt=0.,component_pressure=True)
    assert split['shared_cell_components']==2
    result.append(split)
    for data in result:
        if data['dt']>0 or max(map(abs,data['source_component_sum']))<1e-10:data['solve']=solve(data)
    return result


if __name__=='__main__':
    (Path(__file__).resolve().parents[1]/'reports/cut-cell-operator-fixture.json').write_text(json.dumps(fixtures()))
