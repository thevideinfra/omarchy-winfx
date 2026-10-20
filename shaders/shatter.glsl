#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Glass break: the window is cut into jagged Voronoi shards that crack, then
// tumble away from the impact point and fall.
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;
uniform vec4 window_rect;
uniform vec2 surface_size;
#define CELLS 18.0
#define SHARDS (CELLS * 0.5)
float hash21(vec2 p) {
    return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}
vec2 hash22(vec2 p) { return vec2(hash21(p), hash21(p + 17.3)); }
mat2 rotate2(float a) {
    float s=sin(a), c=cos(a);
    return mat2(c, -s, s, c);
}
bool inside(vec2 p) { return all(greaterThanEqual(p, vec2(0.0))) && all(lessThan(p, vec2(1.0))); }
vec4 sourceAt(vec2 p) {
    if (!inside(p)) return vec4(0.0);
    return texture(tex, window_rect.xy + p * window_rect.zw);
}
// One jittered seed per grid cell; the shards are the cells around the seeds.
vec2 seedOf(vec2 id) { return id + 0.15 + 0.7 * hash22(id); }
// The shard a point belongs to, and how far it is from that shard's edge.
vec2 shardOf(vec2 s, out float edge) {
    vec2 base=floor(s), best=base;
    float d1=1e9, d2=1e9;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 id=base+vec2(float(x),float(y));
        float d=distance(s,seedOf(id));
        if(d<d1) { d2=d1; d1=d; best=id; } else if(d<d2) d2=d;
    }
    edge=d2-d1;
    return best;
}
void main() {
    float p=clamp(progress,0.0,1.0);
    if(p>=1.0) { fragColor=vec4(0.0); return; }
    if(p<=0.0) { fragColor=texture(tex,v_texcoord); return; }
    vec2 uv=(v_texcoord-window_rect.xy)/max(window_rect.zw,vec2(0.00001));
    // The border and shadow lie outside the window's rect; fade them quickly instead of leaving fragments.
    if(!inside(uv)) { fragColor=texture(tex,v_texcoord)*(1.0-smoothstep(0.0,0.3,p)); return; }
    vec2 pixels=max(surface_size*window_rect.zw,vec2(1.0));
    vec2 gs=vec2(SHARDS, SHARDS*pixels.y/pixels.x);
    vec2 x=uv*gs;
    vec2 impact=vec2(0.5,0.4)*gs;
    vec2 base=floor(x);
    float crack=smoothstep(0.0,0.1,p);
    vec4 result=vec4(0.0);
    // Reverse-map nearby shards: undo each shard's motion for this pixel and keep
    // the hit only if the source point lies inside that shard.
    for(int j=-2;j<=2;j++) for(int i=-2;i<=2;i++) {
        vec2 id=base+vec2(float(i),float(j));
        vec2 c=seedOf(id);
        vec2 h=hash22(id+41.0);
        vec2 away=c-impact;
        vec2 dir=away/max(length(away),0.001);
        float delay=0.30*clamp(length(away/gs)/0.7,0.0,1.0);
        float t=clamp((p-delay)/(1.0-delay),0.0,1.0);
        vec2 offset=dir*(0.5+0.7*h.x)*t+vec2(0.0,0.8*t*t);
        float angle=(h.y-0.5)*3.0*t;
        vec2 s=c+rotate2(-angle)*(x-c-offset);
        float edge;
        if(shardOf(s,edge)!=id) continue;
        vec4 part=sourceAt(s/gs);
        // Crack lines along the shard's edges.
        part.rgb*=1.0-0.6*crack*(1.0-smoothstep(0.0,0.05,edge));
        part*=1.0-smoothstep(0.55,1.0,t);
        result=part+result*(1.0-part.a);
    }
    fragColor=result;
}
