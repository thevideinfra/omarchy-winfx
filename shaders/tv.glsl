#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Old TV switching off: the picture squashes to a bright line, the line shrinks to a dot, and the dot fades.
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
    // Phase one squashes the picture vertically, phase two shrinks the line sideways.
    float squash=smoothstep(0.0,0.55,p);
    float narrow=smoothstep(0.5,0.88,p);
    float height=max(1.0-squash*squash*(3.0-2.0*squash), 2.0/pixels.y);
    float width=max(1.0-narrow*narrow, 0.004);
    vec2 centred=uv-0.5;
    if(abs(centred.y)>height*0.5 || abs(centred.x)>width*0.5) { fragColor=vec4(0.0); return; }
    vec2 from=vec2(centred.x/width, centred.y/height)+0.5;
    vec4 color=sourceAt(from);
    // Scanlines show while the picture is still tall enough to have them.
    float lines=0.5+0.5*sin(from.y*CELLS*18.0);
    color.rgb*=1.0-0.35*lines*(1.0-squash);
    // The picture blows out to white as the beam collapses.
    float glow=smoothstep(0.1,0.6,p);
    color.rgb=mix(color.rgb,vec3(color.a),glow);
    color.rgb=min(color.rgb*(1.0+1.2*glow),vec3(color.a));
    // The last dot fades out.
    fragColor=color*(1.0-smoothstep(0.88,1.0,p));
}
