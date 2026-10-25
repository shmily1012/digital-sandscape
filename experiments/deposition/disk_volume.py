"""Analytic disk occupancy and conservative finite-step geometric flux.

The symmetric coordinate paths are a transport construction, not an assumed
physical trajectory or a liquid constitutive law. No raster renormalization.
"""
import math
from dataclasses import replace


def disk_rectangle_area(cx,cy,r,x0,y0,x1,y1):
    left=max(-r,x0-cx);right=min(r,x1-cx)
    bottom=y0-cy;top=y1-cy
    if left>=right or top<=-r or bottom>=r:return 0.
    cuts=[left,right]
    for y in (bottom,top):
        if abs(y)<r:
            x=math.sqrt(max(0.,r*r-y*y))
            cuts.extend(a for a in (-x,x) if left<a<right)
    cuts=sorted(set(cuts))
    def primitive(x):
        root=math.sqrt(max(0.,(r-x)*(r+x)))
        return .5*(x*root+r*r*math.atan2(x,root))
    area=0.
    for a,b in zip(cuts,cuts[1:]):
        root=math.sqrt(max(0.,r*r-((a+b)/2)**2))
        if min(top,root)<=max(bottom,-root):continue
        upper_circle=top>root;lower_circle=bottom< -root
        area+=(int(upper_circle)+int(lower_circle))*(primitive(b)-primitive(a))
        area+=((0. if upper_circle else top)-(0. if lower_circle else bottom))*(b-a)
    # The analytic integral is nonnegative; roundoff at tangent caps can be
    # a few ulps below zero. This is not a global area renormalization.
    return max(0.,area)


def occupancy(grid,grains):
    result=[0.]*len(grid.active)
    for k,g in enumerate(grains):
        if not all(math.isfinite(v) for v in (g.x,g.y,g.radius)) or g.radius<=0:
            raise ValueError('Invalid disk')
        if min(g.x-g.radius,g.y-g.radius)<0 or max(g.x+g.radius,g.y+g.radius)>1:
            raise ValueError('Disk leaves domain')
        for other in grains[:k]:
            if math.hypot(g.x-other.x,g.y-other.y)<g.radius+other.radius-1e-12:
                raise ValueError('Overlapping disks')
        for y in range(max(0,int((g.y-g.radius)/grid.h)),min(grid.size,int((g.y+g.radius)/grid.h)+1)):
            for x in range(max(0,int((g.x-g.radius)/grid.h)),min(grid.size,int((g.x+g.radius)/grid.h)+1)):
                value=disk_rectangle_area(g.x,g.y,g.radius,x*grid.h,y*grid.h,(x+1)*grid.h,(y+1)*grid.h)/grid.h**2
                i=y*grid.size+x
                if value>1e-12 and not grid.active[i]:raise ValueError('Disk crosses sealed cell boundary')
                result[i]+=value
    if min(result)<-1e-12 or max(result)>1+1e-12:raise ValueError('Invalid solid fraction')
    return result


def face_apertures(grid,grain):
    """Exact fraction of each face cut by the disk; Bv is solid volume flux."""
    occupancy(grid,[grain])
    out=[]
    for i,j,_,axis in grid.faces:
        if axis==0:
            normal=(i%grid.size+1)*grid.h-grain.x
            low=(i//grid.size)*grid.h-grain.y
        else:
            normal=(i//grid.size+1)*grid.h-grain.y
            low=(i%grid.size)*grid.h-grain.x
        half=math.sqrt(max(0.,grain.radius**2-normal**2)) if abs(normal)<grain.radius else 0.
        out.append(max(0.,min(low+grid.h,half)-max(low,-half))/grid.h)
    return out


def swept_flux(grid,before,after,dt):
    """Time-averaged solid flux satisfying endpoint occupancy continuity.

Average x-then-y and y-then-x paths. Intermediate disks must also remain
inside the sealed cell mask. Contacts during the constructed paths are not
modeled; this function does not advance or approve particle positions.
"""
    if not math.isfinite(dt) or dt<=0 or len(before)!=len(after):raise ValueError('Invalid step')
    old=occupancy(grid,before);new=occupancy(grid,after)
    flux=[0.]*len(grid.faces)
    lookup={(i,j):f for f,(i,j,_,_) in enumerate(grid.faces)}
    n=grid.size
    def segment(a,b,axis):
        start=occupancy(grid,[a]);end=occupancy(grid,[b])
        for line in range(n):
            cumulative=0.
            for k in range(n):
                i=line*n+k if axis==0 else k*n+line
                cumulative+=(start[i]-end[i])*grid.h/dt
                if k==n-1:
                    if abs(cumulative)>1e-9:raise ValueError('Nonconservative coordinate path')
                else:
                    j=i+(1 if axis==0 else n)
                    f=lookup.get((i,j))
                    if f is not None:flux[f]+=.5*cumulative
                    elif abs(cumulative)>1e-9:raise ValueError('Path crosses sealed face')
    for a,b in zip(before,after):
        if (a.radius,a.material)!=(b.radius,b.material):raise ValueError('Identity or area changed')
        xy=replace(a,x=b.x);yx=replace(a,y=b.y)
        segment(a,xy,0);segment(xy,b,1)
        segment(a,yx,1);segment(yx,b,0)
    residual=max(abs(b-a+dt*d) for a,b,d in zip(old,new,grid.divergence(flux)))
    if residual>1e-10:raise ValueError('Endpoint volume balance failed')
    return flux
