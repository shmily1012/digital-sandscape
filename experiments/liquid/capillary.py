"""Balanced face capillary forcing and local height-function curvature.

Pure two-phase, planar curvature only. No transverse-gap curvature, contact
angle, or three-phase contact-line model is supplied by this experiment.
"""
import math

# Classification tolerance only; heights integrate the original conserved values.
PURE_PHASE_EPSILON = 1e-6

def same_pure_phase(a, b):
    return max(a,b)<=PURE_PHASE_EPSILON or min(a,b)>=1-PURE_PHASE_EPSILON


def circle_fractions(size, radius=0.2, center=(0.5,0.5)):
    """Exact circle/rectangle area integrals; analytic geometry is test-only."""
    h=1/size
    cx,cy=center
    def primitive(t):
        t=max(-radius,min(radius,t))
        return 0.5*(t*math.sqrt(max(0.0,radius*radius-t*t))+radius*radius*math.asin(t/radius))
    values=[]
    for y in range(size):
        for x in range(size):
            area=0.0
            start,end=max(x*h-cx,-radius),min((x+1)*h-cx,radius)
            bottom,top=y*h-cy,(y+1)*h-cy
            cuts=[start,end]
            if start<end:
                for bound in (bottom,top):
                    if abs(bound)<radius:
                        root=math.sqrt(radius*radius-bound*bound)
                        cuts.extend(t for t in (-root,root) if start<t<end)
                cuts=sorted(set(cuts))
                for a,b in zip(cuts,cuts[1:]):
                    half=math.sqrt(max(0.0,radius*radius-((a+b)/2)**2))
                    if min(top,half)<=max(bottom,-half):
                        continue
                    upper_constant,upper_root=(0,1) if half<top else (top,0)
                    lower_constant,lower_root=(0,-1) if -half>bottom else (bottom,0)
                    area+=(upper_constant-lower_constant)*(b-a)+(upper_root-lower_root)*(primitive(b)-primitive(a))
            values.append(min(1.0,max(0.0,area/(h*h))))
    return values


def height_curvature(size, fraction):
    """Return curvature or None where a resolved single interface is absent.

    Three columns with an eleven-cell integration strip. All columns must
    terminate in opposite pure phases; unsupported geometry is reported.
    """
    h=1/size
    def sample(x,y):
        return fraction[y*size+x] if 0<=x<size and 0<=y<size else None
    result=[None]*(size*size)
    for y in range(1,size-1):
        for x in range(1,size-1):
            if not 1e-10 < fraction[y*size+x] < 1-1e-10:
                continue
            gx=sample(x+1,y)-sample(x-1,y)
            gy=sample(x,y+1)-sample(x,y-1)
            if abs(gx)+abs(gy)<1e-12:
                continue
            axes=(1,0) if abs(gy)>=abs(gx) else (0,1)
            for axis in axes:
                heights=[]
                for column in (-1,0,1):
                    strip=[sample(x+column if axis else x+offset,
                                  y+offset if axis else y+column) for offset in range(-5,6)]
                    if any(v is None for v in strip):
                        break
                    if not ((strip[0]<=PURE_PHASE_EPSILON and strip[-1]>=1-PURE_PHASE_EPSILON) or
                            (strip[-1]<=PURE_PHASE_EPSILON and strip[0]>=1-PURE_PHASE_EPSILON)):
                        break
                    # Reject multiple crossings or a nonmonotone gas strip.
                    direction=1 if strip[-1]>strip[0] else -1
                    if any(direction*(b-a)<-1e-8 and not same_pure_phase(a,b) for a,b in zip(strip,strip[1:])):
                        break
                    heights.append(sum(strip)*h)
                if len(heights)==3:
                    left,middle,right=heights
                    first=(right-left)/(2*h)
                    second=(right-2*middle+left)/(h*h)
                    result[y*size+x]=-second/(1+first*first)**1.5
                    break
    return result


def extend_curvature(size, fraction, height):
    """Single nonrecursive extension from nearby resolved heights, never from fills.

    Require two donors in the nearest populated radius (at most two cells),
    and reject incompatible curvature signs/magnitudes. No fraction is changed.
    """
    result=list(height)
    for i,c in enumerate(fraction):
        if height[i] is not None or not 1e-10<c<1-1e-10:
            continue
        x,y=i%size,i//size
        for radius in (1,2):
            values=[]
            for dy in range(-radius,radius+1):
                for dx in range(-radius,radius+1):
                    if max(abs(dx),abs(dy))!=radius or not (0<=x+dx<size and 0<=y+dy<size):continue
                    value=height[(y+dy)*size+x+dx]
                    if value is not None:values.append(value)
            if len(values)<2:continue
            mean=sum(values)/len(values)
            if max(values)-min(values)<=max(0.5,0.25*abs(mean)):
                result[i]=mean
            break
    return result


def capillary_flux(grid, fraction, curvature, tension, reference_curvature=0.0):
    if len(fraction)!=len(grid.active) or len(curvature)!=len(fraction):
        raise ValueError('Capillary field shape mismatch')
    if not math.isfinite(tension) or tension<0:
        raise ValueError('Nonnegative finite tension required')
    flux=[]
    for i,j,m,_ in grid.faces:
        delta=fraction[j]-fraction[i]
        if abs(delta)<1e-14 or tension==0:
            flux.append(0.0)
            continue
        available=[curvature[k] for k in (i,j) if curvature[k] is not None]
        if not available and same_pure_phase(fraction[i],fraction[j]):
            # Projection roundoff inside the same pure phase is not an interface.
            # Ignore its force only; never modify conserved phase fractions.
            flux.append(0.0)
            continue
        if not available or any(not math.isfinite(v) for v in available):
            raise ValueError(f'Unresolved capillary interface at face {i},{j}')
        kappa=sum(available)/len(available)-reference_curvature
        # Same face mobility and gradient as pressure: constant kappa balances.
        flux.append(m*tension*kappa*delta/grid.h)
    return flux


def split_capillary_pressure(grid, fraction, curvature, tension):
    """Move an exactly integrable gradient into base pressure, not out of physics.

    p = sigma*k_ref*c + p_residual; k_ref can be ANY constant. Choosing the
    mean resolved curvature reduces float32 cancellation near equilibrium.
    """
    resolved=[v for v in curvature if v is not None]
    reference=sum(resolved)/len(resolved) if resolved else 0.0
    base=[tension*reference*c for c in fraction]
    residual=capillary_flux(grid,fraction,curvature,tension,reference)
    return base,residual
