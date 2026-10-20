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
    vec2 cells=gridSize()*3.0;
    float n=hash21(floor(uv*cells));
    // Threshold range extends past both ends so no cells remain at completion.
    float mask=1.0-smoothstep(n,n+0.12,p*1.12);
    fragColor=texture(tex,v_texcoord)*mask;
}
