#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Digital rain: columns of green glyphs sweep down, tinting the window green and wiping it away behind them.
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
    float columns=max(8.0,floor(CELLS*1.5));
    float rows=columns*pixels.y/pixels.x;
    float column=floor(uv.x*columns);
    // Each column's rain starts at its own time and falls at its own speed.
    float start=0.35*hash21(vec2(column,3.0));
    float t=clamp((p-start)/(1.0-start),0.0,1.0);
    float trail=0.4;
    float head=t*(1.0+trail);
    float behind=head-uv.y;
    vec4 src=sourceAt(uv);
    // The window greens over as the rain approaches.
    float lum=dot(src.rgb,vec3(0.3,0.59,0.11));
    float wash=smoothstep(0.0,0.5,p)*0.85;
    vec4 tinted=vec4(mix(src.rgb,vec3(0.05*lum,1.05*lum,0.35*lum),wash),src.a);
    if(behind<0.0) { fragColor=tinted; return; }
    if(behind>trail) { fragColor=vec4(0.0); return; }
    float fade=behind/trail;
    // A glyph per cell: a coarse random bitmap that changes a few times a second.
    vec2 cell=vec2(column,floor(uv.y*rows));
    vec2 inCell=fract(vec2(uv.x*columns,uv.y*rows));
    vec2 bit=floor(inCell*vec2(3.0,5.0));
    float tick=floor(p*24.0);
    float glyph=hash21(cell+bit*7.0+tick*13.0)>0.45 ? 1.0 : 0.0;
    glyph*=step(0.12,inCell.x)*step(inCell.x,0.88)*step(0.1,inCell.y)*step(inCell.y,0.9);
    glyph*=step(hash21(cell+tick),0.9-0.5*fade);
    float bright=(1.0-fade)*(1.0-fade);
    vec3 green=mix(vec3(0.1,0.9,0.35),vec3(0.8,1.0,0.85),step(behind,1.5/rows));
    vec4 rain=vec4(green*bright*glyph,bright*glyph);
    // The window itself is wiped out behind the head.
    vec4 rest=tinted*(1.0-smoothstep(0.0,0.35,fade));
    fragColor=rain+rest*(1.0-rain.a);
}
