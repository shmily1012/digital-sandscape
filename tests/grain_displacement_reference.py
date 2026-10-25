"""Independent conservative remap reference for the optional kinematic path."""
import math


def step(material, velocity, offset, n, dt=1.):
    count=n*n
    target=list(range(count)); incoming={}
    if not 0<dt<=1: return None
    for a, m in enumerate(material):
        if m not in range(5) or not all(math.isfinite(x) for x in (*velocity[a],*offset[a])):return None
        if m<2:
            if any((*velocity[a],*offset[a])):return None
            continue
        d=[x*dt for x in velocity[a]]
        if any(abs(x)>.25 for x in d) or any(not -.5<=x<.5 for x in offset[a]):return None
        dest=[a%n+math.floor(offset[a][0]+d[0]+.5),a//n+math.floor(offset[a][1]+d[1]+.5)]
        if any(not 0<=x<n for x in dest):return None
        b=dest[1]*n+dest[0]
        if material[b]==1 or b in incoming:return None
        incoming[b]=a;target[a]=b
        # All pairs in the reference, independent of GPU neighborhood indexing.
        for j, other in enumerate(material):
            if j==a or not other:continue
            sep=[j%n-a%n+offset[j][0]-offset[a][0],j//n-a//n+offset[j][1]-offset[a][1]]
            rel=[(velocity[j][k]-velocity[a][k])*dt for k in range(2)]
            enter,leave=0.,1.
            for k in range(2):
                if abs(rel[k])<1e-12:
                    if abs(sep[k])>=1.-1e-6:leave=-1.
                else:
                    times=[(-1.+1e-6-sep[k])/rel[k],(1.-1e-6-sep[k])/rel[k]]
                    enter=max(enter,min(times));leave=min(leave,max(times))
            if leave>enter:return None
    sources=[];new_velocity=[];new_offset=[]
    for a,m in enumerate(material):
        source=incoming.get(a,a)
        if a not in incoming and m>=2:
            for _ in range(32):
                if material[source]<2:break
                source=target[source]
            if material[source]!=0:return None
        sources.append(source)
        new_velocity.append(list(velocity[source]) if a in incoming else [0.,0.])
        local=[offset[source][k]+velocity[source][k]*dt for k in range(2)]
        new_offset.append([x-math.floor(x+.5) for x in local] if a in incoming else [0.,0.])
    return sources,new_velocity,new_offset


def fixtures():
    cases=[]
    for name in ('single','chain','vertical','diagonal','wall','corner','escape','long-chain'):
        n=40 if name=='long-chain' else 9
        m=[0]*(n*n);v=[[0.,0.] for _ in m];o=[[0.,0.] for _ in m]
        positions=[(2,3)]
        speed=[.0625,0.]
        if name=='chain':positions=[(x,3) for x in range(2,6)]
        if name=='vertical':positions=[(3,y) for y in range(2,6)];speed=[0.,.0625]
        if name=='diagonal':speed=[.0625,.0625]
        if name=='escape':positions=[(8,3)]
        if name=='corner':speed=[.0625,.0625];m[4*n+3]=1
        if name=='wall':m[3*n+3]=1
        if name=='long-chain':positions=[(x,3) for x in range(1,35)]
        for k,(x,y) in enumerate(positions):m[y*n+x]=2+k%3;v[y*n+x]=speed[:]
        initial=m[:];initial_v=[x[:] for x in v];labels=list(range(n*n));frames=[]
        for _ in range(20):
            result=step(m,v,o,n)
            if result is not None:
                sources,v,o=result;m=[m[i] for i in sources];labels=[labels[i] for i in sources]
            frames.append(dict(accepted=result is not None,materials=m[:],velocity=[x[:] for x in v],offset=[x[:] for x in o],sources=labels[:]))
            if result is None:break
        cases.append(dict(name=name,side=n,materials=initial,velocity=initial_v,frames=frames))
    return cases


def joint_fixtures():
    from grain_contact_impulse_reference import solve, closing_speed
    cases=[]
    for name in ('gap-wall','joint-chain','joint-reject','near-corner-clearance','near-corner-overlap'):
        n=9;m=[0]*(n*n);v=[[0.,0.] for _ in m];o=[[0.,0.] for _ in m]
        a=3*n+2;m[a]=2;v[a]=[.0625,0.]
        if name=='gap-wall':m[a+1]=1;o[a]=[-.125,0.]
        if name=='joint-chain':
            for x in range(3,6):m[3*n+x]=2+x%3
        if name=='joint-reject':m[a+1]=3;m[a+1+n]=1;v[a]=[.0625,.0625]
        if name.startswith('near-corner'):
            b=a-n-1;m[b]=3
            o[a]=[-.00001,.12]
            gap=.93e-6 if name=='near-corner-clearance' else 1.2e-6
            o[b]=[o[a][0]+gap,o[a][1]+1.14e-6]
            v[a]=[0.,.00011];v[b]=[1e-9,.000110001]

        initial=m[:];initial_v=[x[:] for x in v];initial_o=[x[:] for x in o]
        labels=list(range(n*n));frames=[]
        for _ in range(12):
            candidate,reaction=solve(m,v,n,128,.5,o)
            result=step(m,candidate,o,n) if closing_speed(m,candidate,n,o)<=1e-7 else None
            if result is not None:
                sources,v,o=result;m=[m[i] for i in sources];labels=[labels[i] for i in sources]
            frames.append(dict(accepted=result is not None,materials=m[:],velocity=[x[:] for x in v],offset=[x[:] for x in o],sources=labels[:],reaction=reaction if result is not None else [[0.,0.] for _ in m]))
            if result is None:break
        cases.append(dict(name=name,side=n,materials=initial,velocity=initial_v,initial_offset=initial_o,frames=frames,joint=True))
    return cases


def forced_fixtures():
    from grain_contact_impulse_reference import solve, closing_speed, MASS
    from grain_traction_reference import traction
    from phase_momentum_reference import advance, E, W
    cases=[]
    for name in ('fluid-drag','gravity-wall','oblique-gravity'):
        n=9;m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        a=(7 if name=='gravity-wall' else 4)*n+4;m[a]=3
        v=[[0.,0.] for _ in m];o=[[0.,0.] for _ in m]
        if name=='fluid-drag':v[a]=[.001,0.]
        g=[.000012,.000016] if name=='oblique-gravity' else [0.,.00002]
        f=[]
        for i in range(n*n):
            flow=.002 if m[i]==0 else 0.
            for q,e in enumerate(E):
                eu=e[0]*flow;f.append(W[q]*(1+3*eu+4.5*eu*eu-1.5*flow*flow))
        impulse=traction(f,m,n,True,v)
        predicted=[[(v[i][k]+impulse[i][k]/MASS[mi]+(1-1/MASS[mi])*g[k]) if mi>=2 else v[i][k] for k in range(2)] for i,mi in enumerate(m)]
        candidate,reaction=solve(m,predicted,n,128,.5,o)
        result=step(m,candidate,o,n) if closing_speed(m,candidate,n,o)<=1e-7 else None
        assert result is not None,name
        sources,nv,no=result
        next_f,_=advance(f,[0.]*(n*n),m,n,gravity=g,sigma=0.,wall_velocity=v)
        frame=dict(accepted=True,materials=[m[i] for i in sources],velocity=nv,offset=no,sources=sources,reaction=reaction)
        cases.append(dict(name=name,side=n,materials=m,velocity=v,initial_offset=o,frames=[frame],joint=True,forced=True,gravity=g,populations=f,fluid_next=next_f,raw_impulse=impulse))
    return cases


def coupled_fixtures():
    from grain_contact_impulse_reference import solve, closing_speed, MASS
    from grain_traction_reference import traction
    from phase_momentum_reference import advance, equilibrium
    from phase_field_reference import step as phase_step, circle
    cases=[]
    for name in ('coupled-fall','coupled-crossing','coupled-phase','coupled-reject'):
        n=16 if name=='coupled-phase' else 9
        m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        c=[0.]*(n*n)
        if name=='coupled-phase':c,_=circle(n,(10.,9.),2.)
        a=3*n+3;m[a]=2;c[a]=0.
        for i in range(n*n):
            if m[i]:c[i]=0.
        v=[[0.,0.] for _ in m];o=[[0.,0.] for _ in m]
        if name=='coupled-crossing':v[a]=[.01,0.];o[a]=[.499,0.]
        if name=='coupled-reject':m[a+1]=3;m[a+1+n]=1;v[a]=[.0625,.0625]
        f=equilibrium(n);g=[0.,.00002];sigma=.002
        initial=dict(materials=m[:],phase=c[:],populations=f[:],velocity=[x[:] for x in v],offset=[x[:] for x in o])
        frames=[];ticks=0
        for _ in range(12):
            impulse=traction(f,m,n,True,v)
            predicted=[[(v[i][k]+impulse[i][k]/MASS[mi]+(1-1/MASS[mi])*g[k]) if mi>=2 else v[i][k] for k in range(2)] for i,mi in enumerate(m)]
            cv,reaction=solve(m,predicted,n,128,.5,o)
            nf,u=advance(f,c,m,n,gravity=g,sigma=sigma,wall_velocity=v)
            nc,_=phase_step(c,n,u,m,dt=1.)
            result=step(m,cv,o,n) if closing_speed(m,cv,n,o)<=1e-7 else None
            if result is not None:
                sources,nv,no=result
                if any(m[i]==0 and m[source]>=2 and nc[i]>.05 for i,source in enumerate(sources)):result=None
            if result is not None:
                sources,v,o=result;m=[m[i] for i in sources];c=[nc[i] for i in sources];f=[nf[9*i+q] for i in sources for q in range(9)];ticks+=1
            frames.append(dict(accepted=result is not None,ticks=ticks,materials=m[:],phase=c[:],populations=f[:],velocity=[x[:] for x in v],offset=[x[:] for x in o]))
            if result is None:break
        cases.append(dict(name=name,side=n,gravity=g,sigma=sigma,initial=initial,frames=frames))
    return cases
