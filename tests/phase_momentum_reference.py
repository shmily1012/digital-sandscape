"""D2Q9 BGK/Guo momentum reference for the phase-field candidate.

Boussinesq buoyancy is a bounded-density approximation, not air/water density
ratio validation. Lattice dx=dt=1; phase transport uses the same dt.
"""
import math

E = [(0,0),(1,0),(0,1),(-1,0),(0,-1),(1,1),(-1,1),(-1,-1),(1,-1)]
W = [4/9]+[1/9]*4+[1/36]*4
OPPOSITE = [0,3,4,1,2,7,8,5,6]


def equilibrium(side):
    return W * (side*side)


def advance(post, c, wall, side, gravity=(0., 0.0001), sigma=0.002, width=4., tau=0.9, load=None, wall_velocity=None, interface_force=None):
    if not (tau > 0.5 and sigma >= 0 and width > 0):
        raise ValueError('Invalid lattice parameters')
    result = post.copy()
    velocity = [(0.,0.)] * len(c)

    def neighbor(i, dx, dy):
        x,y=i%side+dx,i//side+dy
        if not(0<=x<side and 0<=y<side):return i
        j=y*side+x
        return i if wall[j] else j

    for i in range(len(c)):
        if wall[i]:continue
        east,south,west,north=[neighbor(i,*d) for d in E[1:5]]
        grad=((c[east]-c[west])*.5,(c[south]-c[north])*.5)
        lap=c[east]+c[south]+c[west]+c[north]-4*c[i]
        beta,kappa=12*sigma/width,1.5*sigma*width
        mu=2*beta*c[i]*(1-c[i])*(1-2*c[i])-kappa*lap
        weight=(load[i] if load is not None else 0.)-c[i]
        force=(mu*grad[0]+weight*gravity[0],mu*grad[1]+weight*gravity[1])
        if interface_force is not None:
            force=tuple(interface_force[i][k]+weight*gravity[k] for k in range(2))
        pulled=[];wall_mass_source=0.
        for q,(ex,ey) in enumerate(E):
            j=neighbor(i,-ex,-ey)
            pulled.append(post[i*9+OPPOSITE[q]] if j==i and q else post[j*9+q])
            if wall_velocity is not None and j==i and q:
                x,y=i%side-ex,i//side-ey
                if 0<=x<side and 0<=y<side:
                    uw=wall_velocity[y*side+x]
                    before=pulled[-1]
                    pulled[-1]+=6*W[q]*math.fsum(post[i*9:i*9+9])*(ex*uw[0]+ey*uw[1])
                    wall_mass_source+=pulled[-1]-before
        pulled[0]-=wall_mass_source
        rho=math.fsum(pulled)
        ux=(sum(f*e[0] for f,e in zip(pulled,E))+.5*force[0])/rho
        uy=(sum(f*e[1] for f,e in zip(pulled,E))+.5*force[1])/rho
        velocity[i]=(ux,uy)
        for q,(ex,ey) in enumerate(E[1:],start=1):
            eu=ex*ux+ey*uy
            eq=W[q]*rho*(1+3*eu+4.5*eu*eu-1.5*(ux*ux+uy*uy))
            source=W[q]*(1-.5/tau)*((3*(ex-ux)+9*eu*ex)*force[0]+(3*(ey-uy)+9*eu*ey)*force[1])
            result[i*9+q]=pulled[q]-(pulled[q]-eq)/tau+source
        result[i*9]=rho-math.fsum(result[i*9+1:i*9+9])
    return result,velocity


if __name__ == '__main__':
    import json
    from pathlib import Path
    from phase_field_reference import circle, step
    from grain_load_reference import loads
    from interface_stress_reference import forces as interface_forces
    results=[]
    for with_load,paired,cosine in ((False,False,0.),(True,False,0.),(False,True,0.),(False,True,.5),(False,True,-.5)):
        n=24
        initial,wall=circle(n,(11.,12.),4.)
        wall=[int(w) for w in wall]
        if with_load or paired:
            for y in range(3,7):wall[y*n+11]=2;initial[y*n+11]=0.
        load=loads(wall,n,(0.,.0001)) if with_load else None
        c=initial.copy();post=equilibrium(n)
        for _ in range(80):
            capillary=interface_forces(c,wall,n,sigma=.002,wetting_cosine=cosine) if paired else None
            post,velocity=advance(post,c,wall,n,load=load,interface_force=capillary)
            c,_=step(c,n,velocity,wall,dt=1.,wetting_cosine=cosine)
        results.append(dict(loaded=with_load,paired=paired,wetting_cosine=cosine,side=n,steps=80,initial=initial,wall=wall,expected=c,
                            velocity=[v for pair in velocity for v in pair],mass=math.fsum(initial)))
    (Path(__file__).resolve().parents[1]/'reports/phase-coupled-fixture.json').write_text(json.dumps(results),encoding='utf-8')
