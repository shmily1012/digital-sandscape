#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32ui, set = 0, binding = 0) uniform uimage2D cells;
layout(push_constant, std430) uniform Parameters {
    uint side;
    uint seed;
    uint tick;
    uint phase;
    int gx;
    int gy;
    uint pad0;
    uint pad1;
} p;

uint hash32(uint x) {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

const ivec2 offsets[4] = ivec2[4](ivec2(0,0), ivec2(1,0), ivec2(0,1), ivec2(1,1));
const uint mobility[4] = uint[4](0u, 210u, 155u, 105u);

void main() {
    ivec2 block = ivec2(gl_GlobalInvocationID.xy);
    ivec2 base = block * 2 - ivec2(int(p.phase));
    if (any(greaterThanEqual(base, ivec2(p.side)))) return;
    uint value[4];
    bool valid[4];
    for (int i = 0; i < 4; ++i) {
        ivec2 q = base + offsets[i];
        valid[i] = all(greaterThanEqual(q, ivec2(0))) && all(lessThan(q, ivec2(p.side)));
        value[i] = 4u;
        if (valid[i]) value[i] = imageLoad(cells, q).r;
    }
    uint rng = hash32(p.seed ^ (p.tick * 747796405u) ^ (p.phase * 2891336453u)
                      ^ (uint(block.x) * 277803737u) ^ (uint(block.y) * 1597334677u));
    // Weighted reservoir over downhill moves. Integer gravity avoids float races/drift.
    uint total = 0u;
    int source = -1;
    int target = -1;
    for (int a = 0; a < 4; ++a) {
        if (value[a] < 1u || value[a] > 3u) continue;
        for (int b = 0; b < 4; ++b) {
            if (value[b] != 0u) continue;
            ivec2 d = offsets[b] - offsets[a];
            int projection = d.x * p.gx + d.y * p.gy;
            // Reject near-horizontal creep: a coarse repose-inspired threshold.
            int length1 = abs(d.x) + abs(d.y);
            if (projection <= 6000 * length1) continue;
            uint weight = uint(projection);
            total += weight;
            rng = hash32(rng + 0x9e3779b9u);
            if (rng % total < weight) { source = a; target = b; }
        }
    }
    if (source >= 0) {
        rng = hash32(rng + 0x9e3779b9u);
        // Effective drag differs by mineral; not a liquid pressure solver.
        if ((rng & 255u) < mobility[value[source]]) {
            value[target] = value[source];
            value[source] = 0u;
        }
    }
    for (int i = 0; i < 4; ++i) {
        if (valid[i]) imageStore(cells, base + offsets[i], uvec4(value[i], 0u, 0u, 0u));
    }
}
