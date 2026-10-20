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
    // The border and shadow lie outside the window's rect; fade them quickly instead of leaving fragments.
    if(!inside(uv)) { fragColor=texture(tex,v_texcoord)*(1.0-smoothstep(0.0,0.3,p)); return; }
    vec2 grid=gridSize(), cell=floor(uv*grid);
    vec4 result=vec4(0.0);
    // Reverse-map nearby source pieces. Gravity travels at most three rows;
    // a fixed 3x6 neighbourhood avoids a full-window particle search.
    for(int y=-4;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 id=cell+vec2(float(x),float(y));
        if(!inside(id/grid)) continue;
        float n=hash21(id);
        float delay=0.20*n+0.18*(id.y/grid.y);
        float t=clamp((p-delay)/(1.0-delay),0.0,1.0);
        vec2 center=id+0.5;
        vec2 offset=vec2((n-0.5)*0.3*t,3.0*t*t);
        float scale=1.0-0.60*t;
        vec2 local=rotate2((n-0.5)*1.0*t)*(uv*grid-center-offset)/scale;
        if(any(greaterThanEqual(abs(local),vec2(0.5)))) continue;
        float alpha=1.0-smoothstep(0.35,1.0,t);
        vec4 part=sourceAt((center+local)/grid)*alpha;
        result=part+result*(1.0-part.a);
    }
    fragColor=result;
}
