#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Digital glitch: bands jump sideways, colour channels split and blocks drop out before it fades.
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
void main() {
    float p=clamp(progress,0.0,1.0);
    if(p>=1.0) { fragColor=vec4(0.0); return; }
    if(p<=0.0) { fragColor=texture(tex,v_texcoord); return; }
    vec2 uv=(v_texcoord-window_rect.xy)/max(window_rect.zw,vec2(0.00001));
    // The border and shadow lie outside the window's rect; fade them quickly instead of leaving fragments.
    if(!inside(uv)) { fragColor=texture(tex,v_texcoord)*(1.0-smoothstep(0.0,0.3,p)); return; }
    vec2 pixels=max(surface_size*window_rect.zw,vec2(1.0));
    float tick=floor(p*14.0);
    float rows=max(6.0,floor(CELLS*1.4));
    float band=floor(uv.y*rows);
    float amount=p*p;
    float hb=hash21(vec2(band,tick));
    float jump=hb>0.55?(hb-0.775)*0.9*amount:0.0;
    vec2 u=vec2(uv.x+jump,uv.y);
    float split=0.02*amount*(0.4+hb);
    vec4 r=sourceAt(u+vec2(split,0.0));
    vec4 g=sourceAt(u);
    vec4 b=sourceAt(u-vec2(split,0.0));
    vec4 color=vec4(r.r,g.g,b.b,max(g.a,max(r.a,b.a)));
    // Blocks drop out at random, more of them as it goes.
    vec2 blocks=vec2(CELLS*1.2,CELLS*0.8);
    if(hash21(floor(uv*blocks)+tick)<amount*0.9) color=vec4(0.0);
    // Scanlines creep in.
    color.rgb*=1.0-0.25*amount*step(0.5,fract(uv.y*pixels.y/3.0));
    color.rgb=min(color.rgb,vec3(color.a));
    fragColor=color*(1.0-smoothstep(0.75,1.0,p));
}
