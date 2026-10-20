#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
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
mat2 rotate2(float a) {
    float s=sin(a), c=cos(a);
    return mat2(c, -s, s, c);
}
bool inside(vec2 p) { return all(greaterThanEqual(p, vec2(0.0))) && all(lessThan(p, vec2(1.0))); }
vec4 sourceAt(vec2 p) {
    if (!inside(p)) return vec4(0.0);
    return texture(tex, window_rect.xy + p * window_rect.zw);
}
vec2 gridSize() {
    vec2 pixels = max(surface_size * window_rect.zw, vec2(1.0));
    return vec2(CELLS, max(3.0, floor(CELLS * pixels.y / pixels.x + 0.5)));
}
void main() {
    float p=clamp(progress,0.0,1.0);
    if(p>=1.0) { fragColor=vec4(0.0); return; }
    if(p<=0.0) { fragColor=texture(tex,v_texcoord); return; }
    vec2 uv=(v_texcoord-window_rect.xy)/max(window_rect.zw,vec2(0.00001));
    if(!inside(uv)) { fragColor=vec4(0.0); return; }
    vec2 pixels=max(surface_size*window_rect.zw,vec2(1.0));
    float block=mix(1.0,pixels.x/CELLS*3.0,p*p);
    vec2 grid=max(vec2(1.0),pixels/max(block,1.0));
    vec2 sampleUv=(floor(uv*grid)+0.5)/grid;
    vec4 mosaic=sourceAt(clamp(sampleUv,vec2(0.00001),vec2(0.99999)));
    vec4 original=sourceAt(uv);
    fragColor=mix(original,mosaic,smoothstep(0.0,0.16,p))*(1.0-smoothstep(0.25,1.0,p));
}
