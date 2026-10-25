"""Two-phase PLIC face transport with conservative bounded flux correction.

This reconstructs local interface geometry from the current volume fraction.
It never replaces the global shape. No momentum or capillary law lives here.
"""
import math


def polygon_area(vertices):
    if len(vertices)<3:
        return 0.0
    return abs(sum(x*v-y*u for (x,y),(u,v) in zip(vertices,vertices[1:]+vertices[:1])))*0.5


def clip_polygon(vertices, normal, offset):
    result=[]
    if not vertices:
        return result
    nx,ny=normal
    for a,b in zip(vertices,vertices[1:]+vertices[:1]):
        da,db=nx*a[0]+ny*a[1]-offset,nx*b[0]+ny*b[1]-offset
        if da>=0:
            result.append(a)
        if (da>=0)!=(db>=0):
            t=da/(da-db)
            result.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return result


SQUARE=[(0.0,0.0),(1.0,0.0),(1.0,1.0),(0.0,1.0)]


def reconstruct_polygons(grid,fraction):
    neighbors=[[[None,None] for _ in fraction] for _ in range(2)]
    for i,j,_,axis in grid.faces:
        neighbors[axis][i][1]=j
        neighbors[axis][j][0]=i
    polygons=[]
    for i,c in enumerate(fraction):
        if c<=0:
            polygons.append([])
            continue
        if c>=1:
            polygons.append(SQUARE)
            continue
        gradient=[]
        for axis in range(2):
            left,right=neighbors[axis][i]
            gradient.append((fraction[right] if right is not None else c)-(fraction[left] if left is not None else c))
        magnitude=math.hypot(*gradient)
        normal=tuple(v/magnitude for v in gradient) if magnitude>1e-14 else (1.0,0.0)
        projections=[normal[0]*x+normal[1]*y for x,y in SQUARE]
        low,high=min(projections),max(projections)
        for _ in range(48):
            middle=(low+high)*0.5
            area=polygon_area(clip_polygon(SQUARE,normal,middle))
            if area>c:
                low=middle
            else:
                high=middle
        polygons.append(clip_polygon(SQUARE,normal,(low+high)*0.5))
    return polygons


def advect(grid,fraction,velocity,requested_dt,geometric=True):
    """Return new fractions and accepted dt; CFL caps physical elapsed time."""
    if not math.isfinite(requested_dt) or requested_dt<=0:
        raise ValueError('Positive finite timestep required')
    if len(fraction)!=len(grid.active) or any(not math.isfinite(c) or c< -1e-9 or c>1+1e-9 for c in fraction):
        raise ValueError('Invalid phase fraction')
    divergence=grid.divergence(velocity)
    if max(map(abs,divergence),default=0)>1e-8:
        raise ValueError('Geometric transport requires a divergence-free mixture velocity')
    outflow=[0.0]*len(fraction)
    for u,(i,j,_,_) in zip(velocity,grid.faces):
        outflow[i if u>=0 else j]+=abs(u)/grid.h
    maximum=max(outflow,default=0)
    dt=min(requested_dt,0.45/maximum) if maximum>0 else requested_dt
    polygons=reconstruct_polygons(grid,fraction) if geometric else None
    low_flux,correction=[],[]
    for u,(i,j,_,axis) in zip(velocity,grid.faces):
        donor=i if u>=0 else j
        width=abs(u)*dt/grid.h
        sign=1 if u>=0 else -1
        low=sign*width*fraction[donor]
        high=low
        if geometric and width>0:
            # Outgoing strip at the donor's positive/negative cell face.
            normal=(1.0,0.0) if axis==0 else (0.0,1.0)
            offset=1-width
            if sign<0:
                normal=tuple(-v for v in normal)
                offset=-width
            high=sign*polygon_area(clip_polygon(polygons[donor],normal,offset))
        low_flux.append(low)
        correction.append(high-low)
    provisional=list(fraction)
    positive=[0.0]*len(fraction)
    negative=[0.0]*len(fraction)
    for low,a,(i,j,_,_) in zip(low_flux,correction,grid.faces):
        provisional[i]-=low
        provisional[j]+=low
        positive[j if a>=0 else i]+=abs(a)
        negative[i if a>=0 else j]+=abs(a)
    r_positive=[min(1,max(0,1-c)/p) if p>0 else 1 for c,p in zip(provisional,positive)]
    r_negative=[min(1,max(0,c)/p) if p>0 else 1 for c,p in zip(provisional,negative)]
    for a,(i,j,_,_) in zip(correction,grid.faces):
        limiter=min(r_negative[i],r_positive[j]) if a>=0 else min(r_positive[i],r_negative[j])
        accepted=a*limiter*(1-1e-12)
        provisional[i]-=accepted
        provisional[j]+=accepted
    if min(provisional)<-1e-9 or max(provisional)>1+1e-9:
        raise RuntimeError('Conservative flux limiter failed bounds')
    return provisional,dt
