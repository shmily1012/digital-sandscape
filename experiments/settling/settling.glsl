#[compute]
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
struct Grain {
    vec4 kinematics; // Position (m), velocity (m/s).
    vec4 mineral; // Diameter (m), density (kg/m3), identity, reserved.
    vec4 compensation; // Kahan position summation residual, remaining fields reserved.
};
layout(set = 0, binding = 0, std430) restrict buffer State { Grain grains[]; } state;
layout(push_constant, std430) uniform Parameters {
    vec2 gravity;
    vec2 liquid_velocity;
    float liquid_density;
    float viscosity;
    float dt;
    uint count;
} p;
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= p.count) return;
    Grain grain = state.grains[i];
    float tau = grain.mineral.y * grain.mineral.x * grain.mineral.x / (18.0 * p.viscosity);
    vec2 terminal = p.liquid_velocity + p.gravity * tau * (1.0 - p.liquid_density / grain.mineral.y);
    float t = p.dt / tau;
    // Avoid subtractive cancellation in 1-exp(-t) for very short steps.
    float one_minus_decay = t < 0.001 ? t*(1.0-t*(0.5-t/6.0)) : 1.0-exp(-t);
    vec2 old_velocity = grain.kinematics.zw;
    vec2 displacement = terminal*p.dt + (old_velocity-terminal)*tau*one_minus_decay;
    precise vec2 corrected = displacement - grain.compensation.xy;
    precise vec2 next_position = grain.kinematics.xy + corrected;
    precise vec2 rounding_error = (next_position-grain.kinematics.xy)-corrected;
    grain.compensation.xy = rounding_error;
    grain.kinematics.xy = next_position;
    grain.kinematics.zw = old_velocity + (terminal-old_velocity)*one_minus_decay;
    state.grains[i].kinematics = grain.kinematics;
    state.grains[i].compensation = grain.compensation;
}
