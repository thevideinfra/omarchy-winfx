#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Explosion: square chunks blast outward from the centre, spinning and shrinking, after a flash.
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;
uniform vec4 window_rect;
uniform vec2 surface_size;
#define CELLS 18.0
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
vec2 gridSize(vec2 pixels) {
    return vec2(CELLS, max(3.0, floor(CELLS * pixels.y / pixels.x + 0.5)));
}
void main() {
    float p=clamp(progress,0.0,1.0);
    if(p>=1.0) { fragColor=vec4(0.0); return; }
    if(p<=0.0) { fragColor=texture(tex,v_texcoord); return; }
    vec2 uv=(v_texcoord-window_rect.xy)/max(window_rect.zw,vec2(0.00001));
    // The border and shadow lie outside the window's rect; fade them quickly instead of leaving fragments.
    if(!inside(uv)) { fragColor=texture(tex,v_texcoord)*(1.0-smoothstep(0.0,0.3,p)); return; }
    vec2 pixels=max(surface_size*window_rect.zw,vec2(1.0));
    vec2 gs=gridSize(pixels);
    vec2 x=uv*gs, mid=gs*0.5;
    // Every chunk rides one outward scale, so a pixel knows roughly where its chunk started.
    float k=1.0+1.6*pow(p,0.75);
    vec2 base=floor(mid+(x-mid)/k);
    vec4 result=vec4(0.0);
    for(int j=-3;j<=3;j++) for(int i=-3;i<=3;i++) {
        vec2 id=base+vec2(float(i),float(j));
        vec2 c=id+0.5;
        vec2 h=hash22(id);
        vec2 away=c-mid;
        vec2 dir=away/max(length(away),0.001);
        float delay=0.15*clamp(length(away/gs)/0.7,0.0,1.0);
        float t=clamp((p-delay)/(1.0-delay),0.0,1.0);
        vec2 at=mid+away*k+dir*(1.2*h.x)*t+vec2(0.0,t*t);
        float scale=1.0-0.65*t;
        vec2 local=rotate2(-(h.y-0.5)*5.0*t)*(x-at)/scale;
        if(any(greaterThanEqual(abs(local),vec2(0.5)))) continue;
        vec4 part=sourceAt((c+local)/gs)*(1.0-smoothstep(0.3,1.0,t));
        result=part+result*(1.0-part.a);
    }
    // A short white flash at the centre as it goes off.
    vec2 fromMid=(uv-0.5)*vec2(1.0,pixels.y/pixels.x);
    float flash=(1.0-smoothstep(0.0,0.22,p))*(1.0-clamp(length(fromMid)*2.0,0.0,1.0));
    result.rgb=mix(result.rgb,vec3(result.a),flash*0.7);
    fragColor=result;
}
