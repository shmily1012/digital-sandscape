"""Two-dimensional tangential spring/slider history experiment.

The caller supplies signed contact-point slip in a continuously transported,
canonically oriented tangent frame, including rotational slip if modeled.
Normal force is prescribed here; no claim of a global coupled contact solve.
Equations are independently implemented from the documented spring/slider law.
"""
from dataclasses import dataclass,asdict
import math


@dataclass(frozen=True)
class TangentialState:
    elastic_slip: float
    stiffness: float


@dataclass(frozen=True)
class TangentialUpdate:
    state: TangentialState
    force: float
    elastic_energy: float
    plastic_dissipation: float
    implicit_dissipation: float
    work_into_contact: float


def update_tangent(previous,slip_increment,normal_force,stiffness,friction):
    values=(slip_increment,normal_force,stiffness,friction)
    if any(not math.isfinite(v) for v in values) or normal_force<0 or stiffness<=0 or friction<0:
        raise ValueError('Invalid tangential constitutive input')
    if previous is not None:
        if not math.isfinite(previous.elastic_slip) or previous.stiffness!=stiffness:
            raise ValueError('Invalid history or unaccounted stiffness change')
    old=previous.elastic_slip if previous else 0.
    trial=old+slip_increment;limit=friction*normal_force/stiffness
    elastic=min(limit,max(-limit,trial))
    force=-stiffness*elastic
    plastic=stiffness*elastic*(trial-elastic)
    implicit=.5*stiffness*(elastic-old)**2
    energy=.5*stiffness*elastic**2
    work=-force*slip_increment
    if not all(math.isfinite(v) for v in (elastic,force,plastic,implicit,energy,work)):
        raise ValueError('Tangential update overflow')
    return TangentialUpdate(TangentialState(elastic,stiffness),force,energy,plastic,implicit,work)


def _key(key):
    if not isinstance(key,tuple) or len(key)!=2 or any(type(v) is not int for v in key) or key[0]>=key[1]:
        raise ValueError('Contact key must contain two ordered stable integer IDs')


def advance_histories(previous,samples,stiffness,friction):
    """Pure transaction; samples are (key, slip_increment, normal_force).

Omitted contacts have opened: release their elastic energy and delete history.
Recontact starts a new spring. Stable IDs must survive particle buffer reorder.
"""
    if not math.isfinite(stiffness) or stiffness<=0 or not math.isfinite(friction) or friction<0:
        raise ValueError("Invalid batch constitutive parameters")
    for key,state in previous.items():
        _key(key)
        if not math.isfinite(state.elastic_slip) or state.stiffness!=stiffness:
            raise ValueError('Invalid previous spring state')
    updated={};responses={}
    for key,slip,normal in samples:
        _key(key)
        if key in updated:raise ValueError('Duplicate contact key')
        response=update_tangent(previous.get(key),slip,normal,stiffness,friction)
        updated[key]=response.state;responses[key]=response
    release=sum(.5*s.stiffness*s.elastic_slip**2 for key,s in previous.items() if key not in updated)
    return updated,responses,release


def snapshot(history):
    records=[]
    for key,state in sorted(history.items()):
        _key(key)
        if not math.isfinite(state.elastic_slip) or not math.isfinite(state.stiffness) or state.stiffness<=0:
            raise ValueError('Invalid history snapshot')
        records.append(dict(ids=list(key),**asdict(state)))
    return dict(version=1,contacts=records)


def restore(data):
    if data.get('version')!=1:raise ValueError('Unsupported contact state version')
    result={}
    for record in data['contacts']:
        key=tuple(record['ids']);_key(key)
        if key in result:raise ValueError('Duplicate saved contact')
        result[key]=TangentialState(record['elastic_slip'],record['stiffness'])
    snapshot(result)
    return result
