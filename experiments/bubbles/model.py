"""E2 candidate: overdamped disks and area-preserving deformable gas inclusions.

Dimensionless, uncalibrated mesoscopic mechanics. Implicit liquid supplies
buoyancy and drag. It does NOT solve liquid incompressibility or film drainage.
Bubble shape is an ellipse; topology changes are deliberately unsupported.
"""
from dataclasses import dataclass
import math


@dataclass
class Grain:
    x: float
    y: float
    radius: float
    material: int
    density: float = 2.65


@dataclass
class Bubble:
    x: float
    y: float
    radius: float
    log_aspect: float = 0.0

    @property
    def axes(self):
        return self.radius*math.exp(self.log_aspect), self.radius*math.exp(-self.log_aspect)

    @property
    def area(self):
        return math.pi*self.radius**2

    def perimeter(self, shape=None):
        s = self.log_aspect if shape is None else shape
        a, b = self.radius*math.exp(s), self.radius*math.exp(-s)
        # Ramanujan approximation; constant area is exact independently of it.
        h = ((a-b)/(a+b))**2
        return math.pi*(a+b)*(1+3*h/(10+math.sqrt(4-3*h)))

    def perimeter_derivative(self):
        a, b = self.axes
        u = (a-b)/(a+b)
        h = u*u
        root = math.sqrt(4-3*h)
        denominator = 10+root
        f = 1+3*h/denominator
        derivative = 3/denominator+4.5*h/(root*denominator**2)
        return math.pi*((a-b)*f+(a+b)*derivative*2*u*(1-u*u))


class BubbleCell:
    def __init__(self, grains=(), bubbles=(), width=1.0, height=1.0,
                 gravity=(0.0, 1.0), tension=0.015, contact_stiffness=1.0,
                 grain_drag=0.04, bubble_drag=0.8, shape_mobility=0.3):
        self.grains = list(grains)
        self.bubbles = list(bubbles)
        self.width, self.height = width, height
        self.gravity = gravity
        self.tension, self.contact_stiffness = tension, contact_stiffness
        self.grain_drag, self.bubble_drag = grain_drag, bubble_drag
        self.shape_mobility = shape_mobility
        self.time = 0.0
        self.substeps = 0
        self._validate()

    def _validate(self):
        if min(self.width, self.height, self.grain_drag, self.bubble_drag) <= 0:
            raise ValueError('Positive dimensions and drag required')
        if self.tension < 0 or self.contact_stiffness <= 0 or self.shape_mobility < 0:
            raise ValueError('Invalid mechanical parameters')
        for grain in self.grains:
            if grain.radius <= 0 or grain.density <= 0:
                raise ValueError('Invalid grain')
            if not grain.radius <= grain.x <= self.width-grain.radius or not grain.radius <= grain.y <= self.height-grain.radius:
                raise ValueError('Grain outside container')
        for bubble in self.bubbles:
            a, b = bubble.axes
            if bubble.radius <= 0 or not a <= bubble.x <= self.width-a or not b <= bubble.y <= self.height-b:
                raise ValueError('Bubble outside container')

    @staticmethod
    def ellipse_contact(dx, dy, a, b, stiffness):
        """Gradient of 0.5*k*max(0,1-q)^2, q=elliptic radial coordinate."""
        q = math.hypot(dx/a, dy/b)
        if q >= 1:
            return 0.0, 0.0, 0.0
        if q < 1e-12:
            # Deterministic resolution of a coincident-center singularity.
            return stiffness/a, 0.0, 1.0
        scale = stiffness*(1-q)/q
        return scale*dx/(a*a), scale*dy/(b*b), 1-q

    def forces(self):
        gx, gy = self.gravity
        gf = [[(grain.density-1)*math.pi*grain.radius**2*gx,
               (grain.density-1)*math.pi*grain.radius**2*gy] for grain in self.grains]
        bf = [[-bubble.area*gx, -bubble.area*gy] for bubble in self.bubbles]
        sf = []
        for bubble in self.bubbles:
            sf.append(-self.tension*bubble.perimeter_derivative())
        maximum_penetration = 0.0
        for i, grain in enumerate(self.grains):
            for j in range(i):
                other = self.grains[j]
                dx, dy = grain.x-other.x, grain.y-other.y
                distance = math.hypot(dx, dy)
                overlap = grain.radius+other.radius-distance
                if overlap > 0:
                    maximum_penetration = max(maximum_penetration, overlap)
                    nx, ny = (dx/distance, dy/distance) if distance > 1e-12 else (1.0, 0.0)
                    force = self.contact_stiffness*overlap
                    gf[i][0] += force*nx
                    gf[i][1] += force*ny
                    gf[j][0] -= force*nx
                    gf[j][1] -= force*ny
            for j, bubble in enumerate(self.bubbles):
                a, b = bubble.axes
                dx, dy = grain.x-bubble.x, grain.y-bubble.y
                # Inflated ellipse is a smooth exclusion approximation, not exact
                # Minkowski distance for finite grains. Report this limitation.
                ax, by = a+grain.radius, b+grain.radius
                fx, fy, penetration = self.ellipse_contact(dx, dy, ax, by, self.contact_stiffness*grain.radius)
                gf[i][0] += fx
                gf[i][1] += fy
                bf[j][0] -= fx
                bf[j][1] -= fy
                if penetration > 0:
                    q = math.hypot(dx/ax, dy/by)
                    if q > 1e-12:
                        dq_ds = (-dx*dx*a/ax**3 + dy*dy*b/by**3)/q
                        sf[j] += self.contact_stiffness*grain.radius*penetration*dq_ds
                    maximum_penetration = max(maximum_penetration, penetration*min(ax, by))
        for i, bubble in enumerate(self.bubbles):
            for j in range(i):
                other = self.bubbles[j]
                a, b = bubble.axes
                c, d = other.axes
                dx, dy = bubble.x-other.x, bubble.y-other.y
                fx, fy, penetration = self.ellipse_contact(dx, dy, a+c, b+d, self.contact_stiffness*0.1)
                bf[i][0] += fx
                bf[i][1] += fy
                bf[j][0] -= fx
                bf[j][1] -= fy
                if penetration:
                    q = math.hypot(dx/(a+c), dy/(b+d))
                    if q > 1e-12:
                        scale = self.contact_stiffness*0.1*penetration/q
                        sf[i] += scale*(-dx*dx*a/(a+c)**3+dy*dy*b/(b+d)**3)
                        sf[j] += scale*(-dx*dx*c/(a+c)**3+dy*dy*d/(b+d)**3)
        return gf, bf, sf, maximum_penetration

    def step(self, dt, fixed_bubbles=False):
        if not math.isfinite(dt) or dt < 0:
            raise ValueError('Nonnegative finite dt required')
        remaining = dt
        steps = 0
        while remaining > 1e-12:
            gf, bf, sf, _ = self.forces()
            maximum_speed = max([math.hypot(*f)/self.grain_drag for f in gf]
                                + [math.hypot(*f)/self.bubble_drag for f in bf] + [1e-12])
            scale = min([g.radius for g in self.grains]+[b.radius for b in self.bubbles]+[0.01])
            # Contact penalty stiffness sets a numerical relaxation time too.
            h = min(remaining, 0.002/max(1.0, self.contact_stiffness), 0.1*scale/maximum_speed)
            for grain, force in zip(self.grains, gf):
                grain.x = min(self.width-grain.radius, max(grain.radius, grain.x+h*force[0]/self.grain_drag))
                grain.y = min(self.height-grain.radius, max(grain.radius, grain.y+h*force[1]/self.grain_drag))
            if not fixed_bubbles:
                for bubble, force, shape_force in zip(self.bubbles, bf, sf):
                    proposed = bubble.log_aspect+h*self.shape_mobility*shape_force
                    # Geometric cap is documented; never silently lose gas area.
                    limit = min(math.log(2.5), math.log(min(self.width, self.height)/(2*bubble.radius)))
                    bubble.log_aspect = max(-limit, min(limit, proposed))
                    a, b = bubble.axes
                    bubble.x = min(self.width-a, max(a, bubble.x+h*force[0]/self.bubble_drag))
                    bubble.y = min(self.height-b, max(b, bubble.y+h*force[1]/self.bubble_drag))
            remaining -= h
            steps += 1
            if steps > 10000:
                raise RuntimeError('Substep budget exceeded')
        self.time += dt
        self.substeps += steps

    def gas_area(self):
        return sum(math.pi*a*b for a, b in (bubble.axes for bubble in self.bubbles))

    def inventory(self):
        return [grain.material for grain in self.grains]
