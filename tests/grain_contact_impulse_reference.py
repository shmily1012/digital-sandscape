"""Inelastic voxel-face impulse operator, not a complete grain timestep."""
import json
import math
from pathlib import Path

MASS={2:3.,3:2.7,4:2.4}


def solve(material, velocity, n, sweeps=8, friction=.5, offset=None, dt=1., relaxation=0., impulses_out=None):
    offset=offset or [[0.,0.] for _ in material]
    velocity=[list(v) for v in velocity]
    reaction=[[0.,0.] for _ in material]
    impulses=[[[0.,0.] for _ in material] for _ in range(2)]
    edges=[[[a for a,ma in enumerate(material) if ma and (a%n if axis==0 else a//n)%2==parity and (a%n if axis==0 else a//n)+1<n and material[a+(1 if axis==0 else n)] and not (ma==material[a+(1 if axis==0 else n)]==1)] for parity in range(2)] for axis in range(2)]
    for sweep in range(sweeps):
        omega=1. if relaxation and sweep>=sweeps-8 else relaxation
        for axis in range(2):
            for parity in range(2):
                for a in edges[axis][parity]:
                    ma=material[a]
                    coordinate=a%n if axis==0 else a//n
                    if coordinate%2!=parity or coordinate+1>=n:continue
                    b=a+(1 if axis==0 else n);mb=material[b]
                    if ma==0 or mb==0 or ma==mb==1:continue
                    ia=1/MASS[ma] if ma>=2 else 0.
                    ib=1/MASS[mb] if mb>=2 else 0.
                    relative=[velocity[a][k]-velocity[b][k] for k in range(2)]
                    closing=relative[axis]-max(0.,offset[b][axis]-offset[a][axis])/dt
                    if relaxation==0 and closing<=0:continue
                    normal=closing/(ia+ib)
                    # t is (-ny,nx).
                    tangent_speed=relative[1] if axis==0 else -relative[0]
                    tangent=max(-friction*normal,min(friction*normal,tangent_speed/(ia+ib)))
                    if relaxation:
                        old=impulses[axis][a]
                        nn=max(0.,old[0]+omega*closing/(ia+ib))
                        nt=max(-friction*nn,min(friction*nn,old[1]+omega*tangent_speed/(ia+ib)))
                        normal,tangent=nn-old[0],nt-old[1]
                        impulses[axis][a]=[nn,nt]
                    impulse=[normal,tangent] if axis==0 else [-tangent,normal]
                    for k in range(2):
                        velocity[a][k]-=ia*impulse[k];velocity[b][k]+=ib*impulse[k]
                        reaction[a][k]-=impulse[k];reaction[b][k]+=impulse[k]
    if impulses_out is not None:impulses_out.extend(impulses)
    return velocity,reaction


def closing_speed(material,velocity,n,offset=None,dt=1.):
    offset=offset or [[0.,0.] for _ in material]
    result=0.
    for a,ma in enumerate(material):
        for axis in range(2):
            coordinate=a%n if axis==0 else a//n
            if coordinate+1>=n:continue
            b=a+(1 if axis==0 else n);mb=material[b]
            if ma and mb and (ma>=2 or mb>=2):
                result=max(result,velocity[a][axis]-velocity[b][axis]-max(0.,offset[b][axis]-offset[a][axis])/dt)
    return result


def guarded_solve(material,velocity,n,sweeps=8,friction=.5):
    candidate,reaction=solve(material,velocity,n,sweeps,friction)
    accepted=all(math.isfinite(x) for vectors in (candidate,reaction) for v in vectors for x in v)
    accepted=accepted and closing_speed(material,candidate,n)<=1e-7
    return accepted,(candidate if accepted else [list(v) for v in velocity]),(reaction if accepted else [[0.,0.] for _ in material])


def metrics(material, before, after, reaction):
    momentum=lambda v:[math.fsum(MASS[m]*v[i][a] for i,m in enumerate(material) if m>=2) for a in range(2)]
    energy=lambda v:math.fsum(.5*MASS[m]*sum(x*x for x in v[i]) for i,m in enumerate(material) if m>=2)
    old,new=momentum(before),momentum(after)
    wall=[math.fsum(reaction[i][a] for i,m in enumerate(material) if m==1) for a in range(2)]
    # Prescribed walls provide the work opposite to their received impulse.
    work=-math.fsum(sum(reaction[i][a]*before[i][a] for a in range(2)) for i,m in enumerate(material) if m==1)
    return dict(momentum_residual=math.hypot(*(new[a]-old[a]+wall[a] for a in range(2))),
                initial_energy=energy(before),final_energy=energy(after),wall_work=work)


def fixtures():
    cases=[]
    for name in ('pair','separating','wall','moving-wall','chain'):
        n=9 if name=='chain' else 8
        m=[0]*(n*n);v=[(0.,0.)]*(n*n);center=3*n+3
        m[center]=2;v[center]=(.02,.01)
        if name in ('pair','separating'):
            m[center+1]=4
            if name=='separating':v[center]=(-.02,.01)
        elif name in ('wall','moving-wall'):
            m[center+1]=1
            if name=='moving-wall':v[center+1]=(-.01,0.)
        else:
            for x in range(1,6):m[3*n+x]=2+x%3;v[3*n+x]=(.02,.01)
            m[3*n+6]=1
        for friction in (0.,.5):
            expected,reaction=solve(m,v,n,32,friction)
            cases.append(dict(name=name,orientation=0,side=n,materials=m,velocity=v,sweeps=32,friction=friction,
                              expected=expected,reaction=reaction))
    rotated=[]
    for data in cases:
        n=data['side'];m=[0]*(n*n);v=[(0.,0.)]*(n*n)
        for i,material in enumerate(data['materials']):
            j=(i%n)*n+(n-1-i//n);m[j]=material
            vx,vy=data['velocity'][i];v[j]=(-vy,vx)
        expected,reaction=solve(m,v,n,data['sweeps'],data['friction'])
        rotated.append(dict(data,orientation=1,materials=m,velocity=v,expected=expected,reaction=reaction))
    cases+=rotated
    for data in cases:
        data['accepted']=closing_speed(data['materials'],data['expected'],data['side'])<=1e-7
        if data['name']=='chain':
            data['recovery_expected'],_=solve(data['materials'],data['velocity'],data['side'],128,data['friction'])
    return cases


def projected_residual(material,velocity,n,impulses,friction=.5,offset=None,dt=1.):
    offset=offset or [[0.,0.] for _ in material]
    residual=0.
    for a,ma in enumerate(material):
        for axis in range(2):
            coordinate=a%n if axis==0 else a//n
            if coordinate+1>=n:continue
            b=a+(1 if axis==0 else n);mb=material[b]
            if not ma or not mb or ma==mb==1:continue
            inv=(1/MASS[ma] if ma>=2 else 0)+(1/MASS[mb] if mb>=2 else 0)
            closing=velocity[a][axis]-velocity[b][axis]-max(0.,offset[b][axis]-offset[a][axis])/dt
            vt=(velocity[a][1]-velocity[b][1]) if axis==0 else (velocity[b][0]-velocity[a][0])
            old=impulses[axis][a]
            projected=[max(0.,old[0]+closing/inv),max(-friction*old[0],min(friction*old[0],old[1]+vt/inv))]
            residual=max(residual,closing,*(abs(projected[k]-old[k])*inv for k in range(2)))
    return residual


def projected_fixtures():
    cases=[]
    for data in fixtures():
        for omega in (1.5,1.9):
            impulses=[]
            v,r=solve(data['materials'],data['velocity'],data['side'],128,data['friction'],relaxation=omega,impulses_out=impulses)
            residual=projected_residual(data['materials'],v,data['side'],impulses,data['friction'])
            cases.append(dict(data,relaxation=omega,sweeps=128,expected=v,reaction=r,residual=residual,accepted=residual<=1e-7))
    return cases


def solve_box_contacts(material, velocity, offset, n, sweeps=128, friction=.5, relaxation=1.9,corner_relaxation=None,correction_sweeps=64,diagnostics=None):
    velocity=[list(v) for v in velocity];reaction=[[0.,0.] for _ in material]
    directions=[(1,0),(0,1),(1,1),(-1,1)];edges=[[],[],[],[]]
    def build(direction):
        dx,dy=directions[direction]
        for a,ma in enumerate(material):
            x,y=a%n+dx,a//n+dy
            if not ma or not(0<=x<n and 0<=y<n):continue
            b=y*n+x;mb=material[b]
            if not mb or ma==mb==1:continue
            if direction<2:normal=[dx,dy]
            else:
                gaps=[(offset[b][k]-offset[a][k])*sign for k,sign in enumerate((dx,dy))]
                rates=[(velocity[b][k]-velocity[a][k])*sign for k,sign in enumerate((dx,dy))]
                enter,leave=0.,1.
                for gap,rate in zip(gaps,rates):
                    if abs(rate)<1e-12:
                        if gap>=-1e-6:leave=-1.
                    else:
                        t=(-1e-6-gap)/rate
                        if rate<0:enter=max(enter,t)
                        else:leave=min(leave,t)
                if leave<=enter:continue
                predicted=[gaps[k]+rates[k] for k in range(2)]
                axis=0 if (gaps[0]>gaps[1] or (gaps[0]==gaps[1] and predicted[0]>=predicted[1])) else 1
                normal=[dx,0] if axis==0 else [0,1]
            gap=max(0.,sum((offset[b][k]-offset[a][k])*normal[k] for k in range(2)))
            edges[direction].append([a,b,normal,gap,[0.,0.]])
    build(0);build(1)
    for sweep in range(sweeps+correction_sweeps):
        if sweep==sweeps:build(2);build(3)
        base=relaxation if sweep<sweeps or corner_relaxation is None else corner_relaxation
        omega=1. if ((sweep>=sweeps-8 and sweep<sweeps) or sweep>=sweeps+correction_sweeps-8) else base
        for direction in range(4):
            for parity in range(2):
                for edge in edges[direction]:
                    a,b,normal,gap,old=edge
                    if (a//n if direction==1 else a%n)%2!=parity:continue
                    ia=1/MASS[material[a]] if material[a]>=2 else 0.
                    ib=1/MASS[material[b]] if material[b]>=2 else 0.
                    tangent=[-normal[1],normal[0]];relative=[velocity[a][k]-velocity[b][k] for k in range(2)]
                    closing=sum(relative[k]*normal[k] for k in range(2))-gap
                    speed=sum(relative[k]*tangent[k] for k in range(2))
                    nn=max(0.,old[0]+omega*closing/(ia+ib))
                    nt=max(-friction*nn,min(friction*nn,old[1]+omega*speed/(ia+ib)))
                    impulse=[(nn-old[0])*normal[k]+(nt-old[1])*tangent[k] for k in range(2)]
                    edge[4]=[nn,nt]
                    for k in range(2):
                        velocity[a][k]-=ia*impulse[k];velocity[b][k]+=ib*impulse[k]
                        reaction[a][k]-=impulse[k];reaction[b][k]+=impulse[k]
    residual=0.
    for direction,group in enumerate(edges):
        for a,b,normal,gap,total in group:
            inv=(1/MASS[material[a]] if material[a]>=2 else 0)+(1/MASS[material[b]] if material[b]>=2 else 0)
            tangent=[-normal[1],normal[0]];relative=[velocity[a][k]-velocity[b][k] for k in range(2)]
            closing=sum(relative[k]*normal[k] for k in range(2))-gap
            speed=sum(relative[k]*tangent[k] for k in range(2))
            nr=closing if closing>=0 else min(-closing,total[0]*inv)
            tr=min(speed,max(0.,friction*total[0]-total[1])*inv) if speed>=0 else min(-speed,max(0.,friction*total[0]+total[1])*inv)
            if diagnostics is not None and max(nr,tr)>1e-8:
                diagnostics.append(dict(a=a,b=b,direction=direction,normal=normal,gap=gap,impulse=total,normal_residual=nr,tangent_residual=tr,closing=closing,tangent_speed=speed))
            residual=max(residual,nr,tr)
    return velocity,reaction,residual


def diagonal_fixtures():
    cases=[];n=9;a=3*n+4
    for dx in (1,-1):
        for axis in (0,1):
            for wall in (False,True):
                for friction in (0.,.5):
                    m=[0]*(n*n);v=[[0.,0.] for _ in m];offset=[[0.,0.] for _ in m]
                    b=a+n+dx;m[a]=2;m[b]=1 if wall else 4
                    offset[b]=[0.,-.02] if axis==0 else [-.02*dx,0.]
                    if wall:offset[a]=[-x for x in offset[b]];offset[b]=[0.,0.]
                    v[a]=[.04*dx,.01] if axis==0 else [.01*dx,.04]
                    expected,reaction,residual=solve_box_contacts(m,v,offset,n,friction=friction)
                    cases.append(dict(name='diagonal',side=n,materials=m,velocity=v,offset=offset,expected=expected,reaction=reaction,residual=residual,accepted=residual<=1e-7,friction=friction,relaxation=1.9,diagonals=True))
    m=[0]*(n*n);v=[[0.,0.] for _ in m];offset=[[0.,0.] for _ in m]
    m[a]=2;m[a+1]=4;offset[a+1]=[-5e-7,0.]
    expected,reaction,residual=solve_box_contacts(m,v,offset,n)
    cases.append(dict(name='resting-tolerance-overlap',side=n,materials=m,velocity=v,offset=offset,expected=expected,reaction=reaction,residual=residual,accepted=residual<=1e-7,friction=.5,relaxation=1.9,diagonals=True))
    return cases


if __name__=='__main__':
    from grain_volume_reference import fixtures as volume_fixtures
    (Path(__file__).resolve().parents[1]/'reports/grain-volume-fixture.json').write_text(json.dumps(volume_fixtures()),encoding='utf-8')
    from interface_stress_reference import fixtures as interface_fixtures
    (Path(__file__).resolve().parents[1]/'reports/interface-stress-fixture.json').write_text(json.dumps(interface_fixtures()),encoding='utf-8')
    from grain_displacement_reference import fixtures as displacement_fixtures, joint_fixtures, forced_fixtures, coupled_fixtures
    (Path(__file__).resolve().parents[1]/'reports/grain-displacement-fixture.json').write_text(json.dumps(displacement_fixtures()+joint_fixtures()+forced_fixtures()),encoding='utf-8')
    (Path(__file__).resolve().parents[1]/'reports/grain-coupled-fixture.json').write_text(json.dumps(coupled_fixtures()),encoding='utf-8')
    (Path(__file__).resolve().parents[1]/'reports/grain-projected-fixture.json').write_text(json.dumps(projected_fixtures()+diagonal_fixtures()),encoding='utf-8')
    (Path(__file__).resolve().parents[1]/'reports/grain-contact-impulse-fixture.json').write_text(json.dumps(fixtures()),encoding='utf-8')
