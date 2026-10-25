#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32ui, set = 0, binding = 0) readonly uniform uimage2D cells;
layout(r32ui, set = 0, binding = 1) writeonly uniform uimage2D next_cells;
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

int gas_neighbors(ivec2 q, ivec2 excluded) {
 int result=0;
 for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
  if(x==0 && y==0)continue;
  ivec2 a=q+ivec2(x,y);
  if(a==excluded || any(lessThan(a,ivec2(0))) || any(greaterThanEqual(a,ivec2(p.side))))continue;
  if(imageLoad(cells,a).r==5u)result++;
 }
 return result;
}
bool supported(ivec2 q) {
    ivec2 down=abs(p.gx)>abs(p.gy)?ivec2(sign(p.gx),0):ivec2(0,sign(p.gy));
    ivec2 a=q+down;
    if(any(lessThan(a,ivec2(0)))||any(greaterThanEqual(a,ivec2(p.side))))return true;
    return imageLoad(cells,a).r!=0u;
}
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
        if (value[a] == 0u || value[a] == 4u) continue;
        bool resting=value[a]!=5u && supported(base+offsets[a]);
        for (int b = 0; b < 4; ++b) {
            if (value[b] != 0u) continue;
            ivec2 d = offsets[b] - offsets[a];
            int projection = d.x * p.gx + d.y * p.gy;
            if(value[a]==5u){
                projection=-projection;
                // Phenomenological cohesive gas: prefer preserving local gas bonds.
                int before=gas_neighbors(base+offsets[a],base+offsets[b]);
                int after=gas_neighbors(base+offsets[b],base+offsets[a]);
                projection+=14000*(after-before);
            }
            // Reject near-horizontal creep: a coarse repose-inspired threshold.
            int length1 = abs(d.x) + abs(d.y);
            if(value[a]!=5u && !resting){
                // Free settling uses cardinal drift weighted by gravity components.
                // Diagonal avalanche choices require actual local support.
                if(length1!=1 || projection<=0)continue;
            }else if (projection <= 6000 * length1) continue;
            uint weight = uint(projection);
            total += weight;
            rng = hash32(rng + 0x9e3779b9u);
            if (rng % total < weight) { source = a; target = b; }
        }
    }
    if (source >= 0) {
        rng = hash32(rng + 0x9e3779b9u);
        // Effective drag differs by mineral; not a liquid pressure solver.
        if ((rng & 255u) < (value[source]==5u ? 100u : mobility[value[source]]/3u)) {
            value[target] = value[source];
            value[source] = 0u;
        }
    }
    for (int i = 0; i < 4; ++i) {
        if (valid[i]) imageStore(next_cells, base + offsets[i], uvec4(value[i], 0u, 0u, 0u));
    }
}
