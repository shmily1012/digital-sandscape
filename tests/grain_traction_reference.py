"""Gauge-subtracted, stationary-link traction estimator used by the voxel model."""
from phase_momentum_reference import E, W, OPPOSITE


def traction_components(f, material, n):
    """Exact linear split of the old estimator, not a new force prescription.

    pressure uses W*rho; odd is opposite-direction antisymmetry; even is the
    remaining non-isotropic population. Odd is not assumed pure viscous drag.
    """
    pressure = [0.] * len(f)
    odd = [0.] * len(f)
    for i in range(len(material)):
        rho = sum(f[9*i:9*i+9])
        for q in range(9):
            pressure[9*i+q] = W[q]*rho
            odd[9*i+q] = .5*(f[9*i+q]-f[9*i+OPPOSITE[q]])
    even = [value-p-o for value,p,o in zip(f,pressure,odd)]
    return {name: traction(values,material,n) for name,values in
            [('pressure',pressure), ('odd',odd), ('even',even)]}


def traction(f, material, n, raw_impulse=False, wall_velocity=None):
    result=[(0.,0.)]*len(material)
    for i,m in enumerate(material):
        if m==0 or (m==1 and not raw_impulse):continue
        links=[]
        for q,(dx,dy) in enumerate(E[1:],start=1):
            x,y=i%n+dx,i//n+dy
            if not(0<=x<n and 0<=y<n):continue
            j=y*n+x
            if material[j]==0:links.append((q,j))
        if not links:continue
        background=sum(sum(f[9*j:9*j+9]) for _,j in links)/len(links)
        force=[0.,0.]
        for q,j in links:
            excess=f[9*j+OPPOSITE[q]]-(0. if raw_impulse else W[q]*background)
            for axis in range(2):force[axis]-=2*E[q][axis]*excess
            if raw_impulse and wall_velocity is not None:
                uw=wall_velocity[i]
                correction=6*W[q]*sum(f[9*j:9*j+9])*(E[q][0]*uw[0]+E[q][1]*uw[1])
                for axis in range(2):force[axis]-=E[q][axis]*correction
        result[i]=tuple(force)
    return result


def cases():
    result=[]
    n=12;center=6*n+6
    for name,base,gradient,flow,partial in [
        ('uniform',1.,0.,0.,False),('partial_uniform',2.,0.,0.,True),
        ('flow',1.,0.,.01,False),('pressure',1.,.001,0.,False)]:
        m=[1 if x in (0,n-1) or y in (0,n-1) else 0 for y in range(n) for x in range(n)]
        m[center]=2
        if partial:m[center-n]=1
        f=[]
        for i in range(n*n):
            rho=base+gradient*(i//n-6)
            for q,e in enumerate(E):
                eu=e[0]*flow
                f.append(W[q]*rho*(1+3*eu+4.5*eu*eu-1.5*flow*flow))
        expected=traction(f,m,n)
        result.append(dict(name=name,side=n,center=center,materials=m,populations=f,
                           expected=[v for pair in expected for v in pair],
                           raw_expected=[v for pair in traction(f,m,n,True) for v in pair]))
    return result


if __name__=='__main__':
    import json
    from pathlib import Path
    (Path(__file__).resolve().parents[1]/'reports/grain-traction-fixture.json').write_text(json.dumps(cases()),encoding='utf-8')
