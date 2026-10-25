"""Transactional particle and tangential history candidate, fixed-step CPU model."""
from dataclasses import dataclass
import math
from experiments.deposition.contact_particles import advance_contacts
from experiments.deposition.tangential_history import update_tangent,snapshot

@dataclass
class HistoryContactResult:
    contact: object
    history: dict
    elastic_energy: float
    dissipated: float
    work_into_springs: float
    constitutive_error: float


def advance_history_contacts(grains,ids,history,gravity,dt,planes=(),plane_ids=(),
                             stiffness=1.,friction=.5,mobility_matrix=None,
                             max_iterations=2000,relaxation=1.,external_forces=None):
    if len(ids)!=len(grains) or len(set(ids))!=len(ids) or any(type(i) is not int or i<0 for i in ids):
        raise ValueError('Unique nonnegative particle IDs required')
    if len(plane_ids)!=len(planes) or len(set(plane_ids))!=len(plane_ids) or any(type(i) is not int or i>=0 for i in plane_ids):
        raise ValueError('Unique negative wall IDs required')
    snapshot(history)
    if not math.isfinite(stiffness) or stiffness<=0 or any(s.stiffness!=stiffness for s in history.values()):
        raise ValueError('Invalid or changed stiffness')
    keys=[];springs=[];old_states=[]
    for i,g in enumerate(grains):
        pairs=[(tuple(sorted((ids[i],ids[j]))),math.hypot(g.x-grains[j].x,g.y-grains[j].y)-g.radius-grains[j].radius) for j in range(i)]
        pairs += [((pid,ids[i]),p.nx*g.x+p.ny*g.y-p.offset-g.radius) for pid,p in zip(plane_ids,planes)]
        for key,gap in pairs:
            old=history.get(key) if gap<=1e-10 else None
            keys.append(key);old_states.append(old);springs.append((old.elastic_slip if old else 0.,stiffness))
    result=advance_contacts(grains,gravity,dt,planes,friction,max_iterations=max_iterations,tolerance=1e-12,
                            relaxation=relaxation,mobility_matrix=mobility_matrix,tangential_compliance=springs,external_forces=external_forces)
    updated={};energy=dissipated=work=error=0.;used=set()
    for key,old,c in zip(keys,old_states,result.reactions):
        i,j,nx,ny,gap,ln,lt=c
        vx,vy=result.velocity[i]
        if j>=0:vx-=result.velocity[j][0];vy-=result.velocity[j][1]
        tangent=-ny*vx+nx*vy
        response=update_tangent(old,dt*tangent,ln,stiffness,friction)
        error=max(error,abs(response.force-lt))
        dissipated+=response.plastic_dissipation+response.implicit_dissipation;work+=response.work_into_contact
        if old is not None:used.add(key)
        a=result.grains[i]
        if j>=0:
            b=result.grains[j];end_gap=math.hypot(a.x-b.x,a.y-b.y)-a.radius-b.radius
        else:
            p=planes[plane_ids.index(key[0])];end_gap=p.nx*a.x+p.ny*a.y-p.offset-a.radius
        if end_gap<=1e-10:
            updated[key]=response.state;energy+=response.elastic_energy
        else:dissipated+=response.elastic_energy
    dissipated+=sum(.5*s.stiffness*s.elastic_slip**2 for key,s in history.items() if key not in used)
    if error>1e-9:raise ValueError('Spring constitutive residual failed; original state retained')
    return HistoryContactResult(result,updated,energy,dissipated,work,error)
