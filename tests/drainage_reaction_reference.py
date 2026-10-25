"""Work-conjugate finite-step pressure reaction, using independent swept paths."""
import math


def reaction(case, pressure=None, dt=1.):
    from grain_volume_reference import geometry
    n=case['side'];m=case['material'];o=case['offset'];v=case['velocity']
    p=case['pressure'] if pressure is None else pressure
    shape=case.get('shape','box')
    result=[[0.,0.] for _ in m]
    for grain,material in enumerate(m):
        if material<2:continue
        isolated=[0]*len(m);isolated[grain]=material
        for axis in range(2):
            if v[grain][axis]!=0:
                flux=geometry(isolated,o,v,n,dt,shape)
                weights=[row[2+axis]/v[grain][axis] for row in flux]
            else:
                epsilon=1e-6;probes=[]
                for sign in (-1,1):
                    probe=[list(u) for u in v];probe[grain][axis]=sign*epsilon
                    probes.append(geometry(isolated,o,probe,n,dt,shape))
                weights=[(b[2+axis]-a[2+axis])/(2*epsilon) for a,b in zip(*probes)]
            for i,weight in enumerate(weights):
                j=i+(1 if axis==0 else n)
                if j>=len(m) or (axis==0 and i%n==n-1):continue
                result[grain][axis]+=(p[i]-p[j])*weight
    return result


def work(case, force):
    return math.fsum(f[k]*v[k] for f,v in zip(force,case['velocity']) for k in range(2))


def dissipation(case):
    return math.fsum(q*q/a for flow,opening in zip(case['fluid_flux'],case['aperture'])
                     for q,a in zip(flow,opening) if a>0)


def feedback(case, dt=.1, iterations=16, tolerance=1e-8, accelerate=False):
    """Bounded same-step oracle, with no state commit or capillary forcing.

    Optional depth-one secant mixing minimizes the last two map residuals.
    It changes the next force guess only; acceptance always recomputes the
    unaccelerated physical residual and the contact residual. In particular,
    acceleration does not cure the grid-aligned cut-cell discontinuity.
    """
    from grain_volume_reference import geometry, apertures, project
    from grain_contact_impulse_reference import MASS, solve_box_contacts
    if not 0 < dt <= 1 or not 1 <= iterations <= 32 or tolerance <= 0:
        raise ValueError('Invalid feedback budget')
    material=case['material']; offset=case['offset']; n=case['side']
    force=[[0.,0.] for _ in material]
    previous_residual=previous_map=None
    for iteration in range(iterations):
        predicted=[[(v[k]+dt*force[i][k]/MASS[m])*dt for k in range(2)]
                   if m>=2 else [0.,0.]
                   for i,(m,v) in enumerate(zip(material,case['velocity']))]
        displacement, contact, contact_error=solve_box_contacts(
            material,predicted,offset,n)
        velocity=[[x/dt for x in v] for v in displacement]
        candidate=dict(case,velocity=velocity)
        candidate['expected']=geometry(material,offset,velocity,n,dt,case.get('shape','box'))
        if any(min(row[:2]) < -1e-10 for row in candidate['expected']):
            return dict(accepted=False,reason='capacity',iterations=iteration+1)
        candidate['aperture']=apertures(material,offset,velocity,n,dt,case.get('shape','box'))
        candidate['fluid_flux'],candidate['pressure']=project(candidate)
        target=reaction(candidate,dt=dt)
        residual=max((dt*abs(target[i][k]-force[i][k])/MASS[m]
                      for i,m in enumerate(material) if m>=2 for k in range(2)),default=0.)
        candidate.update(pressure_reaction=target,force_input=[f[:] for f in force],
                         contact_impulse=[[x/dt for x in f] for f in contact],
                         residual=residual,contact_residual=contact_error/dt,
                         iterations=iteration+1,accepted=False)
        if residual<=tolerance and contact_error/dt<=tolerance:
            candidate['accepted']=True
            return candidate
        mapped=[[(a+b)*.5 for a,b in zip(old,new)] for old,new in zip(force,target)]
        residual_vector=[[b-a for a,b in zip(old,new)] for old,new in zip(force,mapped)]
        if accelerate and previous_residual is not None:
            difference=[[b-a for a,b in zip(old,new)] for old,new in zip(previous_residual,residual_vector)]
            denominator=math.fsum(x*x for row in difference for x in row)
            if denominator>1e-30:
                coefficient=math.fsum(a*b for row_a,row_b in zip(residual_vector,difference)
                                      for a,b in zip(row_a,row_b))/denominator
                force=[[b-coefficient*(b-a) for a,b in zip(old,new)]
                       for old,new in zip(previous_map,mapped)]
            else:
                force=mapped
        else:
            force=mapped
        previous_residual=residual_vector
        previous_map=mapped
    candidate['reason']='feedback budget exhausted'
    return candidate
