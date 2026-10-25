"""E1: dilute rigid spheres in a prescribed uniform liquid, all units SI.

This is a validation solver, not the product's liquid/granular coupling.
No added mass, history force, wall corrections, or interparticle interactions.
"""
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class Mineral:
    diameter_m: float
    density_kg_m3: float
    identity: int

    def __post_init__(self):
        if not math.isfinite(self.diameter_m) or self.diameter_m <= 0:
            raise ValueError('Diameter must be positive and finite')
        if not math.isfinite(self.density_kg_m3) or self.density_kg_m3 <= 0:
            raise ValueError('Density must be positive and finite')


@dataclass(frozen=True)
class Grain:
    x: float
    y: float
    vx: float
    vy: float
    mineral: Mineral


def advance(grain, dt, gravity=(0.0, 9.81), liquid_velocity=(0.0, 0.0),
            liquid_density=1000.0, viscosity=0.001):
    if not math.isfinite(dt) or dt < 0:
        raise ValueError('dt must be nonnegative and finite')
    if not math.isfinite(viscosity) or viscosity <= 0:
        raise ValueError('Viscosity must be positive and finite')
    if not math.isfinite(liquid_density) or liquid_density <= 0:
        raise ValueError('Liquid density must be positive and finite')
    if dt == 0:
        return grain
    mineral = grain.mineral
    tau = mineral.density_kg_m3*mineral.diameter_m**2/(18.0*viscosity)
    decay = math.exp(-dt/tau)
    integral = -tau*math.expm1(-dt/tau)
    terminal = tuple(u + g*tau*(1.0-liquid_density/mineral.density_kg_m3)
                     for u, g in zip(liquid_velocity, gravity))
    position = tuple(p + vt*dt + (v-vt)*integral
                     for p, v, vt in zip((grain.x, grain.y), (grain.vx, grain.vy), terminal))
    velocity = tuple(vt + (v-vt)*decay for v, vt in zip((grain.vx, grain.vy), terminal))
    return Grain(*position, *velocity, mineral)


def reynolds(grain, liquid_velocity=(0.0, 0.0), liquid_density=1000.0, viscosity=0.001):
    relative_speed = math.hypot(grain.vx-liquid_velocity[0], grain.vy-liquid_velocity[1])
    return liquid_density*relative_speed*grain.mineral.diameter_m/viscosity
