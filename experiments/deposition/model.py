"""E3 isolated quasi-static contact-bed experiment, not a circular-world solver.

Finite reservoir + material-labelled columns. Avalanche hysteresis is an explicit
phenomenological assumption to calibrate, not a measured mineral friction law.
"""
import math
import random


class ContactBed:
    def __init__(self, reservoir, columns=101, dx=0.001, grain_area=2e-8,
                 start_angle=35.0, stop_angle=30.0, seed=11):
        if columns < 3 or dx <= 0 or grain_area <= 0:
            raise ValueError('Positive spatial scales and at least three columns required')
        if not 0 < stop_angle < start_angle < 89:
            raise ValueError('Require 0 < stop angle < start angle < 89 degrees')
        self.columns = [[] for _ in range(columns)]
        self.reservoir = list(reservoir)
        self.dx, self.quantum = dx, grain_area/dx
        self.start_slope = math.tan(math.radians(start_angle))
        self.stop_slope = math.tan(math.radians(stop_angle))
        self.base = [0.0]*columns
        self.active = [False]*(columns-1)
        self.rng = random.Random(seed)
        self.transfers = 0

    def heights(self):
        return [base+len(column)*self.quantum for base, column in zip(self.base, self.columns)]

    def inventory(self):
        return self.reservoir + [material for column in self.columns for material in column]

    def release(self, column, count=1):
        if not 0 <= column < len(self.columns) or count < 0:
            raise ValueError('Invalid source or count')
        for _ in range(min(count, len(self.reservoir))):
            self.columns[column].append(self.reservoir.pop())

    def tilt_floor(self, degrees):
        if abs(degrees) >= 80:
            raise ValueError('Height-field experiment cannot represent an overturned floor')
        slope = math.tan(math.radians(degrees))
        self.base = [slope*self.dx*i for i in range(len(self.columns))]

    def potential(self):
        # Integral of height over deposited area; common density*g omitted.
        return sum(self.dx*len(c)*self.quantum*(b+len(c)*self.quantum/2)
                   for b, c in zip(self.base, self.columns))

    def relax(self, max_passes=10000):
        moved_total = 0
        for sweep in range(max_passes):
            edges = list(range(len(self.active)))
            self.rng.shuffle(edges)
            moved = 0
            for edge in edges:
                left, right = edge, edge+1
                h_left = self.base[left]+len(self.columns[left])*self.quantum
                h_right = self.base[right]+len(self.columns[right])*self.quantum
                slope = abs(h_left-h_right)/self.dx
                threshold = self.stop_slope if self.active[edge] else self.start_slope
                if slope <= threshold:
                    self.active[edge] = False
                    continue
                source, target = (left, right) if h_left > h_right else (right, left)
                if not self.columns[source]:
                    self.active[edge] = False
                    continue
                self.active[edge] = True
                self.columns[target].append(self.columns[source].pop())
                moved += 1
            moved_total += moved
            if moved == 0:
                self.transfers += moved_total
                return moved_total
        raise RuntimeError('Relaxation did not converge within bounded passes')
