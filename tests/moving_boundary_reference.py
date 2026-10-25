"""Prescribed tangential wall motion; fixed occupancy, not translating grains."""
import json
from pathlib import Path
from phase_momentum_reference import advance, equilibrium
from grain_traction_reference import traction


def fixture(speed=.01, steps=40):
    n=16
    m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
    # All nodes of the upper boundary move tangentially, including corner links.
    wall_velocity=[(speed,0.) if i//n==0 else (0.,0.) for i in range(n*n)]
    c=[0.]*(n*n)
    f=equilibrium(n)
    first=traction(f,m,n,True,wall_velocity)
    for _ in range(steps):
        f,v=advance(f,c,m,n,gravity=(0.,0.),sigma=0.,wall_velocity=wall_velocity)
    return dict(side=n,steps=steps,materials=m,speed=speed,
                wall_velocity=[v for pair in wall_velocity for v in pair],
                initial=equilibrium(n),expected=f,
                expected_velocity=[v for pair in v for v in pair],
                first_impulse=[v for pair in first for v in pair])


if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    (root/'reports/moving-boundary-fixture.json').write_text(
        json.dumps([fixture(speed) for speed in (0.,.01,-.01)]),encoding='utf-8')
