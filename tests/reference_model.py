"""Executable specification for M1; never used as an application fallback."""
import math
import struct

MASK = 0xFFFFFFFF
OFFSETS = ((0, 0), (1, 0), (0, 1), (1, 1))
MOBILITY = (0, 210, 155, 105)


def hash32(value):
    value &= MASK
    value ^= (value << 13) & MASK
    value ^= value >> 17
    value ^= (value << 5) & MASK
    return value & MASK


def gravity(angle):
    radians = math.radians(angle)
    return round(math.sin(radians) * 32767), round(math.cos(radians) * 32767)


def initial_state(side, seed):
    cells = []
    radius = side - 8
    for y in range(side):
        for x in range(side):
            dx, dy = 2*x + 1-side, 2*y + 1-side
            h = hash32((y*side+x) ^ seed)
            value = 0
            if dx*dx + dy*dy > radius*radius:
                value = 4
            elif side*0.17 < y < side*0.46 and h % 100 < 88:
                value = 1 + (y//5 + int(h % 3 == 0)) % 3
            cells.append(value)
    return cells


def blocks(side, phase):
    for by in range(side//2+1):
        for bx in range(side//2+1):
            base_x, base_y = bx*2-phase, by*2-phase
            if base_x >= side or base_y >= side:
                continue
            indices = []
            for ox, oy in OFFSETS:
                x, y = base_x+ox, base_y+oy
                indices.append(y*side+x if 0 <= x < side and 0 <= y < side else None)
            yield bx, by, indices


def step(cells, side, seed, tick, g, reverse_blocks=False):
    for phase in range(2):
        work = list(blocks(side, phase))
        if reverse_blocks:
            work.reverse()
        for bx, by, indices in work:
            value = [cells[i] if i is not None else 4 for i in indices]
            rng = hash32(seed ^ ((tick*747796405) & MASK)
                         ^ ((phase*2891336453) & MASK)
                         ^ ((bx*277803737) & MASK) ^ ((by*1597334677) & MASK))
            total, source, target = 0, -1, -1
            for a in range(4):
                if not 1 <= value[a] <= 3:
                    continue
                for b in range(4):
                    if value[b] != 0:
                        continue
                    dx = OFFSETS[b][0]-OFFSETS[a][0]
                    dy = OFFSETS[b][1]-OFFSETS[a][1]
                    projection = dx*g[0]+dy*g[1]
                    if projection <= 6000*(abs(dx)+abs(dy)):
                        continue
                    total += projection
                    rng = hash32(rng+0x9E3779B9)
                    if rng % total < projection:
                        source, target = a, b
            if source >= 0:
                rng = hash32(rng+0x9E3779B9)
                if rng & 255 < MOBILITY[value[source]]:
                    value[target], value[source] = value[source], 0
            for index, material in zip(indices, value):
                if index is not None:
                    cells[index] = material
    return cells


def serialize(cells):
    return struct.pack(f"<{len(cells)}I", *cells)


def center(cells, side):
    occupied = [i for i, v in enumerate(cells) if 1 <= v <= 3]
    return (sum(i % side for i in occupied)/len(occupied),
            sum(i // side for i in occupied)/len(occupied))


def centered_cloud(side, material=None):
    cells = initial_state(side, 1)
    cells = [4 if v == 4 else 0 for v in cells]
    for y in range(side//2-4, side//2+4):
        for x in range(side//2-4, side//2+4):
            cells[y*side+x] = material or 1+(x+y) % 3
    return cells
