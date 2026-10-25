"""Reference liquid connectivity inside cut cells; not a timestep solver.

Vertical strips split at geometric events. Separate free bands never share a
node merely because they belong to one raster cell. Ports connect only over
positive-length liquid intervals. Unit grains may be boxes or radius-.5 disks;
walls are boxes. Nonoverlapping solids are a caller precondition.
"""
import math


def value(bound,x):
    if len(bound)==1:return bound[0]
    cx,cy,sign=bound
    return cy+sign*math.sqrt(max(0.,.25-(x-cx)**2))


def integral(bound,a,b):
    if len(bound)==1:return bound[0]*(b-a)
    cx,cy,sign=bound
    def primitive(x):
        t=max(-.5,min(.5,x-cx))
        return .5*(t*math.sqrt(max(0.,.25-t*t))+.25*math.asin(2*t))
    return cy*(b-a)+sign*(primitive(b)-primitive(a))


def box_faces(index,offset,n):
    """Build a shared face from its grid plane before adding local offset.

    Adjacent equal-offset grains then evaluate their common face identically;
    (grid + offset) +/- half would round the same plane along different paths.
    """
    x,y=index%n,index//n;ox,oy=offset
    return ((x-.5)+ox,(x+.5)+ox,(y-.5)+oy,(y+.5)+oy)


def grain_faces(graph,grain,cx,cy):
    if 'offsets' in graph:
        return box_faces(grain,graph['offsets'][grain],math.isqrt(graph['material_count']))
    return cx-.5,cx+.5,cy-.5,cy+.5


def build(material,offset,n,shape='box'):
    if shape not in ('box','disk'):raise ValueError('Unknown shape')
    if len(material)!=n*n or len(offset)!=n*n:raise ValueError('Invalid grid')
    bodies=[(i%n+(offset[i][0] if m>=2 else 0.),
             i//n+(offset[i][1] if m>=2 else 0.),shape=='disk' and m>=2)
            for i,m in enumerate(material) if m]
    faces={body:box_faces(i,offset[i] if material[i]>=2 else (0.,0.),n)
           for body,i in zip(bodies,(i for i,m in enumerate(material) if m))}
    nodes=[];edges=[];ports={}
    def link(left,right):
        for i,a,b in left:
            for j,c,d in right:
                opening=min(b,d)-max(a,c)
                if opening>1e-12:edges.append((i,j,opening))
    for cell in range(n*n):
        x,y=cell%n,cell//n;l,r=x-.5,x+.5;bottom,top=y-.5,y+.5
        local=[body for body in bodies if abs(body[0]-x)<1 and abs(body[1]-y)<1]
        cuts={l,r}
        for cx,cy,disk in local:
            xmin,xmax,_,_=faces[(cx,cy,disk)]
            cuts.update(t for t in ((cx-.5,cx,cx+.5) if disk else (xmin,cx,xmax)) if l<t<r)
            if disk:
                for boundary in (bottom,top):
                    if abs(boundary-cy)<.5:
                        root=math.sqrt(.25-(boundary-cy)**2)
                        cuts.update(t for t in (cx-root,cx+root) if l<t<r)
        # Equal-radius disk tangencies can split a band even inside a cell.
        for k,(cx,cy,disk) in enumerate(local):
            if not disk:continue
            for dx,dy,other_disk in local[:k]:
                if other_disk and abs(math.hypot(cx-dx,cy-dy)-1.)<1e-12:
                    point=(cx+dx)*.5
                    if l<point<r:cuts.add(point)
        previous=[];cell_ports=[[],[],[],[]]
        cuts=sorted(cuts)
        for a,b in zip(cuts,cuts[1:]):
            mid=(a+b)*.5;blocked=[]
            for cx,cy,disk in local:
                xmin,xmax,ymin,ymax=faces[(cx,cy,disk)]
                if (abs(mid-cx)>=.5 if disk else not xmin<mid<xmax):continue
                lo=(cx,cy,-1) if disk else (ymin,)
                hi=(cx,cy,1) if disk else (ymax,)
                if value(hi,mid)<=bottom or value(lo,mid)>=top:continue
                if value(lo,mid)<bottom:lo=(bottom,)
                if value(hi,mid)>top:hi=(top,)
                blocked.append((lo,hi))
            blocked.sort(key=lambda pair:value(pair[0],mid))
            bands=[];cursor=(bottom,)
            for lo,hi in blocked:
                if value(lo,mid)>value(cursor,mid):bands.append((cursor,lo))
                if value(hi,mid)>value(cursor,mid):cursor=hi
            if value(cursor,mid)<top:bands.append((cursor,(top,)))
            left=[];right=[]
            for lo,hi in bands:
                area=integral(hi,a,b)-integral(lo,a,b)
                if area<=0:continue
                index=len(nodes)
                nodes.append(dict(cell=cell,x0=a,x1=b,lo=lo,hi=hi,area=area,
                                  center=(mid,.5*(value(lo,mid)+value(hi,mid)))))
                left.append((index,value(lo,a),value(hi,a)))
                right.append((index,value(lo,b),value(hi,b)))
                if lo==(bottom,):cell_ports[2].append((index,a,b))
                if hi==(top,):cell_ports[3].append((index,a,b))
            link(previous,left);previous=right
            if a==l:cell_ports[0]=left
            if b==r:cell_ports[1]=right
        if x:link(ports[cell-1][1],cell_ports[0])
        if y:link(ports[cell-n][3],cell_ports[2])
        ports[cell]=cell_ports
    adjacency=[[] for _ in nodes]
    for i,j,_ in edges:adjacency[i].append(j);adjacency[j].append(i)
    labels=[-1]*len(nodes);count=0
    for i in range(len(nodes)):
        if labels[i]>=0:continue
        labels[i]=count;pending=[i]
        while pending:
            for j in adjacency[pending.pop()]:
                if labels[j]<0:labels[j]=count;pending.append(j)
        count+=1
    grains=[(i,i%n+offset[i][0],i//n+offset[i][1],shape=='disk')
            for i,m in enumerate(material) if m>=2]
    return dict(nodes=nodes,edges=edges,labels=labels,components=count,
                grains=grains,material_count=len(material),materials=list(material),
                offsets=[list(v) for v in offset])


def overlap_ledger(before,after,gas,tolerance=1e-12):
    """Exact local rectangle overlap ledger for box-region remapping.

    Common fluid retains its gas concentration. Covered fluid and its gas are
    held separately; newly exposed capacity is not filled by guessing a donor.
    Complete is true only for a pure repartition with no physical displacement.
    A caller must resolve held/opened volume through physical flow before any
    moving-state commit. Curved bands deliberately remain unsupported here.
    """
    if not math.isfinite(tolerance) or tolerance<=0:raise ValueError('Invalid remap tolerance')
    if before['materials']!=after['materials']:raise ValueError('Material identity changed')
    if len(gas)!=len(before['nodes']) or any(not math.isfinite(g) or not 0<=g<=node['area'] for g,node in zip(gas,before['nodes'])):
        raise ValueError('Invalid old gas inventory')
    if len(before['grains'])!=len(after['grains']):raise ValueError('Grain inventory changed')
    for a,b in zip(before['grains'],after['grains']):
        if a[0]!=b[0] or a[3]!=b[3]:raise ValueError('Grain identity or shape changed')
        if max(abs(a[1]-b[1]),abs(a[2]-b[2]))>.25:raise ValueError('Remap displacement exceeds bound')
    for graph in (before,after):
        if any(len(node['lo'])!=1 or len(node['hi'])!=1 for node in graph['nodes']):
            raise ValueError('Curved region overlap is not implemented')
    new_by_cell={}
    for j,node in enumerate(after['nodes']):new_by_cell.setdefault(node['cell'],[]).append(j)
    overlaps=[];old_parts=[[] for _ in before['nodes']];new_parts=[[] for _ in after['nodes']]
    gas_parts=[[] for _ in after['nodes']]
    for i,old in enumerate(before['nodes']):
        for j in new_by_cell.get(old['cell'],[]):
            new=after['nodes'][j]
            width=min(old['x1'],new['x1'])-max(old['x0'],new['x0'])
            height=min(old['hi'][0],new['hi'][0])-max(old['lo'][0],new['lo'][0])
            if width<=0 or height<=0:continue
            area=width*height
            overlaps.append((i,j,area));old_parts[i].append(area);new_parts[j].append(area)
            gas_parts[j].append(gas[i]*area/old['area'])
    def remainder(nodes,parts):
        result=[]
        for node,pieces in zip(nodes,parts):
            remaining=node['area']-math.fsum(pieces)
            if remaining < -tolerance:raise ValueError('Overlapping region partition')
            # Only a negative double-roundoff tail is zeroed; positive lost or
            # newly exposed area is always retained in the unresolved ledger.
            result.append(max(0.,remaining))
        return result
    covered=remainder(before['nodes'],old_parts);opened=remainder(after['nodes'],new_parts)
    mapped=[math.fsum(parts) for parts in gas_parts]
    held=[g*v/node['area'] for g,v,node in zip(gas,covered,before['nodes'])]
    volume_balance=math.fsum(covered)-math.fsum(opened)
    gas_balance=math.fsum(mapped)+math.fsum(held)-math.fsum(gas)
    budget=tolerance*max(1,len(before['nodes'])+len(after['nodes']))
    if abs(volume_balance)>budget or abs(gas_balance)>budget:raise ValueError('Remap ledger does not conserve inventory')
    return dict(overlaps=overlaps,mapped_gas=mapped,held_gas=held,
                covered_volume=covered,opened_volume=opened,volume_balance=volume_balance,
                gas_balance=gas_balance,complete=max(math.fsum(covered),math.fsum(opened))<=tolerance)


def boundary_map(graph):
    """Integrated outward solid normals on every fluid-region boundary.

    S maps grain translation to outward liquid volume rate. -S^T maps
    pressure to grain force. Artificial strip boundaries add no solid load.
    Geometry is frozen; this is not a finite-step remap of changing regions.
    """
    if 'boundary_weights' in graph:return graph['boundary_weights']
    weights=[]
    for region,node in enumerate(graph['nodes']):
        a,b=node['x0'],node['x1'];mid=(a+b)*.5
        for grain,cx,cy,disk in graph['grains']:
            nx=ny=0.
            xmin,xmax,ymin,ymax=grain_faces(graph,grain,cx,cy)
            for bound,orientation in ((node['lo'],1),(node['hi'],-1)):
                physical=(bound==(cx,cy,orientation) if disk else
                          bound==((ymax if orientation==1 else ymin),) and xmin<mid<xmax)
                if physical:
                    nx-=orientation*(value(bound,b)-value(bound,a))
                    ny+=orientation*(b-a)
            if not disk:
                for x,orientation in ((a,1),(b,-1)):
                    if x==(xmax if orientation==1 else xmin):
                        length=max(0.,min(value(node['hi'],x),ymax)-max(value(node['lo'],x),ymin))
                        nx+=orientation*length
            if nx or ny:weights.append((region,grain,nx,ny))
    return weights


def moving_box_gas(before,after,gas,dt=.1,return_operator=False,joint_inputs=None):
    """Conservative kinematic box remap on a local endpoint overlay.

    Endpoint-fluid adjacency is time-averaged (not a resolved space-time flow).
    Closed-at-both-ends faces never connect. Prescribed motion solves pressure
    for exact capacity change. With joint_inputs, one simultaneous pressure/
    contact solve supplies both reaction and transport flux; mismatched
    geometry returns only an iterate, before any gas transport or publication.
    """
    from local_gas_reference import transport_regions
    if not math.isfinite(dt) or not 0<dt<=1:raise ValueError('Invalid remap timestep')
    ledger=overlap_ledger(before,after,gas)
    if ledger['complete']:
        return dict(gas=ledger['mapped_gas'],gas_drift=ledger['gas_balance'],
                    pressure_residual=0.,gas_residual=0.,nodes=0,kinematic_only=True,
                    pressure_reaction=[[0.,0.] for _ in range(before['material_count'])],
                    geometric_velocity=[[0.,0.] for _ in range(before['material_count'])],
                    boundary_source_error=0.,pressure_work=0.,work_error=0.,endpoint_area_error=0.)
    old_cells={};new_cells={}
    for i,node in enumerate(before['nodes']):old_cells.setdefault(node['cell'],[]).append(i)
    for i,node in enumerate(after['nodes']):new_cells.setdefault(node['cell'],[]).append(i)
    n=math.isqrt(before['material_count']);nodes=[];ports={};edges=[]
    def owner(ids,graph,x,y):
        matches=[i for i in ids if graph['nodes'][i]['x0']<x<graph['nodes'][i]['x1']
                 and graph['nodes'][i]['lo'][0]<y<graph['nodes'][i]['hi'][0]]
        if len(matches)>1:raise ValueError('Overlapping fluid regions')
        return matches[0] if matches else None
    for cell in sorted(set(old_cells)|set(new_cells)):
        x,y=cell%n,cell//n
        old_ids=old_cells.get(cell,[]);new_ids=new_cells.get(cell,[])
        pieces=[before['nodes'][i] for i in old_ids]+[after['nodes'][i] for i in new_ids]
        xs=sorted({x-.5,x+.5}|{a for node in pieces for a in (node['x0'],node['x1'])})
        ys=sorted({y-.5,y+.5}|{a for node in pieces for a in (node['lo'][0],node['hi'][0])})
        if (len(xs)-1)*(len(ys)-1)>1024:raise ValueError('Local remap geometry budget exceeded')
        for a,b in zip(xs,xs[1:]):
            for c,d in zip(ys,ys[1:]):
                old=owner(old_ids,before,(a+b)*.5,(c+d)*.5)
                new=owner(new_ids,after,(a+b)*.5,(c+d)*.5)
                if old is None and new is None:continue
                area=(b-a)*(d-c);index=len(nodes)
                area_uncertainty=4*((math.ulp(a)+math.ulp(b))*(d-c)
                                    +(math.ulp(c)+math.ulp(d))*(b-a)+math.ulp(area))
                nodes.append(dict(area=area if old is not None else 0.,
                                  end_area=area if new is not None else 0.,
                                  bounds=(a,b,c,d),
                                  center=((a+b)*.5,(c+d)*.5),old=old,new=new,
                                  source_uncertainty=area_uncertainty*(int(old is not None)+int(new is not None))/dt,
                                  gas=gas[old]*area/before['nodes'][old]['area'] if old is not None else 0.))
                for axis,coordinate,side,low,high in ((0,a,0,c,d),(0,b,1,c,d),(1,c,0,a,b),(1,d,1,a,b)):
                    ports.setdefault((axis,coordinate),[[],[]])[side].append((index,low,high))
    if len(nodes)>100000:raise ValueError('Remap node budget exceeded')
    adjacency=[[] for _ in nodes]
    for left,right in ports.values():
        for i,a,b in right:
            for j,c,d in left:
                opening=min(b,d)-max(a,c)
                if opening<=0:continue
                fraction=.5*(int(nodes[i]['old'] is not None and nodes[j]['old'] is not None)
                              +int(nodes[i]['new'] is not None and nodes[j]['new'] is not None))
                if not fraction:continue
                edges.append((i,j,opening*fraction));adjacency[i].append(j);adjacency[j].append(i)
    labels=[-1]*len(nodes);count=0
    for i in range(len(nodes)):
        if labels[i]>=0:continue
        labels[i]=count;pending=[i]
        while pending:
            for j in adjacency[pending.pop()]:
                if labels[j]<0:labels[j]=count;pending.append(j)
        count+=1
    overlay=dict(nodes=nodes,edges=edges,labels=labels,components=count,
                 material_count=before['material_count'])
    source=[(node['area']-node['end_area'])/dt for node in nodes]
    uncertainty=[node['source_uncertainty'] for node in nodes]
    weights,geometric_velocity=finite_box_map(overlay,before,after,dt)
    reconstructed=[[] for _ in nodes]
    for region,grain,nx,ny in weights:
        reconstructed[region].append(nx*geometric_velocity[grain][0]+ny*geometric_velocity[grain][1])
    source_error=max((abs(math.fsum(values)-s) for values,s in zip(reconstructed,source)),default=0.)
    if source_error>max(1e-12,math.fsum(uncertainty)):raise RuntimeError('Finite boundary source disagrees with capacity')
    joint=None
    if joint_inputs is None:
        solution=pressure(overlay,source,tolerance=1e-12,max_iterations=2048,precondition=True,source_uncertainty=uncertainty,compensated=True)
    else:
        overlay.update(grains=before['grains'],materials=before['materials'],boundary_weights=weights)
        joint=coupled_contacts(overlay,joint_inputs['velocity'],joint_inputs['mass'],
                               joint_inputs['contacts'],dt,tolerance=joint_inputs['tolerance'])
        grid,_=network(overlay)
        capacity_error=max(abs(a-b) for a,b in zip(grid.divergence(joint['flux']),source))
        velocity_error=max(abs(joint['velocity'][i][k]-geometric_velocity[i][k])
                           for i,_,_,_ in before['grains'] for k in (0,1))
        if capacity_error>1.1e-12 or velocity_error>joint_inputs['tolerance']:
            # Rejected geometry exposes only a new iterate, never gas/state.
            return dict(joint_candidate=joint,capacity_residual=capacity_error,
                        velocity_mismatch=velocity_error,accepted=False)
        solution=joint
    reaction=boundary_reaction(overlay,weights,solution['pressure'],solution['pressure_low'])
    work=math.fsum(f*v for force,vel in zip(reaction,geometric_velocity) for f,v in zip(force,vel))
    work_error=abs(work+solution['dissipation'])
    if work_error>1e-10:raise RuntimeError('Finite boundary pressure work disagrees')
    transported=transport_regions(overlay,[node['gas'] for node in nodes],
                                  [node['end_area'] for node in nodes],solution['flux'],dt,tolerance=1e-11)
    mapped=[[] for _ in after['nodes']];area_parts=[[] for _ in after['nodes']]
    for node,amount in zip(nodes,transported['gas']):
        if node['new'] is not None:
            mapped[node['new']].append(amount);area_parts[node['new']].append(node['end_area'])
        elif amount!=0:raise RuntimeError('Gas remains in covered solid')
    result=[math.fsum(values) for values in mapped]
    area_error=max((abs(math.fsum(parts)-node['area']) for parts,node in zip(area_parts,after['nodes'])),default=0.)
    drift=math.fsum(result)-math.fsum(gas)
    if area_error>1e-12 or abs(drift)>len(nodes)*1e-11:raise RuntimeError('Endpoint remap ledger failed')
    report=dict(gas=result,gas_drift=drift,pressure_residual=solution['residual'],
                pressure_iterations=solution['iterations'],compensated_pressure=True,
                gas_residual=transported['gas_residual'],endpoint_area_error=area_error,
                source_roundoff_bound=math.fsum(uncertainty),
                pressure_reaction=reaction,geometric_velocity=geometric_velocity,
                boundary_source_error=source_error,pressure_work=work,work_error=work_error,
                nodes=len(nodes),edges=len(edges),components=count,kinematic_only=True)
    if joint is not None:
        report.update(joint_candidate=joint,capacity_residual=capacity_error,
                      velocity_mismatch=velocity_error,accepted=True)
    if return_operator:
        overlay.update(grains=before['grains'],materials=before['materials'],boundary_weights=weights)
        report['endpoint_operator']=overlay
        report['endpoint_solution']=solution
    return report


def finite_box_map(overlay,before,after,dt):
    """Secant volume derivative for the same rectangle endpoint capacities.

    Average the x-then-y and y-then-x coordinate paths. The transpose maps
    overlay pressure to reaction; no reference-state force is added twice.
    """
    def width(left,right,lo,hi):return max(0.,min(hi,right)-max(lo,left))
    def cut(point,lo,hi):return 1. if lo<point<hi else (.5 if point in (lo,hi) else 0.)
    weights=[];velocity=[[0.,0.] for _ in range(before['material_count'])]
    for old,new in zip(before['grains'],after['grains']):
        grain,x0,y0,_=old;_,x1,y1,_=new;dx=x1-x0;dy=y1-y0
        if 'offsets' in before and 'offsets' in after:
            dx,dy=[b-a for a,b in zip(before['offsets'][grain],after['offsets'][grain])]
        l0,r0,b0,t0=grain_faces(before,grain,x0,y0)
        l1,r1,b1,t1=grain_faces(after,grain,x1,y1)
        velocity[grain]=[dx/dt,dy/dt]
        for region,node in enumerate(overlay['nodes']):
            a,b,c,d=node['bounds']
            wx0,wx1=width(l0,r0,a,b),width(l1,r1,a,b)
            wy0,wy1=width(b0,t0,c,d),width(b1,t1,c,d)
            nx=((wx1-wx0)/dx if dx else cut(r0,a,b)-cut(l0,a,b))*.5*(wy0+wy1)
            ny=((wy1-wy0)/dy if dy else cut(t0,c,d)-cut(b0,c,d))*.5*(wx0+wx1)
            if nx or ny:weights.append((region,grain,nx,ny))
    return weights,velocity


def contact_prediction(joint,mass,contacts,tolerance=1e-12,friction=.5):
    """Constraint-coherent prediction for closed, active axis-aligned contacts.

    Only geometry prediction is changed, not joint forces or accepted velocity.
    Mass-weighted averaging preserves each component's momentum. Sliding,
    separated, wall and oblique contacts remain outside this limited helper.
    Corrections larger than the supplied solver tolerance are never applied.
    Actual momentum, capacity and contact checks still govern acceptance.
    """
    velocity=joint['velocity'];prediction=[list(v) for v in velocity]
    for axis in (0,1):
        parent={}
        def root(i):
            parent.setdefault(i,i)
            while parent[i]!=i:i=parent[i]
            return i
        for contact,impulse in zip(contacts,joint['contact_lambdas']):
            a,b,nx,ny,gap=contact;normal,tangent=impulse
            if b<0 or gap!=0 or normal<=tolerance:continue
            if (abs(nx),abs(ny)) not in ((1.,0.),(0.,1.)):continue
            normal_axis=0 if nx else 1
            if axis!=normal_axis and abs(tangent)>=friction*normal-tolerance:continue
            ra,rb=root(a),root(b);parent[rb]=ra
        groups={}
        for i in parent:groups.setdefault(root(i),[]).append(i)
        for ids in groups.values():
            mean=math.fsum(mass[i]*velocity[i][axis] for i in ids)/math.fsum(mass[i] for i in ids)
            if max(abs(mean-velocity[i][axis]) for i in ids)<=tolerance:
                for i in ids:prediction[i][axis]=mean
    return prediction


def moving_contact_candidate(before,velocity,mass,contacts,gas,dt=.1,iterations=8,tolerance=1e-8):
    """Bounded endpoint-force feedback; inputs remain untouched on rejection.

    Rebuild the joint pressure/contact operator on the finite endpoint volume
    map. Use its pressure for both force and gas flux, retaining its contact
    datum. Require capacity closure and original momentum before acceptance.
    No application state is published by this reference function.
    """
    if not isinstance(iterations,int) or not 1<=iterations<=16:raise ValueError('Invalid coupled feedback budget')
    n=math.isqrt(before['material_count']);offset=[[0.,0.] for _ in velocity]
    history=[];capacity_history=[];residual_kind='momentum'
    for i,x,y,disk in before['grains']:
        if disk:raise ValueError('Moving coupled disk regions are not implemented')
        offset[i]=list(before['offsets'][i]) if 'offsets' in before else [x-i%n,y-i//n]
    joint=coupled_contacts(before,velocity,mass,contacts,dt,tolerance=tolerance)
    for iteration in range(iterations):
        prediction=contact_prediction(joint,mass,contacts,tolerance=tolerance)
        endpoint=[list(p) for p in offset]
        for i,_,_,_ in before['grains']:
            endpoint[i]=[p+dt*v for p,v in zip(offset[i],prediction[i])]
        after=build(before['materials'],endpoint,n)
        remap=moving_box_gas(before,after,gas,dt,joint_inputs=dict(
            velocity=velocity,mass=mass,contacts=contacts,tolerance=tolerance))
        if 'joint_candidate' in remap:
            joint=remap.pop('joint_candidate')
            capacity_history.append(remap['capacity_residual'])
            if not remap['accepted']:
                residual_kind='geometric_velocity'
                history.append(remap['velocity_mismatch'])
                continue
        if before['grains']==after['grains']:
            # Prescribed zero motion alone cannot determine the pressure
            # difference supporting a sealed plug. The unchanged geometry's
            # simultaneous solve already determines that load from inertia.
            remap['pressure_reaction']=joint['force']
            remap['geometric_velocity']=joint['velocity']
            remap['pressure_residual']=joint['residual']
            remap['fixed_geometry_pressure_retained']=True
        geometric_contact_error=0.
        for (a,b,nx,ny,gap),(normal,tangent) in zip(contacts,joint['contact_lambdas']):
            relative=[remap['geometric_velocity'][a][k]
                      -(remap['geometric_velocity'][b][k] if b>=0 else 0.) for k in (0,1)]
            closing=nx*relative[0]+ny*relative[1]-gap/dt
            slip=-ny*relative[0]+nx*relative[1];limit=.5*normal
            geometric_contact_error=max(geometric_contact_error,
                abs(normal-max(0.,normal+closing)),
                abs(tangent-max(-limit,min(limit,tangent+slip))))
        remap['geometric_contact_residual']=geometric_contact_error
        error=max((abs(remap['geometric_velocity'][i][k]-velocity[i][k]
                       -(dt*remap['pressure_reaction'][i][k]+joint['contact_impulse'][i][k])/mass[i])
                   for i,_,_,_ in before['grains'] for k in range(2)),default=0.)
        history.append(error)
        residual_kind='momentum'
        if error<=tolerance and geometric_contact_error<=tolerance:
            return dict(graph=after,gas=remap['gas'],velocity=remap['geometric_velocity'],
                        contact=joint,remap=remap,residual=error,history=history,
                        capacity_history=capacity_history,iterations=iteration+1,accepted=True,reference_only=True)
    return dict(accepted=False,residual=history[-1],history=history,iterations=iterations,
                capacity_history=capacity_history,residual_kind=residual_kind,
                reason='Endpoint geometry/force feedback budget exhausted',reference_only=True)


def boundary_source(graph,velocity):
    if len(velocity)!=graph['material_count'] or any(len(v)!=2 or any(not math.isfinite(x) for x in v) for v in velocity):
        raise ValueError('Invalid grain velocity')
    weights=boundary_map(graph);source=[0.]*len(graph['nodes'])
    for region,grain,nx,ny in weights:
        source[region]+=nx*velocity[grain][0]+ny*velocity[grain][1]
    return source,weights


def boundary_reaction(graph,weights,p,low=None):
    if len(p)!=len(graph['nodes']) or any(not math.isfinite(x) for x in p):
        raise ValueError('Invalid region pressure')
    if low is not None:
        if len(low)!=len(p) or any(not math.isfinite(x) for x in low):raise ValueError('Invalid low pressure')
        terms=[[[],[]] for _ in range(graph['material_count'])]
        for region,grain,nx,ny in weights:
            for axis,normal in enumerate((nx,ny)):
                terms[grain][axis].extend((-normal*p[region],-normal*low[region]))
        return [[math.fsum(axis) for axis in pair] for pair in terms]
    force=[[0.,0.] for _ in range(graph['material_count'])]
    for region,grain,nx,ny in weights:
        force[grain][0]-=nx*p[region];force[grain][1]-=ny*p[region]
    return force


def network(graph):
    """Shared two-point reference network for prescribed and inertial solves."""
    import sys
    from pathlib import Path
    root=str(Path(__file__).resolve().parents[1])
    if root not in sys.path:sys.path.insert(0,root)
    from experiments.liquid.model import DarcyGrid
    edges=[]
    for i,j,opening in graph['edges']:
        a,b=graph['nodes'][i]['center'],graph['nodes'][j]['center']
        distance=math.hypot(a[0]-b[0],a[1]-b[1])
        edges.append((i,j,opening/distance))
    return DarcyGrid.from_graph(len(graph['nodes']),edges),edges


def coupled_pressure(graph,velocity,mass,dt=.1,tolerance=1e-10,max_iterations=None):
    """Simultaneous Darcy pressure/grain inertia on frozen split geometry.

    (L + dt S M^-1 S^T)p = S v_free. No frictional contact, gas transport,
    or position commit. Unlike prescribed motion, pressure can stop a plug
    instead of rejecting its attempted compression of a sealed liquid region.
    """
    if not math.isfinite(dt) or not 0<dt<=1:raise ValueError('Invalid timestep')
    if len(mass)!=graph['material_count'] or any(not math.isfinite(mass[i]) or mass[i]<=0 for i,_,_,_ in graph['grains']):
        raise ValueError('Invalid grain mass')
    source,weights=boundary_source(graph,velocity)
    if max_iterations is None:max_iterations=2048 if 'boundary_weights' in graph else 512
    grid,edges=network(graph)
    endpoint_operator='boundary_weights' in graph
    def apply(p,low=None):
        if endpoint_operator and low is None:low=[0.]*len(p)
        result=grid.operator(p,low)
        force=boundary_reaction(graph,weights,p,low)
        terms=[[v] for v in result]
        for region,grain,nx,ny in weights:
            terms[region].append(-dt*(nx*force[grain][0]+ny*force[grain][1])/mass[grain])
        return [math.fsum(values) for values in terms]
    precondition=None;precondition_shift=None
    if endpoint_operator:
        from experiments.liquid.model import incomplete_cholesky
        rows=[{} for _ in graph['nodes']]
        def add(i,j,value):rows[i][j]=rows[i].get(j,0.)+value
        for i,j,w in edges:
            add(i,i,w);add(j,j,w);add(i,j,-w);add(j,i,-w)
        per_grain={}
        for region,grain,nx,ny in weights:per_grain.setdefault(grain,[]).append((region,nx,ny))
        for grain,entries in per_grain.items():
            for i,nx,ny in entries:
                for j,mx,my in entries:add(i,j,dt*(nx*mx+ny*my)/mass[grain])
        precondition,precondition_shift=incomplete_cholesky(rows)
    try:
        p,iterations,residual=grid.pressure_for_source(source,tolerance,max_iterations,apply,precondition=precondition,
            compensated=endpoint_operator,apply_compensated=apply if endpoint_operator else None)
    except RuntimeError as error:
        error.endpoint_system=dict(graph=graph,velocity=velocity,mass=mass,dt=dt,
                                   tolerance=tolerance,max_iterations=max_iterations)
        raise
    low=grid.last_pressure_low
    force=boundary_reaction(graph,weights,p,low)
    updated=[list(v) for v in velocity]
    for i,_,_,_ in graph['grains']:
        updated[i]=[v+dt*f/mass[i] for v,f in zip(velocity[i],force[i])]
    final_source,_=boundary_source(graph,updated)
    flux=grid.liquid_flux(p,low)
    continuity=max((abs(a-b) for a,b in zip(grid.divergence(flux),final_source)),default=0.)
    if continuity>tolerance*1.1:raise RuntimeError('Coupled volume residual exceeded')
    return dict(pressure=p,pressure_low=low,precondition_shift=precondition_shift,force=force,velocity=updated,flux=flux,iterations=iterations,
                residual=residual,continuity=continuity,
                dissipation=math.fsum(q*q/w for q,(_,_,w) in zip(flux,edges)))


def pressure(graph,source,tolerance=1e-10,max_iterations=512,precondition=False,source_uncertainty=None,compensated=False):
    """Reference region network: q = opening/distance * pressure difference.

    This positive two-point conductance is not calibrated viscous flow on
    curved/skew regions. Sources are explicit volume rates per region; no
    redistribution across components and no moving-geometry commit occurs.
    """
    if len(source)!=len(graph['nodes']) or any(not math.isfinite(s) for s in source):
        raise ValueError('Invalid region source')
    if source_uncertainty is not None and (len(source_uncertainty)!=len(source) or any(not math.isfinite(x) or x<0 for x in source_uncertainty)):
        raise ValueError('Invalid geometric source uncertainty')
    if not math.isfinite(tolerance) or tolerance<=0 or not isinstance(max_iterations,int) or not 1<=max_iterations<=2048:
        raise ValueError('Invalid pressure budget')
    groups=[[] for _ in range(graph['components'])]
    for i,label in enumerate(graph['labels']):groups[label].append(i)
    for group in groups:
        # Inventory compatibility is stricter than a per-node residual. Do not
        # subtract a component mean to make an impossible source solvable.
        balance=math.fsum(source[i] for i in group)
        bound=max(1e-12,math.fsum(source_uncertainty[i] for i in group)) if source_uncertainty is not None else 1e-12
        if abs(balance)>bound:
            raise ValueError(f'Incompatible source in sealed liquid component: net={balance}')
    grid,edges=network(graph)
    diagonal=[sum(w for _,w in neighbors) or 1. for neighbors in grid.neighbors] if precondition else None
    p,iterations,_=grid.pressure_for_source(source,tolerance,max_iterations,diagonal=diagonal,compensated=compensated)
    low=grid.last_pressure_low
    for group in groups:
        mean=math.fsum(p[i] for i in group)/len(group)
        for i in group:
            if low is None:p[i]-=mean
            else:
                from experiments.liquid.model import add_compensated
                p[i],low[i]=add_compensated(p[i],low[i],-mean)
    flux=grid.liquid_flux(p,low)
    residual=max((abs(a-b) for a,b in zip(grid.divergence(flux),source)),default=0.)
    if residual>tolerance*1.1:raise RuntimeError('Region pressure residual exceeded')
    return dict(pressure=p,pressure_low=low,flux=flux,residual=residual,iterations=iterations,
                dissipation=math.fsum(q*q/w for q,(_,_,w) in zip(flux,edges)),
                source_work=math.fsum(value*s for i,s in enumerate(source)
                                      for value in (p[i],low[i] if low is not None else 0.)))


def coupled_contacts(graph,velocity,mass,contacts,dt=.1,friction=.5,sweeps=128,tolerance=1e-8):
    """Fixed-contact-set reference with pressure-aware impulse responses.

    Contacts are (a,b,nx,ny,gap); b may be -1 for a stationary wall. Normal
    points from a to b, positive relative velocity closes the gap. Response
    columns are a correctness oracle, not a product GPU storage strategy.
    Re-solve pressure with final impulses before checking the contact law.
    """
    if not isinstance(sweeps,int) or not 1<=sweeps<=256 or len(contacts)>64:
        raise ValueError('Invalid contact budget')
    if not math.isfinite(friction) or friction<0 or not math.isfinite(tolerance) or tolerance<=0:
        raise ValueError('Invalid contact parameters')
    grains={i for i,_,_,_ in graph['grains']}
    for a,b,nx,ny,gap in contacts:
        if a not in grains or (b!=-1 and b not in grains) or a==b or not all(math.isfinite(x) for x in (nx,ny,gap)) or abs(nx*nx+ny*ny-1)>1e-10 or gap<0:
            raise ValueError('Invalid fixed contact')
    pressure_tolerance=1e-12 if 'boundary_weights' in graph else 1e-10
    base=coupled_pressure(graph,velocity,mass,dt,tolerance=pressure_tolerance)
    current=[list(v) for v in base['velocity']];columns=[]
    def relative(v,c,direction):
        a,b,nx,ny,_=c;axis=(nx,ny) if direction==0 else (-ny,nx)
        return sum(axis[k]*(v[a][k]-(v[b][k] if b>=0 else 0.)) for k in range(2))
    for c in contacts:
        a,b,nx,ny,_=c;responses=[]
        for direction in ((nx,ny),(-ny,nx)):
            trial=[[0.,0.] for _ in velocity]
            for k in range(2):
                trial[a][k]=-direction[k]/mass[a]
                if b>=0:trial[b][k]=direction[k]/mass[b]
            responses.append(coupled_pressure(graph,trial,mass,dt,tolerance=pressure_tolerance)['velocity'])
        columns.append(responses)
    impulses=[[0.,0.] for _ in contacts]
    for sweep in range(sweeps):
        omega=1. if sweep>=sweeps-8 else 1.9
        for index,c in enumerate(contacts):
            for direction in range(2):
                response=columns[index][direction]
                diagonal=-relative(response,c,direction)
                speed=relative(current,c,direction)-(c[4]/dt if direction==0 else 0.)
                if diagonal<=1e-12:
                    if (speed>tolerance if direction==0 else abs(speed)>tolerance):
                        raise RuntimeError('Degenerate pressure/contact response')
                    continue
                old=impulses[index][direction];target=old+omega*speed/diagonal
                if direction==0:target=max(0.,target)
                else:
                    limit=friction*impulses[index][0];target=max(-limit,min(limit,target))
                impulses[index][direction]=target
                delta=target-old
                for grain in grains:
                    for k in range(2):current[grain][k]+=delta*response[grain][k]
    # Resolve the small identified active set instead of adding more sweeps.
    # Dense elimination is reference-only; final pressure/contact checks below
    # remain authoritative if a sticking/sliding classification changes.
    def merit(v,imp):
        error=0.
        for c,(normal,tangent) in zip(contacts,imp):
            closing=relative(v,c,0)-c[4]/dt;slip=relative(v,c,1)
            limit=friction*max(0.,normal)
            error=max(error,abs(normal-max(0.,normal+closing)),
                      abs(tangent-max(-limit,min(limit,tangent+slip))))
        return error
    polish_merits=[merit(current,impulses)];polish_trace=[]
    # A sealed collinear chain can trade uniform normal contact pressure
    # against the liquid pressure datum without changing any velocity.
    # Report that response null mode; the incremental solve below preserves
    # feasible unresolved coordinates instead of imposing an absolute datum.
    uniform_null=bool(contacts) and max((abs(sum(pair[0][grain][k] for pair in columns))
                                       for grain in grains for k in range(2)),default=0.)<=1e-9
    for _ in range(4):
        rows=[];rhs=[];size=2*len(contacts);all_sticking=True
        for index,c in enumerate(contacts):
            normal,tangent=impulses[index]
            closing=relative(current,c,0)-c[4]/dt
            active=normal+closing>0.
            if active:
                rows.append([relative(response,c,0) for pair in columns for response in pair])
                rhs.append(c[4]/dt-relative(base['velocity'],c,0))
            else:
                rows.append([float(k==2*index) for k in range(size)]);rhs.append(0.)
            slip=relative(current,c,1);limit=friction*max(0.,normal)
            trial=tangent+slip
            if active and abs(trial)<limit:
                rows.append([relative(response,c,1) for pair in columns for response in pair])
                rhs.append(-relative(base['velocity'],c,1))
            else:
                all_sticking=False
                sign=1. if trial>=0 else -1.
                row=[float(k==2*index+1) for k in range(size)]
                if active:row[2*index]=-sign*friction
                rows.append(row);rhs.append(0.)
        # Solve increments with complete pivoting; preserve unresolved impulse
        # null coordinates rather than amplify pressure/contact gauge noise.
        old=[x for pair in impulses for x in pair]
        # A verified uniform response null mode has no velocity constraint.
        # Keep its current mean impulse, rather than invert noisy tiny pivots.
        # Only the all-sticking active set admits this reduced coordinate;
        # inactive/sliding constraints still require the full system.
        anchor=size-2 if uniform_null and all_sticking and size>=4 else None
        coordinates=[k for k in range(size) if k!=anchor]
        width=len(coordinates)
        matrix=[]
        for row,b in zip(rows,rhs):
            reduced=[row[k]-(row[anchor] if anchor is not None and k%2==0 else 0.) for k in coordinates]
            scale=max(map(abs,reduced),default=0.) or 1.
            matrix.append([x/scale for x in reduced]+[(b-math.fsum(a*x for a,x in zip(row,old)))/scale])
        order=list(coordinates);rank=0;pivots=[]
        for k in range(width):
            pivot,column=max(((i,j) for i in range(k,size) for j in range(k,width)),key=lambda ij:abs(matrix[ij[0]][ij[1]]))
            if abs(matrix[pivot][column])<1e-10:break
            pivots.append(abs(matrix[pivot][column]))
            matrix[k],matrix[pivot]=matrix[pivot],matrix[k]
            for row in matrix:row[k],row[column]=row[column],row[k]
            order[k],order[column]=order[column],order[k]
            scale=matrix[k][k];matrix[k]=[x/scale for x in matrix[k]]
            for i in range(size):
                if i==k:continue
                factor=matrix[i][k]
                matrix[i]=[a-factor*b for a,b in zip(matrix[i],matrix[k])]
            rank+=1
        increment=[0.]*size
        for k in range(rank):increment[order[k]]=matrix[k][-1]
        if anchor is not None:increment[anchor]=-math.fsum(increment[::2])
        trial_trace=dict(rank=rank,size=size,minimum_pivot=min(pivots,default=0.),
                         max_increment=max(map(abs,increment),default=0.),trials=[],
                         preserved_uniform_datum=anchor is not None)
        polish_trace.append(trial_trace)
        improved=False
        for backtrack in range(8):
            alpha=2.**(-backtrack)
            solution=[a+alpha*b for a,b in zip(old,increment)]
            candidate_impulses=[solution[i:i+2] for i in range(0,size,2)]
            candidate_velocity=[list(v) for v in base['velocity']]
            for grain in grains:
                for k in range(2):
                    candidate_velocity[grain][k]+=math.fsum(amount*response[grain][k]
                        for pair,values in zip(columns,candidate_impulses) for response,amount in zip(pair,values))
            value=merit(candidate_velocity,candidate_impulses)
            trial_trace['trials'].append(dict(alpha=alpha,merit=value,
                minimum_normal=min((pair[0] for pair in candidate_impulses),default=0.)))
            if value<polish_merits[-1]:
                impulses=candidate_impulses;current=candidate_velocity
                polish_merits.append(value);improved=True;break
        if not improved:break
    applied=[[0.,0.] for _ in velocity]
    for (a,b,nx,ny,_),(normal,tangent) in zip(contacts,impulses):
        impulse=(nx*normal-ny*tangent,ny*normal+nx*tangent)
        for k in range(2):
            applied[a][k]-=impulse[k]
            if b>=0:applied[b][k]+=impulse[k]
    free=[list(v) for v in velocity]
    for grain in grains:
        for k in range(2):free[grain][k]+=applied[grain][k]/mass[grain]
    result=coupled_pressure(graph,free,mass,dt,tolerance=pressure_tolerance)
    residual=0.;worst=None
    for c,(normal,tangent) in zip(contacts,impulses):
        closing=relative(result['velocity'],c,0)-c[4]/dt
        slip=relative(result['velocity'],c,1)
        normal_error=abs(normal-max(0.,normal+closing))
        limit=friction*normal
        tangent_error=abs(tangent-max(-limit,min(limit,tangent+slip)))
        if max(normal_error,tangent_error)>residual:
            residual=max(normal_error,tangent_error);worst=(c,normal,tangent,closing,slip)
    if residual>tolerance:
        error=RuntimeError(f'Coupled contact residual exceeded: {residual}; {worst}; polish={polish_merits}')
        error.contact_diagnostic=dict(polish_trace=polish_trace,uniform_null=uniform_null,
            contacts=contacts,columns=columns,base_velocity=base['velocity'],
            impulses=impulses,rows=rows,rhs=rhs,velocity=current)
        raise error
    result.update(contact_impulse=applied,contact_lambdas=impulses,contact_residual=residual,
                  response_solves=2*len(contacts),contact_sweeps=sweeps,
                  uniform_pressure_contact_null=uniform_null,polish_merits=polish_merits,
                  polish_trace=polish_trace)
    return result
