shader_type canvas_item;
render_mode unshaded;
uniform float angle = 0.0;

void fragment() {
    vec2 p = UV - vec2(0.5);
    float r = length(p);
    float aa = max(fwidth(r), 0.001);
    float c = cos(angle);
    float s = sin(angle);
    vec2 local_uv = vec2(c*p.x+s*p.y, -s*p.x+c*p.y) + vec2(0.5);
    vec4 sand = texture(TEXTURE, local_uv);
    vec3 liquid = vec3(0.73, 0.75, 0.74);
    vec3 content = mix(liquid, sand.rgb, sand.a);
    content *= 1.0 - 0.12 * smoothstep(0.30, 0.48, r);
    content += vec3(0.025) * pow(max(0.0, 1.0-length(p-vec2(-0.18,-0.22))*2.0), 6.0);
    float inside = 1.0-smoothstep(0.480-aa, 0.480+aa, r);
    vec3 rim = vec3(0.075) + vec3(0.07)*smoothstep(-0.5,0.5,-p.y);
    COLOR = vec4(mix(rim, content, inside), 1.0-smoothstep(0.495-aa,0.495+aa,r));
}
