#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Horizontal blinds slide off alternately to the left and right while each strip narrows.
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
    float rows=max(4.0,floor(CELLS*0.6));
    float band=floor(uv.y*rows);
    float f=fract(uv.y*rows);
    float delay=0.4*(band/rows);
    float t=clamp((p-delay)/0.6,0.0,1.0);
    float eased=t*t*(3.0-2.0*t);
    float side=mod(band,2.0)*2.0-1.0;
    // Each strip thins towards its middle as it goes.
    if(abs(f-0.5)>0.5*(1.0-0.6*eased)) { fragColor=vec4(0.0); return; }
    vec2 from=vec2(uv.x-side*eased*1.05, (band+0.5+(f-0.5)/max(1.0-0.6*eased,0.05))/rows);
    fragColor=sourceAt(from)*(1.0-smoothstep(0.7,1.0,t));
}
