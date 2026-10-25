"""Endpoint box areas and coordinate-path volume flux; no fluid solve.

Reuses the conservative split-path construction from deposition/disk_volume.py,
with analytic unit-box overlap matching the current contact geometry.
"""
import json
import math
from pathlib import Path


def occupancy(material, offset, n, shape='box'):
    if shape not in ('box','disk'):raise ValueError('Unknown grain shape')
    if shape=='disk':
        import sys
        root=str(Path(__file__).resolve().parents[1])
        if root not in sys.path:sys.path.insert(0,root)
        from experiments.deposition.disk_volume import disk_rectangle_area
    area=[0.]*(n*n)
    for i,m in enumerate(material):
        if not m:continue
        cx=i%n+(offset[i][0] if m>=2 else 0.)
        cy=i//n+(offset[i][1] if m>=2 else 0.)
        for y in range(max(0,math.floor(cy)-1),min(n,math.floor(cy)+3)):
            for x in range(max(0,math.floor(cx)-1),min(n,math.floor(cx)+3)):
                width=max(0.,min(x+.5,cx+.5)-max(x-.5,cx-.5))
                height=max(0.,min(y+.5,cy+.5)-max(y-.5,cy-.5))
                area[y*n+x]+=(disk_rectangle_area(cx,cy,.5,x-.5,y-.5,x+.5,y+.5)
                               if shape=='disk' and m>=2 else width*height)
    return area


def geometry(material, offset, velocity, n, dt=1., shape='box'):
    end=[[o[k]+(v[k]*dt if material[i]>=2 else 0.) for k in range(2)]
         for i,(o,v) in enumerate(zip(offset,velocity))]
    old,new=occupancy(material,offset,n,shape),occupancy(material,end,n,shape)
    midx=[[b[0],a[1]] for a,b in zip(offset,end)]
    midy=[[a[0],b[1]] for a,b in zip(offset,end)]
    ax,ay=occupancy(material,midx,n,shape),occupancy(material,midy,n,shape)
    flux=[[0.,0.] for _ in material]
    for before,after,axis in ((old,ax,0),(ay,new,0),(old,ay,1),(ax,new,1)):
        for line in range(n):
            cumulative=0.
            for k in range(n):
                i=line*n+k if axis==0 else k*n+line
                cumulative+=(before[i]-after[i])/(2*dt)
                flux[i][axis]+=cumulative
    return [[1-a,1-b,*f] for a,b,f in zip(old,new,flux)]


def apertures(material, offset, velocity, n, dt=1., shape='box'):
    if shape not in ('box','disk'):raise ValueError('Unknown grain shape')
    result=[[0.,0.] for _ in material]
    for time in (0.,dt):
        centers=[(i%n+(offset[i][0]+time*velocity[i][0] if m>=2 else 0.),
                  i//n+(offset[i][1]+time*velocity[i][1] if m>=2 else 0.),m)
                 for i,m in enumerate(material) if m]
        for i in range(n*n):
            for axis in range(2):
                normal=(i%n if axis==0 else i//n)+.5
                low=(i//n if axis==0 else i%n)-.5
                segments=[];cuts={low,low+1}
                for center in centers:
                    if abs(center[axis]-normal)>.5:continue
                    half=(math.sqrt(max(0.,.25-(center[axis]-normal)**2))
                          if shape=='disk' and center[2]>=2 else .5)
                    a=max(low,center[1-axis]-half);b=min(low+1,center[1-axis]+half)
                    if b>a:segments.append((a,b));cuts.update((a,b))
                cuts=sorted(cuts);covered=math.fsum(b-a for a,b in zip(cuts,cuts[1:])
                    if any(x<=(a+b)/2<=y for x,y in segments))
                result[i][axis]+=.5*(1-covered)
    return result


def project(case):
    import sys
    root=str(Path(__file__).resolve().parents[1])
    if root not in sys.path:sys.path.insert(0,root)
    from experiments.liquid.model import DarcyGrid
    n=case['side'];grid=DarcyGrid(n);grid.h=1.
    grid.faces=[(i,j,case['aperture'][i][axis],axis) for i,j,_,axis in grid.faces]
    solid=[case['expected'][i][2+axis] for i,j,_,axis in grid.faces]
    projection=grid.project(solid,tolerance=1e-11,max_iterations=1024)
    flux=[[0.,0.] for _ in case['material']]
    for value,(i,j,_,axis) in zip(projection.liquid,grid.faces):flux[i][axis]=value
    return flux,projection.pressure


def fixtures():
    result=[]
    for angle in (0,30,45,90,120,180,270,337):
        n=12;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
        m[65]=2;o[65]=[.49,-.31]
        v[65]=[.02*math.cos(math.radians(angle)),.02*math.sin(math.radians(angle))]
        result.append(dict(name=f'angle-{angle}',side=n,material=m,offset=o,velocity=v,valid=True))
    n=32;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
    o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
    for y in range(3,23):m[y*n+16]=2+(y%3);o[y*n+16]=[0.,.49];v[y*n+16]=[0.,.02]
    result.append(dict(name='twenty-grain-chain',side=n,material=m,offset=o,velocity=v,valid=True))
    n=12;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
    o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
    m[5*n+1]=2;o[5*n+1]=[-.49,0.];v[5*n+1]=[-.02,0.]
    result.append(dict(name='wall-overlap',side=n,material=m,offset=o,velocity=v,valid=False))
    for case in result:
        case['expected']=geometry(case['material'],case['offset'],case['velocity'],case['side'])
        case['aperture']=apertures(case['material'],case['offset'],case['velocity'],case['side'])
        if case['valid']:
            case['fluid_flux'],case['pressure']=project(case)
            from drainage_reaction_reference import reaction
            case['pressure_reaction']=reaction(case)
            from local_gas_reference import profiles
            case['gas_profiles']=profiles(case)
    return result


if __name__=='__main__':
    (Path(__file__).resolve().parents[1]/'reports/grain-volume-fixture.json').write_text(json.dumps(fixtures()))
